import Foundation

/// Handles streaming chat completions from DeepSeek (OpenAI-compatible SSE).
actor AIService {
    private var currentTask: Task<Void, Never>?

    /// Cancel any in-flight streaming request.
    func cancel() { currentTask?.cancel(); currentTask = nil }

    private nonisolated func buildEndpoint(baseURL: String, suffix: String, provider: AIProvider? = nil) -> String {
        var base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.hasSuffix("/") { base.removeLast() }

        if base.hasSuffix("/v1") {
            return base + suffix
        } else if suffix.hasPrefix("/api/") {
            return base + suffix
        } else {
            return base + "/v1" + suffix
        }
    }

    /// Test connection and fetch available models based on the provider.
    nonisolated func fetchAvailableModels(baseURL: String, apiKey: String, provider: AIProvider) async throws -> [String] {
        var endpoint: String
        var request: URLRequest

        switch provider {
        case .deepseek, .openAICompatible, .mstyOllama, .mstyMLX:
            endpoint = buildEndpoint(baseURL: baseURL, suffix: "/models")
            guard let url = URL(string: endpoint) else { throw URLError(.badURL) }
            request = URLRequest(url: url)
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        case .ollama:
            endpoint = baseURL.hasSuffix("/") ? baseURL + "api/tags" : baseURL + "/api/tags"
            guard let url = URL(string: endpoint) else { throw URLError(.badURL) }
            request = URLRequest(url: url)
        case .anthropic:
            endpoint = buildEndpoint(baseURL: baseURL, suffix: "/models")
            guard let url = URL(string: endpoint) else { throw URLError(.badURL) }
            request = URLRequest(url: url)
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        }

        request.httpMethod = "GET"
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                let errorMsg = parseErrorMessage(statusCode: http.statusCode)
                throw NSError(domain: "APIError", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMsg])
            }

            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

            // 1. Try OpenAI/Anthropic "data" format first (e.g. {"data": [{"id": "model-name"}, ...]})
            if let dataArr = json?["data"] as? [[String: Any]] {
                let ids = dataArr.compactMap { $0["id"] as? String }
                if !ids.isEmpty { return ids }
            }

            // 2. Try Ollama native "models" format (e.g. {"models": [{"name": "model:tag"}, ...]})
            if let modelsArr = json?["models"] as? [[String: Any]] {
                let names = modelsArr.compactMap { ($0["name"] as? String) ?? ($0["id"] as? String) }
                if !names.isEmpty { return names }
            }

            return []
        } catch let nsError as NSError {
            if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCannotConnectToHost {
                throw NSError(domain: "APIError", code: nsError.code, userInfo: [NSLocalizedDescriptionKey: "无法连接服务，如果使用本地 Ollama 请确认服务已启动"])
            }
            throw nsError
        }
    }

    nonisolated private func parseErrorMessage(statusCode: Int) -> String {
        switch statusCode {
        case 401: return "API Key 无效，请检查是否复制完整"
        case 403: return "API Key 有效，但没有访问该资源的权限"
        case 404: return "Base URL 或 API 路径不正确"
        case 429: return "请求过于频繁或额度不足"
        case 500, 502, 503: return "服务商暂时不可用，请稍后再试"
        default: return "HTTP 错误: \(statusCode)"
        }
    }

    /// Stream a chat completion. Calls `onChunk` on the MainActor for each delta.
    func stream(
        apiKey: String,
        baseURL: String = "https://api.deepseek.com",
        prompt: String,
        systemPrompt: String,
        model: String = "deepseek-v4-flash",
        provider: AIProvider = .deepseek,
        enableThinking: Bool = false,
        context: String? = nil, // 可选的上下文（如当前剧本内容），利于命中 Context Cache
        failoverProviders: [(provider: AIProvider, apiKey: String, baseURL: String, model: String)] = [],
        onChunk: @MainActor @Sendable @escaping (String) -> Void,
        onDone: @MainActor @Sendable @escaping () -> Void,
        onError: @MainActor @Sendable @escaping (String) -> Void
    ) {
        cancel()

        // Try primary provider first, then failover providers
        attemptStream(
            apiKey: apiKey,
            baseURL: baseURL,
            prompt: prompt,
            systemPrompt: systemPrompt,
            model: model,
            provider: provider,
            enableThinking: enableThinking,
            context: context,
            failoverProviders: failoverProviders,
            failoverIndex: 0,
            onChunk: onChunk,
            onDone: onDone,
            onError: onError
        )
    }

    private func attemptStream(
        apiKey: String,
        baseURL: String,
        prompt: String,
        systemPrompt: String,
        model: String,
        provider: AIProvider,
        enableThinking: Bool,
        context: String?,
        failoverProviders: [(provider: AIProvider, apiKey: String, baseURL: String, model: String)],
        failoverIndex: Int,
        retryCount: Int = 0,
        maxRetries: Int = 3,
        onChunk: @MainActor @Sendable @escaping (String) -> Void,
        onDone: @MainActor @Sendable @escaping () -> Void,
        onError: @MainActor @Sendable @escaping (String) -> Void
    ) {
        let urlString: String
        switch provider {
        case .ollama:
            urlString = baseURL.hasSuffix("/") ? baseURL + "api/chat" : baseURL + "/api/chat"
        case .anthropic:
            // 检测是否使用官方Anthropic API
            let isOfficialAnthropic = baseURL.contains("api.anthropic.com")
            if isOfficialAnthropic {
                // 官方Anthropic使用原生格式
                urlString = buildEndpoint(baseURL: baseURL, suffix: "/messages")
            } else {
                // 代理服务：AI SDK可能使用原生Anthropic格式
                // 直接使用/messages，不添加/v1前缀
                var base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
                if base.hasSuffix("/") { base.removeLast() }
                urlString = base + "/messages"
            }
        default: // deepseek, openAICompatible, mstyOllama, mstyMLX
            // For now, always use chat/completions for OpenAI-compatible providers
            // The Responses API might not be available on all endpoints
            urlString = buildEndpoint(baseURL: baseURL, suffix: "/chat/completions")
        }
        guard let ep = URL(string: urlString) else {
            Task { @MainActor in onError("无效的 API 地址") }
            return
        }

        currentTask = Task {
            guard !apiKey.isEmpty else {
                await onError("请先在设置中配置 API Key")
                return
            }

            var request = URLRequest(url: ep)
            request.httpMethod = "POST"
            request.timeoutInterval = 60
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            if provider == .anthropic {
                request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            } else {
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            }

            // 检测是否使用官方Anthropic API
            let isOfficialAnthropic = provider == .anthropic && baseURL.contains("api.anthropic.com")

            // 保持 System Prompt 在第一位，确保前缀缓存（Context Caching）的高命中率。
            var messages: [[String: Any]] = []

            // 代理服务使用原生Anthropic格式（system在顶层）
            if provider == .anthropic && !isOfficialAnthropic {
                // 不在messages中添加system role
            } else {
                // OpenAI兼容格式使用标准messages数组
                messages.append(["role": "system", "content": systemPrompt])
            }

            // 如果有上下文（当前剧本），以纯中立的背景资料形式提供。
            if let context = context, !context.isEmpty {
                messages.append(["role": "user", "content": "背景资料：\n\(context)"])
            }

            // 尾部指令增强 (Tail Instruction Reinforcement)
            // 利用大模型的末端注意力机制，防止模型在长上下文后产生"指令漂移"。
            // 重点提醒：结合背景但不重复背景，直接回答。
            let reinforcedPrompt = """
            \(prompt)

            (请直接针对问题进行回复。注意：请结合你的角色设定和背景资料进行专业回答，但无需再次介绍背景或复述身份，保持自然口语化。)
            """
            messages.append(["role": "user", "content": reinforcedPrompt])

            var body: [String: Any]
            let lowerModel = model.lowercased()

            // Use standard Chat Completions API format for all providers
            body = [
                "model": model,
                "stream": true,
                "messages": messages,
                "max_tokens": 4096
            ]

            // GPT 5.5 特定配置（根据官方配置）
            if provider == .openAICompatible && lowerModel.contains("gpt-5") {
                body["store"] = false
                if enableThinking {
                    // 使用官方配置的variants
                    body["reasoning_effort"] = "xhigh"
                }
            }

            // 为推理模型自动管理思考模式（仅针对DeepSeek）
            if provider == .deepseek {
                if enableThinking {
                    body["thinking"] = ["type": "enabled", "budget_tokens": 4096]
                    if lowerModel.contains("r1") || lowerModel.contains("pro") || lowerModel.contains("reasoning") {
                        body["reasoning_effort"] = "high"
                    }
                } else {
                    body["thinking"] = ["type": "disabled"]
                }
                body["stream_options"] = ["include_usage": true]
            }

            // Anthropic特殊处理（包括官方和代理）
            if provider == .anthropic {
                body["system"] = systemPrompt // Anthropic system prompt is top-level
                if lowerModel.contains("sonnet") || lowerModel.contains("opus") {
                     // 为高性能 Claude 模型尝试开启思考模式
                     body["thinking"] = ["type": "enabled", "budget_tokens": 1024]
                }
            }
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)

            do {
                let (bytes, response) = try await URLSession.shared.bytes(for: request)

                if let http = response as? HTTPURLResponse {
                    if http.statusCode != 200 {
                        await onError("API 返回错误: HTTP \(http.statusCode)")
                        return
                    }
                }

                var isThinking = false

                for try await line in bytes.lines {
                    if Task.isCancelled { break }

                    guard line.hasPrefix("data: ") else { continue }
                    let payload = String(line.dropFirst(6))

                    if payload == "[DONE]" {
                        break
                    }

                    guard let data = payload.data(using: .utf8),
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                    else {
                        continue
                    }

                    // 统一使用标准 Chat Completions 格式解析（包括GPT 5.5）
                    if let choices = json["choices"] as? [[String: Any]],
                       let first = choices.first,
                       let delta = first["delta"] as? [String: Any] {

                        // 优先处理推理内容（深度思考）
                        if let reasoning = delta["reasoning_content"] as? String {
                            if !isThinking {
                                await onChunk("<think>\n")
                                isThinking = true
                            }
                            await onChunk(reasoning)
                        }

                        // 处理正式回复内容
                        if let content = delta["content"] as? String {
                            if isThinking {
                                await onChunk("\n</think>\n\n")
                                isThinking = false
                            }
                            await onChunk(content)
                        }
                    }

                    // Anthropic 格式 (支持 content_block_delta 和 thinking)
                    if provider == .anthropic, let type = json["type"] as? String {
                        if type == "content_block_delta",
                           let delta = json["delta"] as? [String: Any] {

                            // Anthropic Thinking Block
                            if let thinking = delta["thinking"] as? String {
                                if !isThinking {
                                    await onChunk("<think>\n")
                                    isThinking = true
                                }
                                await onChunk(thinking)
                            }

                            // Anthropic Text Block
                            if let content = delta["text"] as? String {
                                if isThinking {
                                    await onChunk("\n</think>\n\n")
                                    isThinking = false
                                }
                                await onChunk(content)
                            }
                        }
                    }
                    // Provider usage metadata is intentionally ignored here.
                    // Never log prompt, context, reasoning, or streamed content.
                }

                if !Task.isCancelled {
                    await onDone()
                }
            } catch is CancellationError {
                // Normal cancellation
            } catch {
                if !Task.isCancelled {
                    let nsError = error as NSError

                    // Retry logic for network errors
                    if retryCount < maxRetries && (nsError.domain == NSURLErrorDomain || nsError.code == -1001 || nsError.code == -1005) {
                        try? await Task.sleep(nanoseconds: UInt64(1_000_000_000 * (retryCount + 1))) // Exponential backoff

                        attemptStream(
                            apiKey: apiKey,
                            baseURL: baseURL,
                            prompt: prompt,
                            systemPrompt: systemPrompt,
                            model: model,
                            provider: provider,
                            enableThinking: enableThinking,
                            context: context,
                            failoverProviders: failoverProviders,
                            failoverIndex: failoverIndex,
                            retryCount: retryCount + 1,
                            maxRetries: maxRetries,
                            onChunk: onChunk,
                            onDone: onDone,
                            onError: onError
                        )
                    } else if failoverIndex < failoverProviders.count {
                        // Try failover if available
                        let nextProvider = failoverProviders[failoverIndex]
                        attemptStream(
                            apiKey: nextProvider.apiKey,
                            baseURL: nextProvider.baseURL,
                            prompt: prompt,
                            systemPrompt: systemPrompt,
                            model: nextProvider.model,
                            provider: nextProvider.provider,
                            enableThinking: enableThinking,
                            context: context,
                            failoverProviders: failoverProviders,
                            failoverIndex: failoverIndex + 1,
                            retryCount: 0,
                            maxRetries: maxRetries,
                            onChunk: onChunk,
                            onDone: onDone,
                            onError: onError
                        )
                    } else {
                        await onError("网络错误: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
}
