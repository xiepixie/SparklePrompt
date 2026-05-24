import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers

struct PromptPresentationStyle {
    let backgroundColor: Color
    let primaryTextColor: Color
    let secondaryTextColor: Color
    let codeTextColor: Color
    let accentColor: Color
    let textOpacityMultiplier: Double
    let panelOpacityMultiplier: Double
    let hintOpacity: Double
    let dividerOpacity: Double
    let subtleFillOpacity: Double
    let panelBorderOpacity: Double
    let shadowOpacity: Double
    let shadowRadius: CGFloat
    let shadowYOffset: CGFloat
    let blurRadius: CGFloat
    let fontSize: CGFloat
}

/// Represents a keyboard shortcut with modifiers and a key.
struct Shortcut: Codable, Equatable {
    var key: String
    var keyCode: UInt16
    var modifiers: UInt

    var normalizedModifiers: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifiers).intersection([.command, .option, .shift, .control])
    }

    var displayString: String {
        let displayKey = key == " " ? "Space" : key.uppercased()
        return keySymbols.joined() + displayKey
    }

    var keySymbols: [String] {
        var symbols: [String] = []
        let flags = normalizedModifiers
        if flags.contains(.control) { symbols.append("⌃") }
        if flags.contains(.option) { symbols.append("⌥") }
        if flags.contains(.shift) { symbols.append("⇧") }
        if flags.contains(.command) { symbols.append("⌘") }
        return symbols
    }
}

struct AIRole: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var prompt: String
}

enum AIProvider: String, Codable, CaseIterable {
    case deepseek = "DeepSeek"
    case openAICompatible1 = "OpenAI 兼容 1"
    case openAICompatible2 = "OpenAI 兼容 2"
    case anthropic = "Anthropic"
    case ollama = "Ollama 原生"
    case mstyOllama = "Msty Ollama"
    case mstyMLX = "Msty MLX"

    var defaultBaseURL: String {
        switch self {
        case .deepseek: return "https://api.deepseek.com"
        case .openAICompatible1, .openAICompatible2: return "https://api.openai.com"
        case .anthropic: return "https://api.anthropic.com"
        case .ollama: return "http://localhost:11434"
        case .mstyOllama: return "http://localhost:11964/v1"
        case .mstyMLX: return "http://localhost:11973/v1"
        }
    }

    var isLocal: Bool {
        switch self {
        case .ollama, .mstyOllama, .mstyMLX:
            return true
        default:
            return false
        }
    }
}

enum ProviderStatus: Equatable {
    case notConfigured
    case localReady
    case waitingForTest
    case testing
    case success(modelCount: Int)
    case configError(code: Int, message: String)
    case networkError(message: String)
    case customError(message: String)

    var displayText: String {
        switch self {
        case .notConfigured: return "未配置 API Key"
        case .localReady: return "本地服务就绪"
        case .waitingForTest: return "等待测试连接"
        case .testing: return "正在验证连接..."
        case .success(let count): return "测试成功，可使用 \(count) 个模型"
        case .configError(let code, let msg): return "配置错误 (HTTP \(code)): \(msg)"
        case .networkError(let msg): return "网络错误: \(msg)"
        case .customError(let msg): return msg
        }
    }

    var color: Color {
        switch self {
        case .localReady, .success: return .green
        case .configError, .networkError, .notConfigured: return .red
        case .waitingForTest, .testing, .customError: return .yellow
        }
    }
}


enum ShortcutAction: String, CaseIterable, Codable {
    case playPause = "播放/暂停"
    case reset = "重置"
    case toggleLibrary = "剧本库"
    case prevScript = "上一个剧本"
    case nextScript = "下一个剧本"
    case aiPrompt = "AI 面板"
    case toggleControls = "控制栏"
    case toggleAlwaysOnTop = "置顶"
    case paste = "粘贴"
    case toggleTimer = "计时器开关"
    case resetTimer = "计时器重置"
    case toggleEdit = "编辑剧本"
    case prevWorkspace = "上一个工作区"
    case nextWorkspace = "下一个工作区"
    case increaseFontSize = "增大字号"
    case decreaseFontSize = "减小字号"
    case increaseBgOpacity = "增加背景暗度"
    case decreaseBgOpacity = "减小背景暗度"
    case increaseTextOpacity = "增加文字不透明度"
    case decreaseTextOpacity = "减小文字不透明度"
    case togglePrivacy = "隐私防护"
    case toggleMirrorH = "水平镜像"
    case toggleMirrorV = "垂直镜像"
}

@MainActor
final class SparklePromptViewModel: ObservableObject {
    /// Shared constant for sidebar width — used in View, AppDelegate, and KeyEventBridge.
    static let sidebarWidth: CGFloat = 250

    // MARK: - AI Shadow Directory
    /// AI 生成的剧本存储在 App 专属目录，不污染用户原始文件夹
    static let aiScriptsDirectory: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("SparklePrompt/ai_scripts", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// 获取特定工作区的 AI 剧本存储目录
    static func aiDirectory(for workspaceId: UUID) -> URL {
        let dir = aiScriptsDirectory.appendingPathComponent(workspaceId.uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Core playback state
    @Published var text: String = SparklePromptViewModel.defaultText {
        didSet {
            isCodeDetected = text.contains("```")
            textUpdateSubject.send()
        }
    }
    @Published var isCodeMode: Bool = false {
        didSet {
            updateAttributedText()
            if !isInternalLoading { saveSubject.send() }
        }
    }
    @Published var enableDeepSeekThinking: Bool = false {
        didSet { if !isInternalLoading { saveSubject.send() } }
    }
    private(set) var isCodeDetected: Bool = false

    // MARK: - Line Rendering Cache
    private static let maxLineCacheEntries = 25_000
    private static let markdownProbeCharacters = CharacterSet(charactersIn: "#*_`[]!>\\")
    private var lineCache: [String: AttributedString] = [:]
    private var suppressNextTextUpdate = false
    private var renderingTask: Task<Void, Never>?

    private struct LineRangeInfo {
        let range: NSRange
        let styleType: StyleType
    }
    
    private enum StyleType {
        case think
        case code
        case normal
    }

    private static func mayContainMarkdown(_ line: String) -> Bool {
        line.rangeOfCharacter(from: markdownProbeCharacters) != nil
    }

    private static func parseLineMarkdown(_ line: String) -> AttributedString {
        let leadingWhitespace = line.prefix { $0 == " " || $0 == "\t" }
        let trimmedLine = String(line.dropFirst(leadingWhitespace.count))
        
        var parsed: AttributedString
        if mayContainMarkdown(trimmedLine) {
            parsed = (try? AttributedString(markdown: trimmedLine)) ?? AttributedString(trimmedLine)
        } else {
            parsed = AttributedString(trimmedLine)
        }
        
        if !leadingWhitespace.isEmpty {
            var indented = AttributedString(String(leadingWhitespace))
            indented.append(parsed)
            return indented
        } else {
            return parsed
        }
    }
    @Published var isPlaying: Bool = false
    @Published var speed: Double = 45 { didSet { if !isInternalLoading { saveSubject.send() } } }
    @Published var fontSize: Double = 20 {
        didSet {
            updateAttributedText()
            if !isInternalLoading { saveSubject.send() }
        }
    }
    @Published var lineSpacing: Double = 10 {
        didSet {
            updateAttributedText()
            if !isInternalLoading { saveSubject.send() }
        }
    }
    @Published var textOpacity: Double = 1.0 { didSet { if !isInternalLoading { saveSubject.send() } } }
    @Published var bgOpacity: Double = 0.65 { didSet { if !isInternalLoading { saveSubject.send() } } }
    @Published var privacyBlurRadius: CGFloat = 1.0 { didSet { if !isInternalLoading { saveSubject.send() } } }
    @Published var mirroredHorizontal: Bool = false
    @Published var mirroredVertical: Bool = false
    @Published var showControls: Bool = true
    @Published var isEditing: Bool = false {
        didSet {
            if isEditing && isPrivacyMode {
                isEditing = false
                return
            }
            if isEditing {
                showSettings = false
                showAIPromptBar = false
            } else {
                // 退出编辑：一次性刷新格式化文本并触发保存
                updateAttributedText()
                saveSubject.send()
            }
            updateWindowInteractionState()
        }
    }

    @Published var scrollOffset: CGFloat = 0
    @Published var contentHeight: CGFloat = 0 {
        didSet {
            // ✨ 核心优化：只有当内容高度真正变化时，才触发跟随滚动
            // 这确保了滚动目标值是基于最新渲染后的高度，消除了抖动和延迟感
            if isAIStreaming && autoFollowEnabled {
                scrollToBottom()
            }
        }
    }
    @Published var viewportHeight: CGFloat = 0

    @Published var textColor: Color = .white {
        didSet {
            updateAttributedText()
            if !isInternalLoading { saveSubject.send() }
        }
    }
    @Published var readingLineColor: Color = Color(red: 245/255, green: 158/255, blue: 11/255) { didSet { if !isInternalLoading { saveSubject.send() } } }
    @Published var accentColor: Color = Color(red: 139/255, green: 92/255, blue: 246/255) {
        didSet {
            updateAttributedText()
            if !isInternalLoading { saveSubject.send() }
        }
    }
    @Published var alwaysOnTop: Bool = true {
        didSet {
            // 🔒 强制一致性：如果开启了隐私模式，置顶状态不允许被设为 false
            if isPrivacyMode && !alwaysOnTop {
                alwaysOnTop = true
                return
            }
            windowController?.setAlwaysOnTop(alwaysOnTop)
            if !isInternalLoading { saveSubject.send() }
        }
    }

    private let privacyExitConfirmationInterval: TimeInterval = 1.5
    private var privacyExitConfirmationDeadline: Date?
    private var lastPrivacyTransitionTime: Date = Date.distantPast

    @Published var isPrivacyMode: Bool = false {
        didSet {
            updateAttributedText()
            windowController?.setStealthMode(isPrivacyMode)
            windowController?.setHideFromCapture(isPrivacyMode)
            if isPrivacyMode {
                alwaysOnTop = true
                showControls = false
                privacyExitConfirmationDeadline = nil
            } else {
                showControls = true
            }
            if !isInternalLoading {
                // ⚡️ 立即同步写入 isPrivacyMode，不走 debounce 管线
                // 防止 setStealthMode 触发 UserDefaults.didChangeNotification
                // 在 saveSubject debounce 完成前读取到旧值并覆盖回来
                UserDefaults.standard.set(isPrivacyMode, forKey: "Pref_isPrivacyMode")
                saveSubject.send()
            }
        }
    }

    var presentationStyle: PromptPresentationStyle {
        if isPrivacyMode {
            return PromptPresentationStyle(
                backgroundColor: Color(red: 30/255, green: 30/255, blue: 30/255),
                primaryTextColor: Color(red: 65/255, green: 65/255, blue: 65/255),
                secondaryTextColor: Color(red: 70/255, green: 70/255, blue: 70/255),
                codeTextColor: Color(red: 65/255, green: 65/255, blue: 65/255),
                accentColor: Color(red: 75/255, green: 75/255, blue: 75/255),
                textOpacityMultiplier: 0.35,
                panelOpacityMultiplier: 0.35,
                hintOpacity: 0.3,
                dividerOpacity: 0.0,
                subtleFillOpacity: 0.0,
                panelBorderOpacity: 0.0,
                shadowOpacity: 0.15,
                shadowRadius: 1,
                shadowYOffset: 0.5,
                blurRadius: privacyBlurRadius,
                fontSize: CGFloat(fontSize)
            )
        }

        return PromptPresentationStyle(
            backgroundColor: .black,
            primaryTextColor: textColor,
            secondaryTextColor: .white,
            codeTextColor: textColor.opacity(0.9),
            accentColor: accentColor,
            textOpacityMultiplier: 1.0,
            panelOpacityMultiplier: 1.0,
            hintOpacity: 0.3,
            dividerOpacity: 0.1,
            subtleFillOpacity: 0.06,
            panelBorderOpacity: 0.15,
            shadowOpacity: 0.8,
            shadowRadius: 3,
            shadowYOffset: 1,
            blurRadius: 0,
            fontSize: CGFloat(fontSize)
        )
    }

    /// ✨ 幽灵模式控制中心 (唯一控制逻辑)
    @Published var mousePenetration: Bool = false {
        didSet { updateWindowInteractionState() }
    }
    @Published var isGhostModePending: Bool = false
    @Published var ghostModeCountdown: Int = 0        // 准备期倒计时
    @Published var ghostModeTimeRemaining: Int = 0    // 执行期剩余时间
    @Published var ghostModeDuration: Double = 300    // 执行期总时长 (默认 5 分钟)

    // 幽灵模式相关计时器
    private var ghostPrepTimer: Timer?
    private var ghostRunTimer: Timer?

    func requestGhostMode() {
        guard !mousePenetration else { return }
        showSettings = false
        showAIPromptBar = true

        // 切换显示模式为准备期
        timerDisplayMode = .ghostPrep
        isGhostModePending = true
        ghostModeCountdown = 3

        ghostPrepTimer?.invalidate()
        ghostPrepTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                if self.ghostModeCountdown > 1 {
                    self.ghostModeCountdown -= 1
                } else {
                    self.startGhostSession()
                }
            }
        }
    }

    func cancelGhostPrep() {
        isGhostModePending = false
        ghostPrepTimer?.invalidate()
        ghostPrepTimer = nil
    }

    private func startGhostSession() {
        cancelGhostPrep()

        // 🔒 核心安全锁定：开启穿透、隐私与置顶
        mousePenetration = true
        isPrivacyMode = true
        alwaysOnTop = true

        // 🧹 清理 UI：关闭设置和剧本库，但保留底部栏（因为计时器在那里）
        showSettings = false
        isEditing = false
        showLibrary = false
        showControls = true
        showAIPromptBar = true

        ghostModeTimeRemaining = Int(ghostModeDuration)

        // 切换显示模式为运行期
        timerDisplayMode = .ghostRun

        // 确保进入即开始播放
        if !isPlaying {
            togglePlay()
        } else {
            start()
        }

        ghostRunTimer?.invalidate()
        ghostRunTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                if self.ghostModeTimeRemaining > 1 {
                    self.ghostModeTimeRemaining -= 1
                } else {
                    self.terminateGhostMode()
                }
            }
        }
    }

    func terminateGhostMode() {
        mousePenetration = false
        isGhostModePending = false
        ghostModeTimeRemaining = 0
        timerDisplayMode = .speech // 恢复普通计时显示
        ghostRunTimer?.invalidate()
        ghostPrepTimer?.invalidate()
        ghostRunTimer = nil
        ghostPrepTimer = nil
    }
    // MARK: - Timer State (Unified Architecture)
    enum TimerDisplayMode {
        case speech      // 普通演讲计时（正向）
        case ghostPrep   // 幽灵准备（倒计时 3, 2, 1）
        case ghostRun    // 幽灵运行（锁定倒计时）
    }

    @Published var timerDisplayMode: TimerDisplayMode = .speech
    @Published var timerElapsedTime: Int = 0        // 演讲已用时
    @Published var isTimerActive: Bool = false      // 演讲计时是否激活
    private var speechTimer: Timer?                 // 演讲计时器

    // MARK: - Script Library (Workspace Architecture)
    @Published var workspaces: [Workspace] = [Workspace(name: "收集箱", scripts: [])]
    @Published var activeWorkspaceIndex: Int = 0
    @Published var activeScriptIndex: Int = -1

    // MARK: - UI Display Helpers

    var cleanedModelName: String {
        cleanModelName(aiModel)
    }

    func cleanModelName(_ model: String) -> String {
        // 1. Remove everything before the first '/' if present
        let baseName = model.split(separator: "/").last.map(String.init) ?? model

        // 2. Limit maximum length and add ellipsis if needed
        let maxLength = 20
        if baseName.count > maxLength {
            return String(baseName.prefix(maxLength)) + "..."
        }
        return baseName
    }

    var currentScriptNameShort: String {
        guard activeWorkspaceIndex >= 0 && activeWorkspaceIndex < workspaces.count,
              activeScriptIndex >= 0 && activeScriptIndex < workspaces[activeWorkspaceIndex].scripts.count else {
            return "无剧本"
        }
        let name = workspaces[activeWorkspaceIndex].scripts[activeScriptIndex].title
        let maxLength = 12
        if name.count > maxLength {
            return String(name.prefix(maxLength)) + "..."
        }
        return name
    }
    @Published var showLibrary: Bool = false {
        didSet {
            if oldValue != showLibrary {
                windowController?.toggleSidebar(show: showLibrary)
            }
        }
    }

    @Published var scriptSearchQuery: String = "" {
        didSet {
            // Trigger debounced update
            searchSubject.send(scriptSearchQuery)
        }
    }
    @Published var debouncedSearchQuery: String = ""
    private let searchSubject = PassthroughSubject<String, Never>()
    @Published var attributedText: AttributedString = AttributedString("")

    // MARK: - AI Configuration (persisted via settings window)

    /// Guard flag to prevent child property didSet handlers from writing back
    /// to provider dictionaries during a cascading provider switch.
    private var isUpdatingProvider = false

    @Published var aiProvider: AIProvider = .deepseek {
        didSet {
            guard !isUpdatingProvider else { return }
            isUpdatingProvider = true
            defer { isUpdatingProvider = false }

            // Restore from per-provider storage
            self.aiAPIKey = providerKeys[aiProvider] ?? (((aiProvider == .mstyOllama || aiProvider == .mstyMLX)) ? "not-needed" : "")
            self.aiBaseURL = providerURLs[aiProvider] ?? aiProvider.defaultBaseURL
            self.availableModels = providerModels[aiProvider] ?? []
            self.aiModel = providerSelectedModels[aiProvider] ?? ""
            self.apiTestStatus = providerStatuses[aiProvider]?.displayText

            // On-demand load key if NOT already in memory cache
            if (self.aiAPIKey.isEmpty || providerKeys[aiProvider] == nil) && aiProvider != .mstyOllama && aiProvider != .mstyMLX {
                Task { await loadActiveProviderKey() }
            }

            if !isInternalLoading {
                saveSubject.send()
                // 自动触发测试与模型刷新
                fetchModels()
            }
        }
    }

    @Published var aiAPIKey: String = "" { didSet { if !isUpdatingProvider { providerKeys[aiProvider] = aiAPIKey }; if !isInternalLoading { saveSubject.send() } } }
    @Published var aiModel: String = "" { didSet { if !isUpdatingProvider { providerSelectedModels[aiProvider] = aiModel }; if !isInternalLoading { saveSubject.send() } } }
    @Published var aiBaseURL: String = "https://api.deepseek.com" { didSet { if !isUpdatingProvider { providerURLs[aiProvider] = aiBaseURL }; if !isInternalLoading { saveSubject.send() } } }
    @Published var availableModels: [String] = [] { didSet { if !isUpdatingProvider { providerModels[aiProvider] = availableModels }; if !isInternalLoading { saveSubject.send() } } }

    // MARK: - Provider Priority and Failover
    @Published var providerPriority: [AIProvider] = [.deepseek, .openAICompatible1, .openAICompatible2, .anthropic, .ollama, .mstyOllama, .mstyMLX] { didSet { if !isInternalLoading { saveSubject.send() } } }
    @Published var enableFailover: Bool = true { didSet { if !isInternalLoading { saveSubject.send() } } }

    // MARK: - Per-provider persistence dictionaries
    private var providerKeys: [AIProvider: String] = [:]
    private var providerURLs: [AIProvider: String] = [:]
    private var providerModels: [AIProvider: [String]] = [:]
    private var providerSelectedModels: [AIProvider: String] = [:]
    @Published var providerStatuses: [AIProvider: ProviderStatus] = [:]

    @Published var aiRoles: [AIRole] = [
        AIRole(name: "LeetCode 刷题助手", prompt: #"""
你是一个顶尖的 LeetCode 刷题专家与算法教练。

## 核心任务
帮助用户解答 LeetCode 算法题，特别擅长识别中英文混合、拼音、数字、代码缩写等高噪输入。你的输出必须极度精简，拒绝任何多余的套话与啰唆解释。

## 交互流程（关键）
1. **理解与确认评估**：
   - 仔细评估用户的输入。如果题目描述或补充说明中存在明显歧义、信息缺失（如不知道数据范围、边界限制、输入输出格式），或可能影响算法选择（如 O(N) vs O(NlogN)），你必须立即停止输出解答，用极简的语言向用户提问以澄清不确定点。
   - 如果信息完整、无歧义，则直接进入解答阶段。

2. **解答输出结构（仅在确认理解无误时提供，拒绝废话）**：
   - **【核心思路】**：仅用 1-2 句话陈述你对题意的理解及选择该算法的核心理由（例如：“此题为经典的双指针问题，通过维护左右窗口边界可以在 O(N) 时间内求得最长子串”）。
   - **【Python 代码】**：提供 LeetCode 可直接提交的高质量 Python3 代码。代码中应包含关键位置的超精炼单行注释。
   - **【边界与极值分析】**：列出 2-3 个容易被忽视的边界测试点（如空输入、单元素、极大值、负数等）以及针对性处理。
   - **【极简执行步骤】**：按代码执行顺序（初始化 -> 循环/更新逻辑 -> 返回值），使用极度精炼的步骤说明其运作机制。

## 规则限制
- 默认且仅使用 Python3。
- 选择兼顾“最优复杂度”与“面试高容错/易写性”的解法，不写过度炫技或难以复现的代码。
- 拒绝任何如“好的，我明白了”、“接下来为你分析”等无意义的前缀/后缀客套话。
"""#),
        AIRole(name: "模拟面试", prompt: "你是一名有经验的面试官，正在模拟面试。请直接输出正文。")
    ] { didSet { if !isInternalLoading { saveSubject.send() } } }
    @Published var selectedRoleIndex: Int = 0 { didSet { if !isInternalLoading { saveSubject.send() } } }

    /// ✨ 个人风格偏好：作为 System Prompt 的稳定前缀，提升缓存命中率并保持一致性
    @Published var aiPersonalStyle: String = "" { didSet { if !isInternalLoading { saveSubject.send() } } }

    @Published var autoFollowEnabled: Bool = true { didSet { if !isInternalLoading { saveSubject.send() } } }
    @Published var useWorkspaceContextForAI: Bool = false { didSet { if !isInternalLoading { saveSubject.send() } } } // ✨ 新增：是否将整个工作区作为上下文
    @Published var useAnyContextForAI: Bool = true { didSet { if !isInternalLoading { saveSubject.send() } } } // 是否使用任何背景资料（当前文本或工作区）
    @Published var isTestingAPI: Bool = false
    @Published var apiTestStatus: String? = nil

    // MARK: - Customizable Shortcuts
    @Published var shortcuts: [ShortcutAction: Shortcut] = [:]
    private let shortcutsKey = "UserShortcuts_v2"
    private let workspacesKey = "UserWorkspaces_v1"
    private let oldLibraryKey = "UserScriptLibrary_v1" // For migration

    // MARK: - AI Runtime state
    @Published var isAIStreaming: Bool = false
    @Published var showAIPromptBar: Bool = false {
        didSet {
            if showAIPromptBar {
                showSettings = false
                isEditing = false
            }
            updateWindowInteractionState()
        }
    }
    @Published var aiPrompt: String = ""
    @Published var aiErrorMessage: String = ""
    @Published var showSettings: Bool = false {
        didSet {
            if showSettings {
                isEditing = false
                showAIPromptBar = false
            }
            updateWindowInteractionState()
            if !isInternalLoading { saveSubject.send() }
        }
    }

    let aiService = AIService()

    weak var windowController: AppDelegate?

    private var displayLink: DisplayLink?
    private var lastFrameTime: Double = 0
    private var saveSubject = PassthroughSubject<Void, Never>()
    private var cancellables = Set<AnyCancellable>()
    private var isResetting = false
    private let textUpdateSubject = PassthroughSubject<Void, Never>()

    @Published var showSaveStatus: Bool = false
    @Published var refreshingWorkspaceId: UUID? = nil // ✨ 正在刷新的工作区 ID，用于驱动旋转动画

    private var isInternalSaving = false
    private var isInternalLoading = false

    /// ✨ 核心逻辑：智能判断当前是否应该开启鼠标穿透
    /// 只有在用户开启了穿透，且当前没有打开任何交互面板（设置、编辑、AI）时才真正生效
    func updateWindowInteractionState() {
        let shouldPenetrate = mousePenetration && !showSettings && !isEditing && !showAIPromptBar
        windowController?.setMousePenetration(shouldPenetrate)
    }

    /// Tracks whether initial async loading (Keychain) has completed.
    /// Prevents saveSubject sink from persisting empty/default values
    /// before AI settings have been loaded from Keychain.
    private var hasCompletedInitialLoad = false

    init() {
        loadVisualSettings()
        loadShortcuts()
        Task { @MainActor in
            await loadAISettings()
            hasCompletedInitialLoad = true
        }
        loadLibrary()

        // Debounce all persistence (max once every 1 second for better responsiveness)
        saveSubject
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] in
                guard let self = self, !self.isResetting else { return }
                self.saveVisualSettings()
                if self.hasCompletedInitialLoad {
                    self.saveAISettingsToDefaults()
                }
                self.saveShortcuts()
                self.saveLibrary()
                // notifySaveSuccess() // 移除自动保存的弹窗提示，改为静默保存
            }
            .store(in: &cancellables)

        // ✨ Listen for external settings changes (e.g. from other windows or defaults command)
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main) // Reduce noise
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self = self, !self.isResetting, !self.isInternalSaving, !self.isInternalLoading else { return }
                self.loadVisualSettings()
            }
            .store(in: &cancellables)

        // Debounce search (300ms)
        searchSubject
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .assign(to: \.debouncedSearchQuery, on: self)
            .store(in: &cancellables)

        // Throttle Attributed Text Update (100ms) - 确保流式输出时至少每 100ms 渲染一次
        // 注意：这里必须使用 throttle 而非 debounce，因为 debounce 会在高速输入时不断重置计时器导致不渲染
        textUpdateSubject
            .throttle(for: .milliseconds(100), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] in
                guard let self = self else { return }
                if self.suppressNextTextUpdate {
                    self.suppressNextTextUpdate = false
                    return
                }
                self.updateAttributedText()
                // 编辑模式下不触发自动保存，退出编辑时统一保存
                if !self.isInternalLoading && !self.isEditing {
                    self.saveSubject.send()
                }
            }
            .store(in: &cancellables)

        updateAttributedText()
    }

    deinit {
        ghostPrepTimer?.invalidate()
        ghostRunTimer?.invalidate()
        speechTimer?.invalidate()
    }

    private func renderLines(
        _ lines: [String],
        range: Range<Int>,
        isInsideThinkBlock: inout Bool,
        isInsideCodeBlock: inout Bool
    ) -> AttributedString {
        let baseSize = fontSize
        var combined = AttributedString()
        var currentTotalLength = 0
        var lineRanges: [LineRangeInfo] = []

        for index in range {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // 检测并隐藏思考块标记
            if trimmed == "<think>" {
                isInsideThinkBlock = true
                continue
            }
            if trimmed == "</think>" {
                isInsideThinkBlock = false
                continue
            }

            // 检测并隐藏 Markdown 代码块标记
            if trimmed.hasPrefix("```") {
                isInsideCodeBlock.toggle()
                continue
            }

            if trimmed.isEmpty {
                combined.append(AttributedString("\n"))
                currentTotalLength += 1
                continue
            }

            // 🚀 行级缓存：只缓存原始 Markdown 解析后的 AttributedString，与具体的视觉样式（字体大小、颜色等）解耦
            if lineCache[line] == nil {
                lineCache[line] = Self.parseLineMarkdown(line)
            }

            var lineAttr = lineCache[line]!
            let styleType: StyleType

            if isInsideThinkBlock {
                styleType = .think
                if isPrivacyMode {
                    lineAttr = AttributedString("")
                } else {
                    // 🧠 思考块样式：斜体、小字 (75%)、灰色
                    let thinkSize = baseSize * 0.75
                    let thinkColor = Color.gray.opacity(0.65)
                    lineAttr.swiftUI.font = Font.system(size: thinkSize, weight: Font.Weight.regular, design: Font.Design.default).italic()
                    lineAttr.swiftUI.foregroundColor = thinkColor
                }
            } else if isInsideCodeBlock || isCodeMode {
                styleType = .code
                // 💻 代码块样式：等宽字体、小字 (90%)
                let codeSize = baseSize * 0.9
                for run in lineAttr.runs {
                    if let inline = run.inlinePresentationIntent, inline.contains(InlinePresentationIntent.stronglyEmphasized) {
                        lineAttr[run.range].swiftUI.foregroundColor = presentationStyle.accentColor
                    }
                    lineAttr[run.range].swiftUI.font = Font.system(size: codeSize, weight: Font.Weight.regular, design: Font.Design.monospaced)
                    if lineAttr[run.range].swiftUI.foregroundColor == nil {
                        lineAttr[run.range].swiftUI.foregroundColor = presentationStyle.codeTextColor
                    }
                }
            } else {
                styleType = .normal
                // 📝 正文样式：大字、粗体
                for run in lineAttr.runs {
                    var runSize: CGFloat = baseSize
                    var weight: Font.Weight = .semibold

                    if let intent = run.presentationIntent {
                        for component in intent.components {
                            if case .header(let level) = component.kind {
                                runSize = baseSize * (level == 1 ? 1.5 : (level == 2 ? 1.3 : 1.15))
                                weight = .bold
                            }
                        }
                    }

                    if let inline = run.inlinePresentationIntent, inline.contains(InlinePresentationIntent.stronglyEmphasized) {
                        weight = .heavy
                        lineAttr[run.range].swiftUI.foregroundColor = presentationStyle.accentColor
                    }

                    lineAttr[run.range].swiftUI.font = Font.system(size: runSize, weight: weight, design: Font.Design.default)
                    if lineAttr[run.range].swiftUI.foregroundColor == nil {
                        lineAttr[run.range].swiftUI.foregroundColor = presentationStyle.primaryTextColor
                    }
                }
            }

            let lineLength = NSAttributedString(lineAttr).length
            let startLoc = currentTotalLength
            currentTotalLength += lineLength
            combined.append(lineAttr)

            if lineLength > 0 {
                let nsRange = NSRange(location: startLoc, length: lineLength)
                lineRanges.append(LineRangeInfo(range: nsRange, styleType: styleType))
            }

            if index < lines.count - 1 {
                combined.append(AttributedString("\n"))
                currentTotalLength += 1
            }
        }

        // 批量将拼装好的字符转换为 NSMutableAttributedString 渲染段落样式，
        // 彻底免去在循环体内 5000+ 次重复转换 of O(N) 桥接性能开销
        let nsAttr = NSMutableAttributedString(combined)
        for info in lineRanges {
            let paragraphStyle = NSMutableParagraphStyle()
            switch info.styleType {
            case .think:
                paragraphStyle.lineSpacing = lineSpacing * 0.3
                paragraphStyle.alignment = .center
            case .code:
                paragraphStyle.lineSpacing = lineSpacing * 0.8
                paragraphStyle.alignment = .left
                paragraphStyle.firstLineHeadIndent = 20
                paragraphStyle.headIndent = 20
            case .normal:
                paragraphStyle.lineSpacing = lineSpacing
                paragraphStyle.alignment = .center
            }
            nsAttr.addAttribute(.paragraphStyle, value: paragraphStyle, range: info.range)
        }

        return AttributedString(nsAttr)
    }

    private func updateAttributedText() {
        // 编辑模式下跳过：EditorOverlay 覆盖了提词器，格式化文本不可见
        guard !isEditing else { return }

        // 缓存容量保护
        if lineCache.count > Self.maxLineCacheEntries {
            lineCache.removeAll(keepingCapacity: true)
        }

        // 取消前一个正在运行的后台渲染任务
        renderingTask?.cancel()
        renderingTask = nil

        let lines = text.components(separatedBy: .newlines)
        
        var isInsideThinkBlock = false
        var isInsideCodeBlock = false
        
        let initialChunkSize = 200
        
        if lines.count <= initialChunkSize {
            // 小文件：直接同步完整渲染
            self.attributedText = renderLines(lines, range: 0..<lines.count, isInsideThinkBlock: &isInsideThinkBlock, isInsideCodeBlock: &isInsideCodeBlock)
        } else {
            // 大文件：
            // 1. 同步渲染前 200 行以最快速度显示，避免首屏切换卡死
            self.attributedText = renderLines(lines, range: 0..<initialChunkSize, isInsideThinkBlock: &isInsideThinkBlock, isInsideCodeBlock: &isInsideCodeBlock)
            
            // 获取当前已缓存的 key 集合（值类型，Safe for Sendable）
            let cachedKeys = Set(self.lineCache.keys)
            
            // 捕获同步渲染后的块状态作为初始状态
            let initialThink = isInsideThinkBlock
            let initialCode = isInsideCodeBlock
            
            // 2. 启动后台异步任务进行 Markdown 解析与渐进式渲染
            renderingTask = Task {
                var taskThink = initialThink
                var taskCode = initialCode
                
                var currentIndex = initialChunkSize
                let chunkSize = 500
                
                while currentIndex < lines.count {
                    if Task.isCancelled { break }
                    
                    let endLimit = min(currentIndex + chunkSize, lines.count)
                    let chunkRange = currentIndex..<endLimit
                    
                    // 在后台线程（非 MainActor）中解析 Markdown，彻底解放主线程
                    var parsedChunk: [String: AttributedString] = [:]
                    for idx in chunkRange {
                        let line = lines[idx]
                        let trimmed = line.trimmingCharacters(in: .whitespaces)
                        if trimmed.isEmpty || line.hasPrefix("```") || trimmed == "<think>" || trimmed == "</think>" {
                            continue
                        }
                        if !cachedKeys.contains(line) {
                            parsedChunk[line] = Self.parseLineMarkdown(line)
                        }
                    }
                    
                    if Task.isCancelled { break }
                    
                    // 回到 MainActor 合并已解析缓存并执行视觉渲染
                    let (updatedThink, updatedCode) = await MainActor.run { [weak self] () -> (Bool, Bool) in
                        guard let self = self else { return (taskThink, taskCode) }
                        
                        for (line, attr) in parsedChunk {
                            self.lineCache[line] = attr
                        }
                        
                        var think = taskThink
                        var code = taskCode
                        
                        // 此时 renderLines 100% 命中缓存，运行时间 < 1ms
                        let chunkAttr = self.renderLines(
                            lines,
                            range: chunkRange,
                            isInsideThinkBlock: &think,
                            isInsideCodeBlock: &code
                        )
                        
                        if !Task.isCancelled {
                            self.attributedText.append(chunkAttr)
                        }
                        
                        return (think, code)
                    }
                    
                    taskThink = updatedThink
                    taskCode = updatedCode
                    currentIndex = endLimit
                    
                    // 挂起并休眠 15ms，交出 CPU 时间片，确保 RunLoop 极其流畅地响应用户滚动与交互
                    try? await Task.sleep(nanoseconds: 15_000_000)
                }
                
                await MainActor.run { [weak self] in
                    guard let self = self else { return }
                    if !Task.isCancelled {
                        self.renderingTask = nil
                    }
                }
            }
        }
    }

    func notifySaveSuccess() {
        showSaveStatus = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.showSaveStatus = false
        }
    }

    // MARK: - Shortcut Management

    func loadShortcuts() {
        // 先加载默认值，确保新增的快捷键（如编辑、AI等）能自动出现
        resetShortcutsToDefault()

        // 如果用户有保存过的配置，则进行覆盖合并
        if let data = UserDefaults.standard.data(forKey: shortcutsKey),
           let decoded = try? JSONDecoder().decode([ShortcutAction: Shortcut].self, from: data) {
            for (action, shortcut) in decoded {
                self.shortcuts[action] = shortcut
            }
        }
    }

    func saveShortcuts() {
        if let encoded = try? JSONEncoder().encode(shortcuts) {
            UserDefaults.standard.set(encoded, forKey: shortcutsKey)
        }
    }

    func resetShortcutsToDefault() {
        self.shortcuts = [
            .playPause: Shortcut(key: " ", keyCode: 49, modifiers: 0),
            .reset: Shortcut(key: "r", keyCode: 15, modifiers: 0),
            .toggleLibrary: Shortcut(key: "l", keyCode: 37, modifiers: 0),
            .prevScript: Shortcut(key: "[", keyCode: 33, modifiers: NSEvent.ModifierFlags.option.rawValue),
            .nextScript: Shortcut(key: "]", keyCode: 30, modifiers: NSEvent.ModifierFlags.option.rawValue),
            .aiPrompt: Shortcut(key: "a", keyCode: 0, modifiers: 0),
            .toggleControls: Shortcut(key: "h", keyCode: 4, modifiers: 0),
            .toggleAlwaysOnTop: Shortcut(key: "t", keyCode: 17, modifiers: 0),
            .paste: Shortcut(key: "v", keyCode: 9, modifiers: 0),
            .toggleEdit: Shortcut(key: "e", keyCode: 14, modifiers: 0),
            .prevWorkspace: Shortcut(key: "[", keyCode: 33, modifiers: NSEvent.ModifierFlags([.option, .command]).rawValue),
            .nextWorkspace: Shortcut(key: "]", keyCode: 30, modifiers: NSEvent.ModifierFlags([.option, .command]).rawValue),
            .increaseFontSize: Shortcut(key: "=", keyCode: 24, modifiers: 0),
            .decreaseFontSize: Shortcut(key: "-", keyCode: 27, modifiers: 0),
            .increaseBgOpacity: Shortcut(key: "]", keyCode: 30, modifiers: 0),
            .decreaseBgOpacity: Shortcut(key: "[", keyCode: 33, modifiers: 0),
            .increaseTextOpacity: Shortcut(key: ".", keyCode: 47, modifiers: 0),
            .decreaseTextOpacity: Shortcut(key: ",", keyCode: 43, modifiers: 0),
            .toggleTimer: Shortcut(key: "k", keyCode: 40, modifiers: 0),
            .resetTimer: Shortcut(key: "K", keyCode: 40, modifiers: NSEvent.ModifierFlags.shift.rawValue),
            .togglePrivacy: Shortcut(key: "s", keyCode: 1, modifiers: 0),
            .toggleMirrorH: Shortcut(key: "m", keyCode: 46, modifiers: 0),
            .toggleMirrorV: Shortcut(key: "f", keyCode: 3, modifiers: 0)
        ]
        saveShortcuts()
    }

    // MARK: - AI Settings Persistence

    func loadAISettings() async {
        isInternalLoading = true
        defer { isInternalLoading = false }

        // 1. Perform migration from "OpenAI 兼容" to "OpenAI 兼容 1"
        if let providerRaw = UserDefaults.standard.string(forKey: "Pref_aiProvider"),
           providerRaw == "OpenAI 兼容" {
            UserDefaults.standard.set("OpenAI 兼容 1", forKey: "Pref_aiProvider")
        }

        func migrateUserDefaultsDict(key: String) {
            if var dict = UserDefaults.standard.dictionary(forKey: key) {
                if let val = dict["OpenAI 兼容"] {
                    dict["OpenAI 兼容 1"] = val
                    dict.removeValue(forKey: "OpenAI 兼容")
                    UserDefaults.standard.set(dict, forKey: key)
                }
            }
        }
        migrateUserDefaultsDict(key: "Pref_providerURLs")
        migrateUserDefaultsDict(key: "Pref_providerModels")
        migrateUserDefaultsDict(key: "Pref_providerSelectedModels")
        migrateUserDefaultsDict(key: "Pref_providerKeys")

        // Migrate "Pref_providerPriority"
        if var priorityData = UserDefaults.standard.array(forKey: "Pref_providerPriority") as? [String] {
            if let idx = priorityData.firstIndex(of: "OpenAI 兼容") {
                priorityData[idx] = "OpenAI 兼容 1"
                if !priorityData.contains("OpenAI 兼容 2") {
                    priorityData.insert("OpenAI 兼容 2", at: idx + 1)
                }
                UserDefaults.standard.set(priorityData, forKey: "Pref_providerPriority")
            }
        }

        // Migrate Keychain API key if exists
        do {
            if let oldKey = try? await KeychainHelper.shared.read(for: "APIKey_OpenAI 兼容") {
                try? await KeychainHelper.shared.save(oldKey, for: "APIKey_OpenAI 兼容 1")
                KeychainHelper.shared.delete(for: "APIKey_OpenAI 兼容")
            }
        }

        // Load main provider
        if let providerRaw = UserDefaults.standard.string(forKey: "Pref_aiProvider"),
           let provider = AIProvider(rawValue: providerRaw) {
            self.aiProvider = provider
        }

        // Load per-provider dictionaries
        if var keys = UserDefaults.standard.dictionary(forKey: "Pref_providerKeys") as? [String: String] {
            var keysModified = false
            for (k, v) in keys {
                if let p = AIProvider(rawValue: k) {
                    do {
                        try await KeychainHelper.shared.save(v, for: "APIKey_\(k)")
                        providerKeys[p] = v
                        keys.removeValue(forKey: k)
                        keysModified = true
                        print("✅ Keychain migration successful for \(k)")
                    } catch {
                        print("⚠️ Keychain migration failed for \(k): \(error)")
                        // If failed, keep in keys dictionary so we can retry next time
                    }
                }
            }

            if keysModified {
                if keys.isEmpty {
                    UserDefaults.standard.removeObject(forKey: "Pref_providerKeys")
                } else {
                    UserDefaults.standard.set(keys, forKey: "Pref_providerKeys")
                }
            }
        } else {
            // Optimization: Only load the current active provider's key on startup.
            // This reduces the number of Keychain prompts to at most one.
            do {
                let saved = try await KeychainHelper.shared.read(for: "APIKey_\(aiProvider.rawValue)")
                providerKeys[aiProvider] = saved
            } catch KeychainHelper.KeychainError.notFound {
                // Normal initial state, ignore
            } catch {
                print("⚠️ Initial Keychain read failed: \(error)")
                self.apiTestStatus = "读取保存的 API Key 失败: \(error.localizedDescription)"
            }
        }

        if let urls = UserDefaults.standard.dictionary(forKey: "Pref_providerURLs") as? [String: String] {
            urls.forEach { if let p = AIProvider(rawValue: $0) { providerURLs[p] = $1 } }
        }
        if let models = UserDefaults.standard.dictionary(forKey: "Pref_providerModels") as? [String: [String]] {
            models.forEach { if let p = AIProvider(rawValue: $0) { providerModels[p] = $1 } }
        }
        if let selectedModels = UserDefaults.standard.dictionary(forKey: "Pref_providerSelectedModels") as? [String: String] {
            selectedModels.forEach { if let p = AIProvider(rawValue: $0) { providerSelectedModels[p] = $1 } }
        }

        // Sync current active fields
        self.aiAPIKey = providerKeys[aiProvider] ?? (((aiProvider == .mstyOllama || aiProvider == .mstyMLX) ? "not-needed" : ""))
        // No need to call loadActiveProviderKey here as it will be called by aiProvider's didSet
        // if memory cache is empty, OR it was already loaded in line 687.

        self.aiBaseURL = providerURLs[aiProvider] ?? aiProvider.defaultBaseURL
        self.availableModels = providerModels[aiProvider] ?? []
        self.aiModel = providerSelectedModels[aiProvider] ?? ""

        // Other settings
        if let rolesData = UserDefaults.standard.data(forKey: "Pref_aiRoles"),
           let decodedRoles = try? JSONDecoder().decode([AIRole].self, from: rolesData) {
            self.aiRoles = decodedRoles
        }

        let savedRoleIndex = UserDefaults.standard.integer(forKey: "Pref_selectedRoleIndex")
        self.selectedRoleIndex = min(max(0, savedRoleIndex), max(0, aiRoles.count - 1))

        if let autoFollow = UserDefaults.standard.object(forKey: "Pref_autoFollow") as? Bool {
            self.autoFollowEnabled = autoFollow
        }
        if let useContext = UserDefaults.standard.object(forKey: "Pref_useWorkspaceContextForAI") as? Bool {
            self.useWorkspaceContextForAI = useContext
        }
        if let useAnyContext = UserDefaults.standard.object(forKey: "Pref_useAnyContextForAI") as? Bool {
            self.useAnyContextForAI = useAnyContext
        }
        if let enableFailover = UserDefaults.standard.object(forKey: "Pref_enableFailover") as? Bool {
            self.enableFailover = enableFailover
        }
        if let priorityData = UserDefaults.standard.array(forKey: "Pref_providerPriority") as? [String] {
            let loadedPriority = priorityData.compactMap { AIProvider(rawValue: $0) }
            if !loadedPriority.isEmpty {
                self.providerPriority = loadedPriority
            }
        }
        if let personalStyle = UserDefaults.standard.string(forKey: "Pref_aiPersonalStyle") {
            self.aiPersonalStyle = personalStyle
        }
        if let codeMode = UserDefaults.standard.object(forKey: "Pref_isCodeMode") as? Bool {
            self.isCodeMode = codeMode
        }
        if let deepSeekThinking = UserDefaults.standard.object(forKey: "Pref_enableDeepSeekThinking") as? Bool {
            self.enableDeepSeekThinking = deepSeekThinking
        }
        lineCache.removeAll(keepingCapacity: true)
        updateAttributedText()
    }

    /// Loads the API key for the currently selected provider from Keychain.
    func loadActiveProviderKey() async {
        let current = aiProvider

        // 🛡️ [1] 优先检查内存缓存：如果内存中已有值，则跳过 Keychain 读取
        // 这能极大地减少触发 macOS 授权弹窗的频率（仅需在应用启动或首次配置时验证一次）
        if let cachedValue = providerKeys[current], !cachedValue.isEmpty {
            self.aiAPIKey = cachedValue
            return
        }

        guard current != .mstyOllama && current != .mstyMLX else { return }

        // 🛡️ [2] 仅在内存为空时读取 Keychain
        do {
            let saved = try await KeychainHelper.shared.read(for: "APIKey_\(current.rawValue)")
            // 双重检查 provider 没变，防止异步加载过程中的竞态
            if self.aiProvider == current {
                self.aiAPIKey = saved
                self.providerKeys[current] = saved
            }
        } catch KeychainHelper.KeychainError.notFound {
            if self.aiProvider == current {
                self.aiAPIKey = ""
            }
        } catch {
            print("⚠️ Keychain read error for \(current.rawValue): \(error)")
            if self.aiProvider == current {
                self.apiTestStatus = "读取保存的 API Key 失败: \(error.localizedDescription)"
            }
        }
    }

    /// Lightweight save: only persists AI config to UserDefaults.
    /// Called automatically by the debounced saveSubject pipeline.
    /// Does NOT touch Keychain — avoids triggering macOS authorization dialogs.
    func saveAISettingsToDefaults() {
        guard !isResetting else { return }
        isInternalSaving = true
        defer { isInternalSaving = false }

        UserDefaults.standard.set(aiProvider.rawValue, forKey: "Pref_aiProvider")

        // Sync current active state into dictionaries
        providerKeys[aiProvider] = aiAPIKey
        providerURLs[aiProvider] = aiBaseURL
        providerModels[aiProvider] = availableModels
        providerSelectedModels[aiProvider] = aiModel

        let urlsStrings = providerURLs.reduce(into: [String: String]()) { $0[$1.key.rawValue] = $1.value }
        UserDefaults.standard.set(urlsStrings, forKey: "Pref_providerURLs")

        let modelsStrings = providerModels.reduce(into: [String: [String]]()) { $0[$1.key.rawValue] = $1.value }
        UserDefaults.standard.set(modelsStrings, forKey: "Pref_providerModels")

        let selectedModelsStrings = providerSelectedModels.reduce(into: [String: String]()) { $0[$1.key.rawValue] = $1.value }
        UserDefaults.standard.set(selectedModelsStrings, forKey: "Pref_providerSelectedModels")

        if let encodedRoles = try? JSONEncoder().encode(aiRoles) {
            UserDefaults.standard.set(encodedRoles, forKey: "Pref_aiRoles")
        }
        UserDefaults.standard.set(selectedRoleIndex, forKey: "Pref_selectedRoleIndex")
        UserDefaults.standard.set(autoFollowEnabled, forKey: "Pref_autoFollow")
        UserDefaults.standard.set(useWorkspaceContextForAI, forKey: "Pref_useWorkspaceContextForAI")
        UserDefaults.standard.set(useAnyContextForAI, forKey: "Pref_useAnyContextForAI")
        UserDefaults.standard.set(enableFailover, forKey: "Pref_enableFailover")
        UserDefaults.standard.set(providerPriority.map { $0.rawValue }, forKey: "Pref_providerPriority")
        UserDefaults.standard.set(aiPersonalStyle, forKey: "Pref_aiPersonalStyle")
        UserDefaults.standard.set(isCodeMode, forKey: "Pref_isCodeMode")
        UserDefaults.standard.set(enableDeepSeekThinking, forKey: "Pref_enableDeepSeekThinking")
    }

    // MARK: - AI Provider UI Helpers

    func getProviderStatus(_ provider: AIProvider) -> ProviderStatus {
        if let status = providerStatuses[provider] {
            return status
        }

        if provider.isLocal {
            return .localReady
        }

        let key = getAPIKey(for: provider)
        return key.isEmpty ? .notConfigured : .waitingForTest
    }

    var activeStatusText: String {
        if isTestingAPI { return "正在验证连接..." }
        if let status = apiTestStatus { return status }
        return getProviderStatus(aiProvider).displayText
    }

    var activeStatusColor: Color {
        getProviderStatus(aiProvider).color
    }

    // MARK: - Per-Provider Accessors

    func getBaseURL(for provider: AIProvider) -> String {
        if provider == aiProvider { return aiBaseURL }
        return providerURLs[provider] ?? provider.defaultBaseURL
    }

    func setBaseURL(_ url: String, for provider: AIProvider) {
        if provider == aiProvider { aiBaseURL = url }
        else { providerURLs[provider] = url; saveSubject.send() }
    }

    func getAPIKey(for provider: AIProvider) -> String {
        if provider == aiProvider { return aiAPIKey }
        return providerKeys[provider] ?? ""
    }

    func setAPIKey(_ key: String, for provider: AIProvider) {
        if provider == aiProvider { aiAPIKey = key }
        else {
            providerKeys[provider] = key
            saveSubject.send()
        }
    }

    func getModel(for provider: AIProvider) -> String {
        if provider == aiProvider { return aiModel }
        return providerSelectedModels[provider] ?? ""
    }

    func setModel(_ model: String, for provider: AIProvider) {
        if provider == aiProvider { aiModel = model }
        else { providerSelectedModels[provider] = model; saveSubject.send() }
    }

    func getAvailableModels(for provider: AIProvider) -> [String] {
        if provider == aiProvider { return availableModels }
        return providerModels[provider] ?? []
    }


    /// Full save: persists AI config to UserDefaults AND API keys to Keychain.
    /// Only called on explicit user action (e.g. clicking "保存" or closing settings).
    func saveAISettings() async {
        // 1. 先保存基础配置到 UserDefaults
        saveAISettingsToDefaults()

        // 2. 仅持久化当前活跃平台的 Key 到 Keychain (如果该 Key 存在且非空)
        // 这样可以避免每次保存都触发所有平台的 Keychain 授权弹窗
        if let keyToSave = providerKeys[aiProvider], !keyToSave.isEmpty {
            do {
                try await KeychainHelper.shared.save(keyToSave, for: "APIKey_\(aiProvider.rawValue)")
            } catch {
                print("❌ Failed to save \(aiProvider.rawValue) key to Keychain: \(error)")
            }
        }
    }

    func showConfigFileInFinder() {
        // macOS preferences are in ~/Library/Preferences
        let path = NSString(string: "~/Library/Preferences").expandingTildeInPath
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.open(url)
    }

    func resetAllSettings() {
        let alert = NSAlert()
        alert.messageText = "确定要重置所有设置吗？"
        alert.informativeText = "这将会清除所有已导入的剧本、AI 配置、API Key 以及快捷键设置。此操作无法撤销。"
        alert.alertStyle = .critical
        alert.addButton(withTitle: "重置")
        alert.addButton(withTitle: "取消")

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        isResetting = true

        // 1. Clear disk state - use a more robust approach
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }

        // Additionally remove all keys explicitly as removePersistentDomain can be inconsistent in dev environments
        let keys = UserDefaults.standard.dictionaryRepresentation().keys
        for key in keys {
            // Only remove keys that belong to our app (Pref_, Visual_, User...)
            if key.hasPrefix("Pref_") || key.hasPrefix("Visual_") || key.hasPrefix("User") {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        // Note: synchronize() is a no-op on modern macOS (10.14+) — system auto-syncs.

        // 2. Clear in-memory AI dictionaries immediately
        providerKeys.removeAll()
        providerURLs.removeAll()
        providerModels.removeAll()
        providerSelectedModels.removeAll()

        // 2.1 Clear Keychain items
        AIProvider.allCases.forEach { p in
            KeychainHelper.shared.delete(for: "APIKey_\(p.rawValue)")
        }

        // 3. Reset properties to defaults
        aiProvider = .deepseek
        aiAPIKey = ""
        aiBaseURL = aiProvider.defaultBaseURL
        aiModel = ""
        availableModels = []
        isCodeMode = false
        enableDeepSeekThinking = false
        providerPriority = [.deepseek, .openAICompatible1, .openAICompatible2, .anthropic, .ollama, .mstyOllama, .mstyMLX]
        lineCache.removeAll()
        aiRoles = [
            AIRole(name: "LeetCode 刷题助手", prompt: #"""
你是一个顶尖的 LeetCode 刷题专家与算法教练。

## 核心任务
帮助用户解答 LeetCode 算法题，特别擅长识别中英文混合、拼音、数字、代码缩写等高噪输入。你的输出必须极度精简，拒绝任何多余的套话与啰唆解释。

## 交互流程（关键）
1. **理解与确认评估**：
   - 仔细评估用户的输入。如果题目描述或补充说明中存在明显歧义、信息缺失（如不知道数据范围、边界限制、输入输出格式），或可能影响算法选择（如 O(N) vs O(NlogN)），你必须立即停止输出解答，用极简的语言向用户提问以澄清不确定点。
   - 如果信息完整、无歧义，则直接进入解答阶段。

2. **解答输出结构（仅在确认理解无误时提供，拒绝废话）**：
   - **【核心思路】**：仅用 1-2 句话陈述你对题意的理解及选择该算法的核心理由（例如：“此题为经典的双指针问题，通过维护左右窗口边界可以在 O(N) 时间内求得最长子串”）。
   - **【Python 代码】**：提供 LeetCode 可直接提交的高质量 Python3 代码。代码中应包含关键位置的超精炼单行注释。
   - **【边界与极值分析】**：列出 2-3 个容易被忽视的边界测试点（如空输入、单元素、极大值、负数等）以及针对性处理。
   - **【极简执行步骤】**：按代码执行顺序（初始化 -> 循环/更新逻辑 -> 返回值），使用极度精炼的步骤说明其运作机制。

## 规则限制
- 默认且仅使用 Python3。
- 选择兼顾“最优复杂度”与“面试高容错/易写性”的解法，不写过度炫技或难以复现的代码。
- 拒绝任何如“好的，我明白了”、“接下来为你分析”等无意义的前缀/后缀客套话。
"""#),
            AIRole(name: "默认助手", prompt: "你是一个专业的提词器助手，请根据我的要求生成播报内容。"),
            AIRole(name: "模拟面试官", prompt: "你是一个专业的互联网公司面试官，请针对我的简历或项目进行追问。")
        ]
        selectedRoleIndex = 0
        aiPersonalStyle = ""

        // 4. Re-initialize other states from (now empty) UserDefaults or defaults
        loadVisualSettings()
        loadShortcuts()
        loadLibrary()

        // 5. Reset dynamic runtime state
        reset()
        showSettings = false // Close settings panel after reset

        isResetting = false
    }

    // MARK: - Library Persistence

    func loadLibrary() {
        var loadedWorkspaces: [Workspace] = []
        var didMigrate = false

        // 尝试加载新版 Workspace 数据
        if let data = UserDefaults.standard.data(forKey: workspacesKey),
           let decoded = try? JSONDecoder().decode([Workspace].self, from: data) {
            loadedWorkspaces = decoded
        }
        // 兼容旧版平铺数据
        else if let oldData = UserDefaults.standard.data(forKey: oldLibraryKey),
                let decodedOld = try? JSONDecoder().decode([Script].self, from: oldData) {
            loadedWorkspaces = [Workspace(name: "收集箱", scripts: decodedOld)]
            didMigrate = true
        }

        if loadedWorkspaces.isEmpty {
            loadedWorkspaces = [Workspace(name: "收集箱", scripts: [])]
        }

        // 智能修复/迁移：如果只有一个“收集箱”，尝试根据原始文件的父文件夹名称自动进行分组整理
        if loadedWorkspaces.count == 1 && loadedWorkspaces[0].name == "收集箱" {
            let defaultScripts = loadedWorkspaces[0].scripts
            var grouped: [String: [Script]] = [:]
            var ungrouped: [Script] = []

            for script in defaultScripts {
                if let url = script.url, !script.isAIGenerated {
                    let folderName = url.deletingLastPathComponent().lastPathComponent
                    // 排除一些系统常见根目录，避免过度分组
                    if ["Downloads", "Desktop", "Documents", ""].contains(folderName) || folderName == "/" {
                        ungrouped.append(script)
                    } else {
                        grouped[folderName, default: []].append(script)
                    }
                } else {
                    ungrouped.append(script)
                }
            }

            // 如果确实发现了包含在特定文件夹里的文件，执行拆分
            if !grouped.isEmpty {
                var smartWorkspaces: [Workspace] = []
                if !ungrouped.isEmpty {
                    smartWorkspaces.append(Workspace(name: "收集箱", scripts: ungrouped))
                }
                for (folderName, scripts) in grouped {
                    smartWorkspaces.append(Workspace(name: folderName, scripts: scripts))
                }
                // 按名称排个序，把收集箱放最前
                smartWorkspaces.sort { $0.name == "收集箱" ? true : ($1.name == "收集箱" ? false : $0.name < $1.name) }
                loadedWorkspaces = smartWorkspaces
                didMigrate = true
            }
        }

        self.workspaces = loadedWorkspaces

        // ✨ Bookmark 迁移：为旧数据中缺少 bookmark 的条目自动生成
        var bookmarkMigrated = false
        for wIndex in 0..<workspaces.count {
            // 迁移 Workspace 的 folderBookmark
            if workspaces[wIndex].folderBookmark == nil, let folderURL = workspaces[wIndex].folderURL {
                workspaces[wIndex].folderBookmark = try? folderURL.bookmarkData(
                    options: .minimalBookmark,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                if workspaces[wIndex].folderBookmark != nil { bookmarkMigrated = true }
            }
            // 迁移 Script 的 bookmarkData
            for sIndex in 0..<workspaces[wIndex].scripts.count {
                if workspaces[wIndex].scripts[sIndex].bookmarkData == nil,
                   let scriptURL = workspaces[wIndex].scripts[sIndex].url,
                   !workspaces[wIndex].scripts[sIndex].isAIGenerated {
                    workspaces[wIndex].scripts[sIndex].bookmarkData = try? scriptURL.bookmarkData(
                        options: .minimalBookmark,
                        includingResourceValuesForKeys: nil,
                        relativeTo: nil
                    )
                    if workspaces[wIndex].scripts[sIndex].bookmarkData != nil { bookmarkMigrated = true }
                }
            }
        }

        // Validate indices
        if activeWorkspaceIndex >= workspaces.count { activeWorkspaceIndex = 0 }

        if !workspaces[activeWorkspaceIndex].scripts.isEmpty {
            switchToScript(at: 0, in: activeWorkspaceIndex)
        }

        // 如果发生了迁移或者智能重组，自动保存一次新结构
        if didMigrate || bookmarkMigrated {
            saveLibrary()
        }

        // 启动后台异步加载管线，预先缓存本地磁盘上的脚本内容，避免同步读取卡顿
        lazyLoadAllScriptsContent()
    }

    private func lazyLoadAllScriptsContent() {
        Task.detached(priority: .utility) { [weak self] in
            guard let self = self else { return }
            let currentWorkspaces = await MainActor.run { self.workspaces }

            for wIndex in 0..<currentWorkspaces.count {
                for sIndex in 0..<currentWorkspaces[wIndex].scripts.count {
                    var script = currentWorkspaces[wIndex].scripts[sIndex]
                    if script.content.isEmpty, let targetURL = script.resolveURL() {
                        let targetScriptID = script.id
                        let scriptTitle = script.title
                        do {
                            let access = targetURL.startAccessingSecurityScopedResource()
                            defer { if access { targetURL.stopAccessingSecurityScopedResource() } }
                            let loadedContent = try String(contentsOf: targetURL, encoding: .utf8)

                            await MainActor.run {
                                // 校验确保在加载期间内存中的内容未被用户修改或替换过
                                if wIndex < self.workspaces.count &&
                                   sIndex < self.workspaces[wIndex].scripts.count &&
                                   self.workspaces[wIndex].scripts[sIndex].id == targetScriptID &&
                                   self.workspaces[wIndex].scripts[sIndex].content.isEmpty {
                                    self.workspaces[wIndex].scripts[sIndex].content = loadedContent

                                    // 如果该剧本刚好当前激活，同步更新 text 及渲染视图
                                    if wIndex == self.activeWorkspaceIndex && sIndex == self.activeScriptIndex {
                                        self.suppressNextTextUpdate = true
                                        self.text = loadedContent
                                        self.updateAttributedText()
                                    }
                                }
                            }
                        } catch {
                            print("⚠️ 后台加载剧本失败 [\(scriptTitle)]: \(error.localizedDescription)")
                        }
                    }
                }
            }
        }
    }

    func saveLibrary() {
        // Sync current text and scroll offset before saving
        saveCurrentTextToLibrary()

        if activeWorkspaceIndex >= 0 && activeWorkspaceIndex < workspaces.count {
            if activeScriptIndex >= 0 && activeScriptIndex < workspaces[activeWorkspaceIndex].scripts.count {
                workspaces[activeWorkspaceIndex].scripts[activeScriptIndex].lastScrollOffset = scrollOffset
            }
        }

        // 仅对未关联本地磁盘文件（url 为 nil）的剧本在 UserDefaults 中持久化正文，
        // 关联了本地磁盘文件的剧本只持久化其元数据，正文内容动态加载。
        var workspacesToSave = workspaces
        for wIndex in 0..<workspacesToSave.count {
            for sIndex in 0..<workspacesToSave[wIndex].scripts.count {
                if workspacesToSave[wIndex].scripts[sIndex].url != nil {
                    workspacesToSave[wIndex].scripts[sIndex].content = ""
                }
            }
        }

        if let encoded = try? JSONEncoder().encode(workspacesToSave) {
            UserDefaults.standard.set(encoded, forKey: workspacesKey)
        }
    }

    func saveCurrentTextToLibrary() {
        guard activeWorkspaceIndex >= 0 && activeWorkspaceIndex < workspaces.count else { return }

        if activeScriptIndex >= 0 && activeScriptIndex < workspaces[activeWorkspaceIndex].scripts.count {
            workspaces[activeWorkspaceIndex].scripts[activeScriptIndex].content = text
            workspaces[activeWorkspaceIndex].scripts[activeScriptIndex].lastScrollOffset = scrollOffset
        } else if text != SparklePromptViewModel.defaultText && !text.isEmpty {
            // 如果是在默认文本上编辑并保存，自动创建一个新剧本
            var newScript = Script(title: "未命名剧本", content: text)
            newScript.lastScrollOffset = scrollOffset
            workspaces[activeWorkspaceIndex].scripts.append(newScript)
            activeScriptIndex = workspaces[activeWorkspaceIndex].scripts.count - 1
        }
    }

    // MARK: - Default text
    static let defaultText = """
    SparklePrompt — 快捷键指南

    SPACE           播放 / 暂停滚动
    R               重置滚动与计时器 (Reset)
    ↑ / ↓           加速 / 减速 (滚动速度)
    = / -           放大 / 缩小字号
    M               水平镜像 (Mirrored)
    F               垂直翻转 (Flip)
    H               显示 / 隐藏底部控制栏
    E               编辑当前脚本 (Edit)
    V               从剪贴板粘贴并自动归档 (Paste)
    T               切换 窗口置顶 (Always on Top)
    S               开启隐私防护；已开启时需连续按两次退出

    K               开始 / 暂停计时器 (Timer)
    ⇧ + K           重置计时器
    [ / ]           减小 / 增大背景暗度 (Background Dimming)
    , / .           减小 / 增大文字透明度 (Text Opacity)

    L               打开 / 关闭侧边剧本库 (Library)
    ⌥ + [ / ]       在当前工作区切换剧本 (Prev/Next Script)
    ⌥ + ⌘ + [ / ]   在不同工作区之间跳转 (Prev/Next Workspace)

    A               打开 AI 智播面板 (Ask AI)
    ESC             停止 AI 生成 或 关闭面板

    使用技巧：
    - 🔒 隐私模式：隐藏 Dock 图标并启用录屏抓取防护，退出需要二次确认。
    - 👻 幽灵模式：开启后鼠标穿透，结束倒计时后恢复交互。
    - 🎥 录屏防护：尽量让支持 macOS 捕获标记的软件忽略此窗口，请直播前实测。
    - 直接将文件夹拖入窗口，系统会按文件夹名称自动创建“工作区”。
    - 使用 V 键粘贴内容，系统会自动将其保存到“收集箱”中，永不丢失。
    - 开启“工作区上下文”设置，AI 将能感知当前文件夹下的所有关联文档。
    """

    func showHelp() {
        text = SparklePromptViewModel.defaultText
        activeScriptIndex = -1
        reset()
    }



    // MARK: - Playback controls

    func togglePlay() {
        print("⌨️ Spacebar pressed: Toggling play state to \(!isPlaying)")
        isPlaying.toggle()
        if isPlaying {
            start()
        } else {
            stop()
        }
    }

    func start() {
        // 1. 物理清理旧引擎，不触碰状态
        displayLink?.stop()
        displayLink = nil
        lastFrameTime = 0

        // 2. 注入硬件同步引擎 (VSync)
        displayLink = DisplayLink { [weak self] currentTime in
            guard let self = self, self.isPlaying else { return }

            // 计算两帧之间的物理时间差 (Delta Time)
            if self.lastFrameTime == 0 {
                self.lastFrameTime = currentTime
                return
            }
            let deltaTime = currentTime - self.lastFrameTime
            self.lastFrameTime = currentTime

            // 核心滚动逻辑：基于时间的位移 (位移 = 速度 * 时间)
            // 这确保了即使系统掉帧，文字也会精准跳到应该在的位置，视觉上极其丝滑
            let delta = CGFloat(self.speed * deltaTime)
            self.scrollOffset += delta

            // 自动停止逻辑
            let maxOffset = self.contentHeight + self.viewportHeight
            if maxOffset > 0 && self.scrollOffset > maxOffset {
                self.stop()
            }
        }

        displayLink?.start()

        if !isTimerActive {
            startTimer()
        }
    }

    /// 用户主动停止播放的入口
    func stop() {
        // 1. 同步修改 UI 状态
        isPlaying = false
        // 2. 彻底销毁高精度引擎
        displayLink?.stop()
        displayLink = nil
        lastFrameTime = 0
    }

    // MARK: - Action Toggles with Business Logic

    func toggleAlwaysOnTop() {
        // 🔒 安全锁定：隐私防护开启或幽灵模式运行中，置顶不允许关闭
        if isPrivacyMode || ghostModeTimeRemaining > 0 { return }
        alwaysOnTop.toggle()
    }

    func togglePrivacy() {
        // 🔒 安全锁定：幽灵模式运行中，隐私防护不允许关闭
        if ghostModeTimeRemaining > 0 { return }

        let now = Date()
        // 🛡️ 状态切换冷却保护：0.35 秒内禁止连续切换，防止窗口激活/键轴抖动导致状态回弹
        if now.timeIntervalSince(lastPrivacyTransitionTime) < 0.35 {
            return
        }

        if !isPrivacyMode {
            privacyExitConfirmationDeadline = nil
            isPrivacyMode = true
            lastPrivacyTransitionTime = now
            return
        }

        if let deadline = privacyExitConfirmationDeadline, now <= deadline {
            privacyExitConfirmationDeadline = nil
            isPrivacyMode = false
            lastPrivacyTransitionTime = now
        } else {
            privacyExitConfirmationDeadline = now.addingTimeInterval(privacyExitConfirmationInterval)
            return
        }

        // ✨ 安全救急：如果手动关闭了隐私模式，强制解除幽灵模式锁定
        if !isPrivacyMode {
            terminateGhostMode()
        }
    }

    func toggleControls() {
        if isPrivacyMode { return }
        showControls.toggle()
    }

    func toggleMirrorH() {
        // 🔒 安全锁定：隐私防护开启或幽灵模式运行中，禁止翻转画面
        if isPrivacyMode || ghostModeTimeRemaining > 0 { return }
        mirroredHorizontal.toggle()
    }

    func toggleMirrorV() {
        // 🔒 安全锁定：隐私防护开启或幽灵模式运行中，禁止翻转画面
        if isPrivacyMode || ghostModeTimeRemaining > 0 { return }
        mirroredVertical.toggle()
    }

    func startTimer() {
        guard !isTimerActive else { return }
        isTimerActive = true
        speechTimer?.invalidate()
        speechTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.timerElapsedTime += 1
            }
        }
    }

    func stopTimer() {
        isTimerActive = false
        speechTimer?.invalidate()
        speechTimer = nil
    }

    func toggleTimer() {
        if isTimerActive {
            stopTimer()
        } else {
            startTimer()
        }
    }

    func resetTimer() {
        stopTimer()
        timerElapsedTime = 0
    }

    func reset() {
        isPlaying = false
        stop()
        stopTimer()
        scrollOffset = 0
        timerElapsedTime = 0
    }

    func adjustSpeed(_ delta: Double)    { speed       = max(5, min(500, speed + delta)) }
    func adjustFontSize(_ delta: Double) { fontSize    = max(14, min(200, fontSize + delta)) }
    func adjustBgOpacity(_ delta: Double){ bgOpacity   = max(0, min(1, bgOpacity + delta)) }
    func adjustOpacity(_ delta: Double)  { textOpacity = max(0.1, min(1, textOpacity + delta)) }

    func pasteFromClipboard() {
        guard let content = NSPasteboard.general.string(forType: .string), !content.isEmpty else { return }

        // 1. 安全保存当前内容
        saveCurrentTextToLibrary()

        // 2. 创建新剧本
        let dateStr = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .short)
        let newScript = Script(title: "剪切板导入 (\(dateStr))", content: content)

        // 3. 强制定位到“收集箱”
        let targetWIndex = workspaces.firstIndex(where: { $0.name == "收集箱" }) ?? 0

        // 4. 在收集箱顶部插入
        workspaces[targetWIndex].scripts.insert(newScript, at: 0)

        // 5. 切换到新剧本
        switchToScript(at: 0, in: targetWIndex)

        showLibrary = true
        saveLibrary()
    }

    // MARK: - Script Library Management

    func importToLibrary() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, .text, .utf8PlainText]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.message = "选择文件或文件夹导入到剧本库"
        panel.prompt = "导入"

        guard panel.runModal() == .OK else { return }

        var changed = false
        for url in panel.urls {
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)

            if isDir.boolValue {
                // ✨ 检查是否已经存在关联该文件夹的工作区（用标准化路径 + Bookmark 双重比较）
                let importedPath = url.standardizedFileURL.path
                if let existingIndex = workspaces.firstIndex(where: { workspace in
                    // 优先用解析后的 URL 比较
                    if let existingPath = workspace.folderURL?.standardizedFileURL.path {
                        return existingPath == importedPath
                    }
                    return false
                }) {
                    activeWorkspaceIndex = existingIndex
                    refreshWorkspace(at: existingIndex)
                    changed = true
                    continue
                }

                let folderName = url.lastPathComponent
                var newScripts: [Script] = []

                if let enumerator = FileManager.default.enumerator(
                    at: url,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles]
                ) {
                    for case let fileURL as URL in enumerator {
                        let ext = fileURL.pathExtension.lowercased()
                        if ["txt", "md", "text"].contains(ext) {
                            if let script = Script.fromFile(fileURL) {
                                newScripts.append(script)
                            }
                        }
                    }
                }

                if !newScripts.isEmpty {
                    newScripts.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
                    let newWorkspace = Workspace(name: folderName, scripts: newScripts, folderURL: url)
                    workspaces.append(newWorkspace)
                    changed = true

                    activeWorkspaceIndex = workspaces.count - 1
                    switchToScript(at: 0, in: activeWorkspaceIndex)
                }
            } else {
                // 拖入的是单文件，加入当前 Workspace
                if let script = Script.fromFile(url) {
                    let existingURLs = Set(workspaces[activeWorkspaceIndex].scripts.compactMap { $0.url })
                    if !existingURLs.contains(url) {
                        workspaces[activeWorkspaceIndex].scripts.append(script)
                        workspaces[activeWorkspaceIndex].scripts.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
                        changed = true

                        if let idx = workspaces[activeWorkspaceIndex].scripts.firstIndex(where: { $0.id == script.id }) {
                            switchToScript(at: idx, in: activeWorkspaceIndex)
                        }
                    }
                }
            }
        }

        if changed { saveLibrary() }
    }

    // MARK: - Workspace Refresh

    func refreshWorkspace(at index: Int? = nil) {
        let targetIndex = index ?? activeWorkspaceIndex
        guard targetIndex >= 0 && targetIndex < workspaces.count else { return }

        // 无文件夹关联的工作区不需要刷新
        guard workspaces[targetIndex].folderURL != nil || workspaces[targetIndex].folderBookmark != nil else { return }

        // ✨ 解析文件夹 URL（处理重命名/移动）
        guard let folderURL = workspaces[targetIndex].resolveFolderURL() else {
            print("❌ 刷新失败：无法定位文件夹位置")
            return
        }

        let workspace = workspaces[targetIndex]
        let targetWorkspaceId = workspace.id
        let currentActiveId = (targetIndex == activeWorkspaceIndex && activeScriptIndex >= 0 && activeScriptIndex < workspace.scripts.count) ?
                             workspace.scripts[activeScriptIndex].id : nil

        var updatedScripts = workspace.scripts
        var changed = false

        // ✨ 驱动 UI 旋转动画
        refreshingWorkspaceId = workspace.id

        // 1. 获取磁盘上的有效文件列表
        let supportedExtensions = ["txt", "md", "text"]
        let fileManager = FileManager.default
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey, .fileResourceIdentifierKey]

        guard let enumerator = fileManager.enumerator(at: folderURL,
                                                      includingPropertiesForKeys: keys,
                                                      options: [.skipsHiddenFiles, .skipsPackageDescendants]) else {
            refreshingWorkspaceId = nil
            return
        }

        var diskFiles: [URL] = []
        while let fileURL = enumerator.nextObject() as? URL {
            if supportedExtensions.contains(fileURL.pathExtension.lowercased()) {
                diskFiles.append(fileURL)
            }
        }

        // 2. 建立内存索引（用于快速匹配）
        // 通过 id, URL 路径, 还有 Bookmark 数据（如果能解析的话）建立映射
        var scriptsByPath: [String: Int] = [:]
        for i in 0..<updatedScripts.count {
            if let path = updatedScripts[i].url?.standardizedFileURL.path {
                scriptsByPath[path] = i
            }
        }

        // 记录哪些内存条目被“认领”了，未被认领的非 AI 条目最后将被移除
        var claimedIndices = Set<Int>()
        var newDiskScripts: [Script] = []

        // 3. 遍历磁盘文件，匹配已有剧本或添加新剧本
        for fileURL in diskFiles {
            let standardizedPath = fileURL.standardizedFileURL.path

            // 匹配策略：
            // A. 尝试通过路径匹配
            // B. 尝试通过 Bookmark 匹配（这里简化处理，优先靠 resolveURL 同步路径）
            var matchedIndex: Int? = scriptsByPath[standardizedPath]

            // 如果路径没对上，尝试遍历一遍未认领的，看 Bookmark 能不能解析到这个 URL
            if matchedIndex == nil {
                for i in 0..<updatedScripts.count where !updatedScripts[i].isAIGenerated && !claimedIndices.contains(i) {
                    var script = updatedScripts[i]
                    if let resolved = script.resolveURL(), resolved.standardizedFileURL.path == standardizedPath {
                        matchedIndex = i
                        // 同步回全部变更（包括可能更新的 bookmarkData）
                        updatedScripts[i] = script
                        break
                    }
                }
            }

            if let i = matchedIndex {
                // ✨ 找到了匹配的已有剧本
                claimedIndices.insert(i)
                let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path)
                let diskModDate = attributes?[.modificationDate] as? Date

                // 更新标题（仅当用户没手动改过名时，跟随磁盘文件名）
                if !updatedScripts[i].isTitleCustomized {
                    let newTitle = fileURL.deletingPathExtension().lastPathComponent
                    if updatedScripts[i].title != newTitle {
                        updatedScripts[i].title = newTitle
                        changed = true
                    }
                }

                // 增量同步内容
                let needsUpdate: Bool
                if let diskDate = diskModDate, let cachedDate = updatedScripts[i].lastModifiedDate {
                    needsUpdate = diskDate > cachedDate
                } else {
                    needsUpdate = true
                }

                if needsUpdate {
                    if let newContent = try? String(contentsOf: fileURL, encoding: .utf8), newContent != updatedScripts[i].content {
                        updatedScripts[i].content = newContent
                        updatedScripts[i].lastModifiedDate = diskModDate
                        changed = true
                    } else {
                        updatedScripts[i].lastModifiedDate = diskModDate
                    }
                }

                // 确保运行时 URL 是最新的（防止磁盘重命名后路径变化）
                if updatedScripts[i].url != fileURL {
                    updatedScripts[i].url = fileURL
                    changed = true
                }
            } else {
                // ✨ 这是一个真正的新文件
                if let newScript = Script.fromFile(fileURL) {
                    newDiskScripts.append(newScript)
                    changed = true
                }
            }
        }

        // 4. 处理消失的剧本（未被认领的非 AI 条目直接移除）
        var finalScripts: [Script] = []
        for i in 0..<updatedScripts.count {
            if updatedScripts[i].isAIGenerated || claimedIndices.contains(i) {
                finalScripts.append(updatedScripts[i])
            } else {
                // 文件在磁盘扫描中未被匹配到，从列表移除
                changed = true
            }
        }

        // 5. 加入新剧本并重新排序
        finalScripts.append(contentsOf: newDiskScripts)
        finalScripts.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }

        // 6. 更新视图模型状态（通过 workspace ID 定位，防止延迟期间索引越界）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self = self else { return }
            guard let currentIndex = self.workspaces.firstIndex(where: { $0.id == targetWorkspaceId }) else {
                self.refreshingWorkspaceId = nil
                return
            }

            self.workspaces[currentIndex].scripts = finalScripts

            // 恢复选中状态
            if let currentId = currentActiveId, currentIndex == self.activeWorkspaceIndex {
                if let newIdx = finalScripts.firstIndex(where: { $0.id == currentId }) {
                    self.activeScriptIndex = newIdx
                } else {
                    self.activeScriptIndex = -1
                    self.text = SparklePromptViewModel.defaultText
                    self.reset()
                }
            }

            if changed { self.saveLibrary() }
            self.refreshingWorkspaceId = nil
        }
    }
    func refreshCurrentWorkspace() {
        refreshWorkspace(at: activeWorkspaceIndex)
    }


    func switchToScript(at scriptIndex: Int, in workspaceIndex: Int) {
        guard workspaceIndex >= 0, workspaceIndex < workspaces.count else { return }
        guard scriptIndex >= 0, scriptIndex < workspaces[workspaceIndex].scripts.count else { return }

        // 1. 先保存当前正在看的内容到旧的索引位置
        saveCurrentTextToLibrary()

        // 2. 更新索引
        activeWorkspaceIndex = workspaceIndex
        activeScriptIndex = scriptIndex

        // 3. 更新显示内容
        var script = workspaces[workspaceIndex].scripts[scriptIndex]
        isPlaying = false
        stop()

        let fileURL = script.resolveURL()
        // 同步可能已更新的 URL/Bookmark 状态到内存中
        if script.bookmarkData != workspaces[workspaceIndex].scripts[scriptIndex].bookmarkData ||
            script.url != workspaces[workspaceIndex].scripts[scriptIndex].url {
            workspaces[workspaceIndex].scripts[scriptIndex] = script
        }

        if script.content.isEmpty, let targetURL = fileURL {
            let targetScriptID = script.id
            Task {
                let loadedContent: String
                do {
                    let access = targetURL.startAccessingSecurityScopedResource()
                    defer { if access { targetURL.stopAccessingSecurityScopedResource() } }
                    loadedContent = try String(contentsOf: targetURL, encoding: .utf8)
                } catch {
                    print("❌ 从磁盘读取剧本失败: \(error.localizedDescription)")
                    loadedContent = ""
                }

                await MainActor.run {
                    // 竞态保护：确保异步加载完成时，当前激活的剧本仍然是这同一个
                    guard self.activeWorkspaceIndex == workspaceIndex,
                          self.activeScriptIndex == scriptIndex,
                          self.workspaces[workspaceIndex].scripts[scriptIndex].id == targetScriptID else {
                        return
                    }
                    self.workspaces[workspaceIndex].scripts[scriptIndex].content = loadedContent
                    self.suppressNextTextUpdate = true
                    self.text = loadedContent
                    self.scrollOffset = script.lastScrollOffset
                    self.updateAttributedText()

                    if !self.isInternalLoading && !self.isEditing {
                        self.saveSubject.send()
                    }
                }
            }
        } else {
            // 内容已在内存中，直接同步渲染
            suppressNextTextUpdate = true
            text = script.content
            scrollOffset = script.lastScrollOffset

            // 🚀 重要：立即更新渲染文本，绕过 100ms 的防抖延迟，防止页面切换时出现内容与偏移量不匹配的闪烁
            updateAttributedText()
            if !isInternalLoading && !isEditing {
                saveSubject.send()
            }
        }
    }

    func nextScript() {
        guard !workspaces[activeWorkspaceIndex].scripts.isEmpty else { return }
        let currentScripts = workspaces[activeWorkspaceIndex].scripts
        let next = activeScriptIndex + 1 < currentScripts.count ? activeScriptIndex + 1 : 0
        switchToScript(at: next, in: activeWorkspaceIndex)
    }

    func prevScript() {
        guard !workspaces[activeWorkspaceIndex].scripts.isEmpty else { return }
        let currentScripts = workspaces[activeWorkspaceIndex].scripts
        let prev = activeScriptIndex - 1 >= 0 ? activeScriptIndex - 1 : currentScripts.count - 1
        switchToScript(at: prev, in: activeWorkspaceIndex)
    }

    func prevWorkspace() {
        let nextIndex = activeWorkspaceIndex > 0 ? activeWorkspaceIndex - 1 : workspaces.count - 1
        switchToWorkspace(at: nextIndex)
    }

    func nextWorkspace() {
        let nextIndex = activeWorkspaceIndex + 1 < workspaces.count ? activeWorkspaceIndex + 1 : 0
        switchToWorkspace(at: nextIndex)
    }

    private func switchToWorkspace(at index: Int) {
        guard index >= 0 && index < workspaces.count else { return }
        activeWorkspaceIndex = index
        // 切换到工作区时，自动选中该工作区的第一个剧本（如果有的话）
        if !workspaces[index].scripts.isEmpty {
            switchToScript(at: 0, in: index)
        } else {
            activeScriptIndex = -1
            text = SparklePromptViewModel.defaultText
            reset()
        }
    }


    // MARK: - Move Script Between Workspaces (逻辑绑定，不动原始文件)

    func moveScript(from sourceWorkspace: Int, at scriptIndex: Int, to targetWorkspace: Int) {
        guard sourceWorkspace >= 0, sourceWorkspace < workspaces.count else { return }
        guard targetWorkspace >= 0, targetWorkspace < workspaces.count else { return }
        guard scriptIndex >= 0, scriptIndex < workspaces[sourceWorkspace].scripts.count else { return }
        guard sourceWorkspace != targetWorkspace else { return }

        let script = workspaces[sourceWorkspace].scripts[scriptIndex]

        // 1. 如果移动的是当前正在看的剧本，先切断引用
        let isMovingActive = (sourceWorkspace == activeWorkspaceIndex && scriptIndex == activeScriptIndex)
        if isMovingActive {
            activeScriptIndex = -1
            text = SparklePromptViewModel.defaultText
        }

        // 2. 从源工作区移除
        workspaces[sourceWorkspace].scripts.remove(at: scriptIndex)

        // 3. 插入到目标工作区（纯逻辑绑定，不写入物理文件夹）
        workspaces[targetWorkspace].scripts.append(script)
        workspaces[targetWorkspace].scripts.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }

        // 4. 处理源工作区索引调整
        if sourceWorkspace == activeWorkspaceIndex {
            if isMovingActive {
                activeWorkspaceIndex = targetWorkspace
                if let newIndex = workspaces[targetWorkspace].scripts.firstIndex(where: { $0.id == script.id }) {
                    switchToScript(at: newIndex, in: targetWorkspace)
                }
            } else if scriptIndex < activeScriptIndex {
                activeScriptIndex -= 1
            }
        }

        // 5. 如果源工作区被清空了
        if workspaces[sourceWorkspace].scripts.isEmpty && sourceWorkspace == activeWorkspaceIndex && !isMovingActive {
            activeScriptIndex = -1
            text = SparklePromptViewModel.defaultText
            reset()
        }

        saveLibrary()
        notifySaveSuccess()
    }

    // MARK: - Export Script to Disk

    func exportScript(at scriptIndex: Int, in workspaceIndex: Int) {
        guard workspaceIndex >= 0, workspaceIndex < workspaces.count else { return }
        guard scriptIndex >= 0, scriptIndex < workspaces[workspaceIndex].scripts.count else { return }

        let script = workspaces[workspaceIndex].scripts[scriptIndex]

        let panel = NSSavePanel()
        let safeName = script.title.replacingOccurrences(of: "/", with: "-")
                                   .replacingOccurrences(of: ":", with: "-")
        panel.nameFieldStringValue = "\(safeName).md"
        panel.allowedContentTypes = [.plainText, .text]
        panel.message = "将剧本导出为文件"
        panel.prompt = "导出"

        guard panel.runModal() == .OK, let targetURL = panel.url else { return }

        do {
            try script.content.write(to: targetURL, atomically: true, encoding: .utf8)
            print("✅ 已导出剧本: \(targetURL.lastPathComponent)")
            notifySaveSuccess()
        } catch {
            print("❌ 导出失败: \(error.localizedDescription)")
        }
    }

    // MARK: - Rename Script

    func renameScript(at scriptIndex: Int, in workspaceIndex: Int, to newName: String) {
        guard workspaceIndex >= 0, workspaceIndex < workspaces.count else { return }
        guard scriptIndex >= 0, scriptIndex < workspaces[workspaceIndex].scripts.count else { return }

        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        var script = workspaces[workspaceIndex].scripts[scriptIndex]
        let oldTitle = script.title
        script.title = trimmedName
        script.isTitleCustomized = true // ✨ 标记为自定义标题，刷新时不再被文件名覆盖

        // ✨ 如果是 AI 剧本，我们可以安全地重命名物理文件（在影子目录内）
        if script.isAIGenerated, let oldURL = script.url {
            let fileManager = FileManager.default
            let dir = oldURL.deletingLastPathComponent()
            let safeName = trimmedName.replacingOccurrences(of: "/", with: "-")
                                      .replacingOccurrences(of: ":", with: "-")
                                      .replacingOccurrences(of: "\n", with: " ")
            let ext = oldURL.pathExtension
            let newURL = dir.appendingPathComponent("\(safeName)-\(script.id.uuidString.prefix(8)).\(ext)")

            do {
                if fileManager.fileExists(atPath: oldURL.path) {
                    try fileManager.moveItem(at: oldURL, to: newURL)
                    script.url = newURL
                    // 更新 Bookmark 以追踪新位置
                    script.bookmarkData = try? newURL.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
                    print("✅ AI 物理文件已重命名: \(newURL.lastPathComponent)")
                }
            } catch {
                print("❌ AI 物理文件重命名失败: \(error.localizedDescription)")
            }
        } else {
            // 普通文件遵循“只读挂载”原则，不触碰物理文件，仅修改显示名称
            print("📝 普通剧本执行逻辑重命名: \(oldTitle) -> \(trimmedName)")
        }

        workspaces[workspaceIndex].scripts[scriptIndex] = script
        workspaces[workspaceIndex].scripts.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }

        // 如果重命名的是当前活动的剧本，更新索引以保持选中状态
        if workspaceIndex == activeWorkspaceIndex {
            if let newIdx = workspaces[workspaceIndex].scripts.firstIndex(where: { $0.id == script.id }) {
                activeScriptIndex = newIdx
            }
        }

        saveLibrary()
        notifySaveSuccess()
    }

    func removeScript(at scriptIndex: Int, in workspaceIndex: Int) {
        guard workspaceIndex >= 0, workspaceIndex < workspaces.count else { return }
        guard scriptIndex >= 0, scriptIndex < workspaces[workspaceIndex].scripts.count else { return }

        let script = workspaces[workspaceIndex].scripts[scriptIndex]

        // 1. 如果是当前正在看的剧本，先切断索引引用并重置文本
        // 🚀 重要：必须同时将 text 重置为默认值，否则 saveCurrentTextToLibrary 会因为 text 不为空而误创建一个新剧本
        let isDeletingActive = (workspaceIndex == activeWorkspaceIndex && scriptIndex == activeScriptIndex)
        if isDeletingActive {
            activeScriptIndex = -1
            text = SparklePromptViewModel.defaultText
        }

        // 2. ✨ 只对 AI 生成的剧本（影子目录内）执行物理删除
        //    普通挂载文件遵循"只读挂载"原则，仅从列表移除，不触碰用户磁盘文件
        if script.isAIGenerated, let url = script.url {
            do {
                if FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.removeItem(at: url)
                    print("✅ 已物理删除 AI 脚本文件: \(url.lastPathComponent)")
                }
            } catch {
                print("❌ 物理删除文件失败: \(error.localizedDescription)")
            }
        }

        // 3. 执行内存删除
        workspaces[workspaceIndex].scripts.remove(at: scriptIndex)

        // 4. 处理删除后的状态转移
        if workspaces[workspaceIndex].scripts.isEmpty {
            if workspaceIndex == activeWorkspaceIndex {
                activeScriptIndex = -1
                text = SparklePromptViewModel.defaultText
                reset()
            }
        } else if workspaceIndex == activeWorkspaceIndex {
            if isDeletingActive {
                // 如果删除的是当前激活的剧本，尝试切换到补位的那一个（如果处于末尾则切换到前一个）
                let newIndex = min(scriptIndex, workspaces[activeWorkspaceIndex].scripts.count - 1)
                switchToScript(at: newIndex, in: activeWorkspaceIndex)
            } else if scriptIndex < activeScriptIndex {
                // 如果删除的是当前剧本之前的剧本，更新当前高亮索引以保持其锚定正确的剧本
                activeScriptIndex -= 1
            }
        }
        saveLibrary()
    }

    func removeWorkspace(at index: Int) {
        guard index >= 0 && index < workspaces.count else { return }

        let workspaceId = workspaces[index].id

        // Don't remove the last workspace, clear it instead
        if workspaces.count == 1 {
            workspaces[0].scripts.removeAll()
            workspaces[0].name = "收集箱"
            activeScriptIndex = -1
            text = SparklePromptViewModel.defaultText
            reset()
        } else {
            workspaces.remove(at: index)
            if activeWorkspaceIndex == index {
                activeWorkspaceIndex = max(0, activeWorkspaceIndex - 1)
                if !workspaces[activeWorkspaceIndex].scripts.isEmpty {
                    switchToScript(at: 0, in: activeWorkspaceIndex)
                } else {
                    activeScriptIndex = -1
                    text = SparklePromptViewModel.defaultText
                    reset()
                }
            } else if index < activeWorkspaceIndex {
                activeWorkspaceIndex -= 1
            }
        }

        // ✨ 清理物理影子目录，防止产生孤儿文件
        let aiDir = SparklePromptViewModel.aiDirectory(for: workspaceId)
        try? FileManager.default.removeItem(at: aiDir)

        saveLibrary()
        notifySaveSuccess()
    }

    func handleDroppedFiles(_ urls: [URL]) {
        var changed = false
        for url in urls {
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)

            if isDir.boolValue {
                // 拖入的是文件夹，创建新的 Workspace
                let folderName = url.lastPathComponent
                var newScripts: [Script] = []

                if let enumerator = FileManager.default.enumerator(
                    at: url,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles]
                ) {
                    for case let fileURL as URL in enumerator {
                        let ext = fileURL.pathExtension.lowercased()
                        if ["txt", "md", "text"].contains(ext) {
                            if let script = Script.fromFile(fileURL) {
                                newScripts.append(script)
                            }
                        }
                    }
                }

                if !newScripts.isEmpty {
                    newScripts.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
                    let newWorkspace = Workspace(name: folderName, scripts: newScripts, folderURL: url)
                    workspaces.append(newWorkspace)
                    changed = true
                }
            } else {
                // 拖入单文件
                let existingURLs = Set(workspaces[activeWorkspaceIndex].scripts.compactMap { $0.url })
                if !existingURLs.contains(url), let script = Script.fromFile(url) {
                    workspaces[activeWorkspaceIndex].scripts.append(script)
                    workspaces[activeWorkspaceIndex].scripts.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
                    changed = true
                }
            }
        }

        if changed {
            saveLibrary()
        }
    }

    // MARK: - AI Streaming

    func fetchModels() {
        guard !aiBaseURL.isEmpty else {
            let status = ProviderStatus.customError(message: "Base URL 不能为空")
            self.providerStatuses[aiProvider] = status
            self.apiTestStatus = status.displayText
            return
        }

        isTestingAPI = true
        let status = ProviderStatus.testing
        self.providerStatuses[aiProvider] = status
        self.apiTestStatus = status.displayText

        Task {
            do {
                let models = try await aiService.fetchAvailableModels(baseURL: aiBaseURL, apiKey: aiAPIKey, provider: aiProvider)
                self.availableModels = models
                if !models.contains(self.aiModel) && !models.isEmpty {
                    self.aiModel = models.first!
                }
                let status = ProviderStatus.success(modelCount: models.count)
                self.providerStatuses[aiProvider] = status
                self.apiTestStatus = status.displayText
                self.isTestingAPI = false
            } catch let error as NSError {
                let status: ProviderStatus
                if error.domain == "APIError" {
                    status = .configError(code: error.code, message: error.localizedDescription)
                } else if error.domain == NSURLErrorDomain || error.code == -1001 || error.code == -1005 || error.code == NSURLErrorCannotConnectToHost {
                    status = .networkError(message: error.localizedDescription)
                } else {
                    status = .customError(message: "测试失败: \(error.localizedDescription)")
                }
                self.providerStatuses[aiProvider] = status
                self.apiTestStatus = status.displayText
                self.isTestingAPI = false
            }
        }
    }

    func submitAIPrompt() {
        guard !aiPrompt.isEmpty && !isAIStreaming else { return }

        let prompt = aiPrompt
        let key = aiAPIKey
        let model = aiModel
        let baseURL = aiBaseURL
        // 1. 拼接系统提示词（个人风格 + 角色设定），保持前缀极其稳定以压榨缓存命中率
        let personalStyleHeader = aiPersonalStyle.isEmpty ? "" : "【个人风格偏好】\n\(aiPersonalStyle)\n\n"
        let rolePrompt = aiRoles.indices.contains(selectedRoleIndex) ? aiRoles[selectedRoleIndex].prompt : ""
        let sysPrompt = "\(personalStyleHeader)\(rolePrompt)"

        // 2. 构造上下文
        var contextText: String? = nil
        if useAnyContextForAI && text != SparklePromptViewModel.defaultText {
            if useWorkspaceContextForAI {
                // ✨ 确定性拼接：按标题排序，确保只要文件内容没变，拼接后的字符串物理顺序一致，从而命中前缀缓存
                let workspaceScripts = workspaces[activeWorkspaceIndex].scripts
                    .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }

                let allText = workspaceScripts.map { script -> String in
                    var content = script.content
                    if content.isEmpty, let targetURL = script.url {
                        let access = targetURL.startAccessingSecurityScopedResource()
                        defer { if access { targetURL.stopAccessingSecurityScopedResource() } }
                        content = (try? String(contentsOf: targetURL, encoding: .utf8)) ?? ""
                    }
                    return "标题：\(script.title)\n内容：\(content)"
                }.joined(separator: "\n\n---\n\n")
                let fullContext = "当前工作区【\(workspaces[activeWorkspaceIndex].name)】包含以下资料：\n\(allText)"

                // 安全限制：估算 token 数并截断。混合中英文场景下约 1.5~2 字符/token，
                // 保守按 1.5 估算，限制在 8000 tokens 以内以兼容大多数模型 context window。
                let estimatedTokens = fullContext.count * 2 / 3  // ~1.5 chars per token
                let maxTokens = 8000
                if estimatedTokens > maxTokens {
                    let maxChars = maxTokens * 3 / 2  // reverse estimation
                    contextText = String(fullContext.prefix(maxChars)) + "\n\n...(内容过长，已自动截断至约 \(maxTokens) tokens)"
                } else {
                    contextText = fullContext
                }
            } else {
                contextText = text
            }
        }

        aiErrorMessage = ""
        isAIStreaming = true
        showAIPromptBar = false
        autoFollowEnabled = true

        let titlePreview = String(prompt.prefix(20))
        let scriptId = UUID()

        // ✨ AI 生成的剧本存储到 App 影子目录，不污染用户文件夹
        let aiDir = SparklePromptViewModel.aiDirectory(for: workspaces[activeWorkspaceIndex].id)
        let safeName = titlePreview.replacingOccurrences(of: "/", with: "-")
                                   .replacingOccurrences(of: ":", with: "-")
                                   .replacingOccurrences(of: "\n", with: " ")
        let aiFileURL = aiDir.appendingPathComponent("\(safeName)-\(scriptId.uuidString.prefix(8)).md")

        let newScript = Script(
            id: scriptId,
            title: "AI: \(titlePreview)…",
            content: "",
            url: aiFileURL,
            isAIGenerated: true
        )

        // Add to active workspace
        workspaces[activeWorkspaceIndex].scripts.append(newScript)

        // Clear context when creating new AI script
        useAnyContextForAI = false
        let targetWorkspaceIndex = activeWorkspaceIndex
        let targetScriptIndex = workspaces[activeWorkspaceIndex].scripts.count - 1

        activeScriptIndex = targetScriptIndex
        text = ""
        reset()

        Task {
            var fullResponse = ""

            // Build failover providers list based on priority
            var failoverProviders: [(provider: AIProvider, apiKey: String, baseURL: String, model: String)] = []
            if enableFailover {
                for provider in providerPriority {
                    if provider != aiProvider {
                        let isLocal = provider.isLocal
                        let pKey = providerKeys[provider] ?? (isLocal ? "not-needed" : "")
                        let pURL = providerURLs[provider] ?? provider.defaultBaseURL
                        let pModel = providerSelectedModels[provider] ?? ""

                        let hasValidKey = isLocal || !pKey.isEmpty
                        if hasValidKey && !pModel.isEmpty && !pURL.isEmpty {
                            failoverProviders.append((provider, pKey, pURL, pModel))
                        }
                    }
                }
            }

            await aiService.stream(
                apiKey: key,
                baseURL: baseURL,
                prompt: prompt,
                systemPrompt: sysPrompt,
                model: model,
                provider: aiProvider,
                enableThinking: enableDeepSeekThinking,
                context: contextText,
                failoverProviders: failoverProviders,
                onChunk: { [weak self] chunk in
                    guard let self = self else { return }
                    fullResponse += chunk

                    // 如果用户还在看这个 AI 脚本，更新实时显示
                    if self.activeWorkspaceIndex == targetWorkspaceIndex && self.activeScriptIndex == targetScriptIndex {
                        self.text = fullResponse
                        // 注意：这里不再手动调用 scrollToBottom()，
                        // 而是通过 contentHeight 的 didSet 自动响应渲染后的高度变化。
                    }

                    // 无论用户在看哪里，始终静默更新数据模型中的内容
                    if targetWorkspaceIndex < self.workspaces.count && targetScriptIndex < self.workspaces[targetWorkspaceIndex].scripts.count {
                        self.workspaces[targetWorkspaceIndex].scripts[targetScriptIndex].content = fullResponse
                    }
                },
                onDone: { [weak self] in
                    guard let self = self else { return }
                    self.isAIStreaming = false
                    self.aiPrompt = ""

                    // ✨ 将 AI 生成的内容写入影子目录文件
                    if targetWorkspaceIndex < self.workspaces.count && targetScriptIndex < self.workspaces[targetWorkspaceIndex].scripts.count {
                        let script = self.workspaces[targetWorkspaceIndex].scripts[targetScriptIndex]
                        if let fileURL = script.url {
                            try? script.content.write(to: fileURL, atomically: true, encoding: .utf8)
                        }
                    }

                    self.saveLibrary()
                },
                onError: { [weak self] error in
                    guard let self = self else { return }
                    self.isAIStreaming = false
                    self.aiErrorMessage = error
                    self.showAIPromptBar = true
                }
            )
        }
    }

    func cancelAIGeneration() {
        Task { await aiService.cancel() }
        isAIStreaming = false
    }

    func scrollToBottom() {
        // 计算目标偏移量：让最新的内容出现在屏幕中下方（留出约 40% 的视口缓冲空间）
        let target = max(0, contentHeight - viewportHeight * 0.4)

        // 使用轻微的平滑动画，让 AI 生成时的文字滚动看起来更像“生长”而非“跳变”
        withAnimation(.easeOut(duration: 0.2)) {
            scrollOffset = target
        }
    }

    func handleScrollWheel(deltaY: CGFloat, multiplier: CGFloat = 12.0) {
        let adjustment = -deltaY * multiplier
        if isAIStreaming && autoFollowEnabled && abs(deltaY) > 0.1 {
            autoFollowEnabled = false
        }
        let maxOffset = contentHeight + viewportHeight
        scrollOffset = max(0, min(maxOffset, scrollOffset + adjustment))
    }


    // MARK: - Visual Settings Persistence
    func loadVisualSettings() {
        isInternalLoading = true
        defer { isInternalLoading = false }

        if let speed = UserDefaults.standard.object(forKey: "Pref_speed") as? Double { self.speed = speed }
        if let fontSize = UserDefaults.standard.object(forKey: "Pref_fontSize") as? Double { self.fontSize = fontSize }
        if let lineSpacing = UserDefaults.standard.object(forKey: "Pref_lineSpacing") as? Double { self.lineSpacing = lineSpacing }
        if let textOpacity = UserDefaults.standard.object(forKey: "Pref_textOpacity") as? Double { self.textOpacity = textOpacity }
        if let bgOpacity = UserDefaults.standard.object(forKey: "Pref_bgOpacity") as? Double { self.bgOpacity = bgOpacity }
        if let textColorHex = UserDefaults.standard.string(forKey: "Pref_textColorHex"),
           let nsColor = NSColor(hex: textColorHex) {
            self.textColor = Color(nsColor)
        }
        if let readingLineColorHex = UserDefaults.standard.string(forKey: "Pref_readingLineColorHex"),
           let nsColor = NSColor(hex: readingLineColorHex) {
            self.readingLineColor = Color(nsColor)
        }
        if let aiAccentColorHex = UserDefaults.standard.string(forKey: "Pref_aiAccentColorHex"),
           let nsColor = NSColor(hex: aiAccentColorHex) {
            self.accentColor = Color(nsColor)
        }
        // ⚡️ isPrivacyMode 只在初始化时从 UserDefaults 恢复
        // 运行时由 UserDefaults.didChangeNotification 触发的 reload 不得覆盖
        // 否则会因 save debounce（1s）> notification debounce（500ms）导致状态回弹
        if !hasCompletedInitialLoad {
            if let isPrivacy = UserDefaults.standard.object(forKey: "Pref_isPrivacyMode") as? Bool {
                self.isPrivacyMode = isPrivacy
            }
        }
        if let onTop = UserDefaults.standard.object(forKey: "Pref_alwaysOnTop") as? Bool {
            self.alwaysOnTop = onTop
        }
    }

    func saveVisualSettings() {
        guard !isResetting else { return }
        UserDefaults.standard.set(speed, forKey: "Pref_speed")
        UserDefaults.standard.set(fontSize, forKey: "Pref_fontSize")
        UserDefaults.standard.set(lineSpacing, forKey: "Pref_lineSpacing")
        UserDefaults.standard.set(textOpacity, forKey: "Pref_textOpacity")
        UserDefaults.standard.set(bgOpacity, forKey: "Pref_bgOpacity")
        if let hex = NSColor(textColor).toHex() {
            UserDefaults.standard.set(hex, forKey: "Pref_textColorHex")
        }
        if let hex = NSColor(readingLineColor).toHex() {
            UserDefaults.standard.set(hex, forKey: "Pref_readingLineColorHex")
        }
        if let hex = NSColor(accentColor).toHex() {
            UserDefaults.standard.set(hex, forKey: "Pref_aiAccentColorHex")
        }
        UserDefaults.standard.set(isPrivacyMode, forKey: "Pref_isPrivacyMode")
        UserDefaults.standard.set(alwaysOnTop, forKey: "Pref_alwaysOnTop")
    }
}

extension NSColor {
    convenience init?(hex: String) {
        let hexString = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        let scanner = Scanner(string: hexString)
        if hexString.hasPrefix("#") { scanner.currentIndex = scanner.string.index(after: scanner.currentIndex) }
        var color: UInt64 = 0
        guard scanner.scanHexInt64(&color) else { return nil }
        let r, g, b, a: CGFloat
        let cleanHex = hexString.hasPrefix("#") ? String(hexString.dropFirst()) : hexString
        if cleanHex.count == 8 {
            r = CGFloat((color & 0xff000000) >> 24) / 255
            g = CGFloat((color & 0x00ff0000) >> 16) / 255
            b = CGFloat((color & 0x0000ff00) >> 8) / 255
            a = CGFloat(color & 0x000000ff) / 255
        } else if cleanHex.count == 6 {
            r = CGFloat((color & 0xff0000) >> 16) / 255
            g = CGFloat((color & 0x00ff00) >> 8) / 255
            b = CGFloat(color & 0x0000ff) / 255
            a = 1.0
        } else { return nil }
        self.init(red: r, green: g, blue: b, alpha: a)
    }

    func toHex() -> String? {
        guard let rgbColor = usingColorSpace(.sRGB) else { return nil }
        let r = Int(round(rgbColor.redComponent * 255))
        let g = Int(round(rgbColor.greenComponent * 255))
        let b = Int(round(rgbColor.blueComponent * 255))
        let a = Int(round(rgbColor.alphaComponent * 255))
        return String(format: "#%02X%02X%02X%02X", r, g, b, a)
    }
}
