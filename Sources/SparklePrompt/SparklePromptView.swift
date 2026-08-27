import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SparklePromptView: View {
    @ObservedObject var viewModel: SparklePromptViewModel

    private var controlsShortcutText: String {
        if let shortcut = viewModel.shortcuts[.toggleControls] {
            return "按 \(shortcut.displayString) 显示控制栏"
        }
        return "显示控制栏"
    }

    var body: some View {
        HStack(spacing: 0) {
            mainSurface

            if viewModel.showLibrary {
                LibrarySidebar(viewModel: viewModel)
                    .transition(.identity)
            }
        }
        .ignoresSafeArea()
        // CRITICAL: No SwiftUI animation on showLibrary. The AppKit window resize
        // handles the visual transition. SwiftUI just responds to available space.
        .animation(nil, value: viewModel.showLibrary)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
        }
    }

    private var mainSurface: some View {
        ZStack {
            promptBackground
            promptTextLayer
            topStatusLayer
            readingLineLayer
            bottomControlLayer
            overlayLayer

            KeyEventBridge(viewModel: viewModel)
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.showControls)
        .animation(.easeInOut(duration: 0.2), value: viewModel.isEditing)
        .animation(.easeInOut(duration: 0.2), value: viewModel.showSettings)
    }

    private var promptBackground: some View {
        ZStack {
            viewModel.presentationStyle.backgroundColor
                .opacity(viewModel.bgOpacity)

            StealthCursorView(isPrivacyMode: viewModel.isPrivacyMode)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea()
    }

    private var promptTextLayer: some View {
        GeometryReader { geo in
            ScrollingText(viewModel: viewModel, size: geo.size)
                .onAppear { viewModel.viewportHeight = geo.size.height }
                .onChange(of: geo.size) { _, new in viewModel.viewportHeight = new.height }
        }
        .opacity(viewModel.textOpacity * viewModel.presentationStyle.textOpacityMultiplier)
        .scaleEffect(
            x: viewModel.mirroredHorizontal ? -1 : 1,
            y: viewModel.mirroredVertical ? -1 : 1
        )
        .allowsHitTesting(false)
    }

    private var topStatusLayer: some View {
        VStack(spacing: 0) {
            if viewModel.showAIPromptBar {
                AIPromptBar(viewModel: viewModel)
                    .transition(.move(edge: .top).combined(with: .opacity))
            } else if viewModel.isAIStreaming {
                AIStreamingBanner(viewModel: viewModel)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            Spacer()
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: viewModel.showAIPromptBar)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: viewModel.isAIStreaming)
    }

    @ViewBuilder
    private var readingLineLayer: some View {
        if viewModel.showControls {
            ReadingLine(viewModel: viewModel)
                .allowsHitTesting(false)
        }
    }

    private var bottomControlLayer: some View {
        VStack {
            Spacer()
            if viewModel.showControls {
                ControlsBar(viewModel: viewModel)
                    .padding(.bottom, 20)
                    .padding(.horizontal, 20)
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .opacity
                        )
                    )
            } else {
                controlHint
                    .padding(.bottom, 12)
                    .padding(.trailing, 16)
            }
        }
    }

    private var controlHint: some View {
        HStack {
            Spacer()
            if viewModel.isPrivacyMode {
                Button(action: { viewModel.showSettings = true }) {
                    Image(systemName: "shield.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(viewModel.presentationStyle.secondaryTextColor.opacity(0.10))
                        .frame(width: 28, height: 28)
                        .background(
                            viewModel.presentationStyle.secondaryTextColor.opacity(0.02),
                            in: Circle()
                        )
                }
                .buttonStyle(.plain)
                .help("隐私设置")
            } else {
                Text(controlsShortcutText)
                    .font(.caption)
                    .foregroundColor(
                        viewModel.presentationStyle.secondaryTextColor.opacity(viewModel.presentationStyle.hintOpacity)
                    )
            }
        }
    }

    @ViewBuilder
    private var overlayLayer: some View {
        if viewModel.isEditing {
            EditorOverlay(viewModel: viewModel)
                .transition(.opacity)
        }

        if viewModel.showSettings {
            SettingsOverlay(viewModel: viewModel)
                .transition(.opacity)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil)
                else { return }
                Task { @MainActor in
                    viewModel.handleDroppedFiles([url])
                }
            }
            handled = true
        }
        return handled
    }
}

// MARK: - Scrolling Text

private struct ScrollingText: View {
    @ObservedObject var viewModel: SparklePromptViewModel
    let size: CGSize

    var body: some View {
        Text(viewModel.attributedText)
            .multilineTextAlignment((viewModel.isCodeMode || viewModel.isCodeDetected) ? .leading : .center)
            .lineSpacing(CGFloat(viewModel.lineSpacing))
            .shadow(color: .black.opacity(viewModel.presentationStyle.shadowOpacity), radius: viewModel.presentationStyle.shadowRadius, x: 0, y: viewModel.presentationStyle.shadowYOffset)
            .blur(radius: viewModel.presentationStyle.blurRadius)
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: max(200, size.width * 0.9), alignment: (viewModel.isCodeMode || viewModel.isCodeDetected) ? .leading : .center)
            .background(
                GeometryReader { textGeo in
                    Color.clear
                        .onAppear { viewModel.contentHeight = textGeo.size.height }
                        .onChange(of: textGeo.size.height) { _, new in viewModel.contentHeight = new }
                }
            )
            .frame(width: size.width, alignment: .center)
            .offset(y: size.height * 0.5 - viewModel.scrollOffset)
    }
}

// MARK: - Reading Line

private struct ReadingLine: View {
    @ObservedObject var viewModel: SparklePromptViewModel
    var lineColor: Color { viewModel.isAIStreaming ? viewModel.accentColor : viewModel.readingLineColor }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Rectangle()
                    .fill(LinearGradient(
                        colors: [.clear, lineColor.opacity(0.55), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    ))
                    .frame(height: 2)
                    .position(x: geo.size.width / 2, y: geo.size.height * 0.5)

                Triangle()
                    .fill(lineColor.opacity(0.7))
                    .frame(width: 10, height: 10)
                    .rotationEffect(.degrees(90))
                    .position(x: 14, y: geo.size.height * 0.5)
                Triangle()
                    .fill(lineColor.opacity(0.7))
                    .frame(width: 10, height: 10)
                    .rotationEffect(.degrees(-90))
                    .position(x: geo.size.width - 14, y: geo.size.height * 0.5)
            }
        }
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

// MARK: - AI Prompt Bar (inline at the top)

private struct AIPromptBar: View {
    @ObservedObject var viewModel: SparklePromptViewModel
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                // 1. Header: Title, role/model tags, and close button
                HStack(spacing: 12) {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .foregroundColor(viewModel.presentationStyle.accentColor)
                            .font(.system(size: 13, weight: .bold))
                        Text("Sparkle AI")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(viewModel.presentationStyle.secondaryTextColor)
                    }

                    Spacer()

                    let roleName = viewModel.aiRoles.indices.contains(viewModel.selectedRoleIndex) ? viewModel.aiRoles[viewModel.selectedRoleIndex].name : "未知角色"
                    labelTag(text: roleName, icon: "person.fill")
                    labelTag(text: viewModel.cleanedModelName, icon: "cpu.fill")

                    Button(action: { viewModel.showAIPromptBar = false }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(viewModel.presentationStyle.secondaryTextColor.opacity(0.5))
                            .frame(width: 20, height: 20)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

                // 2. Input Box: TextEditor styled with rounded border and subtle background, focused style
                ZStack(alignment: .topLeading) {
                    if viewModel.aiPrompt.isEmpty {
                        Text("给 AI 发送指令，定制生成剧本或修改文本...")
                            .font(.system(size: 13))
                            .foregroundColor(viewModel.presentationStyle.secondaryTextColor.opacity(0.35))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .allowsHitTesting(false)
                    }

                    TextEditor(text: $viewModel.aiPrompt)
                        .font(.system(size: 13))
                        .foregroundColor(viewModel.presentationStyle.secondaryTextColor)
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                        .frame(minHeight: 50, maxHeight: 120)
                        .tint(viewModel.presentationStyle.accentColor)
                        .focused($isFocused)
                        .background(TextViewIntrospector { textView in
                            textView.textContainerInset = .zero
                            textView.textContainer?.lineFragmentPadding = 0
                        })
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .onKeyPress { keyPress in
                            if keyPress.key == .return {
                                if keyPress.modifiers.contains(.shift) {
                                    return .ignored
                                } else {
                                    viewModel.submitAIPrompt()
                                    return .handled
                                }
                            }
                            return .ignored
                        }
                }
                .background(viewModel.isPrivacyMode ? Color.clear : Color.black.opacity(0.25))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isFocused ? viewModel.presentationStyle.accentColor.opacity(viewModel.isPrivacyMode ? 0.0 : 0.7) : Color.white.opacity(viewModel.presentationStyle.panelBorderOpacity * 0.8), lineWidth: 1)
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

                // 3. Footer: Context toggle on the left, Send/Submit action on the right
                HStack {
                    HStack(spacing: 8) {
                        Text("背景上下文:")
                            .font(.system(size: 10))
                            .foregroundColor(viewModel.presentationStyle.secondaryTextColor.opacity(viewModel.isPrivacyMode ? 0.25 : 0.4))

                        if viewModel.useAnyContextForAI {
                            if viewModel.useWorkspaceContextForAI {
                                clickableContextTag(text: "工作区全量", icon: "folder.fill", viewModel: viewModel)
                            } else {
                                clickableContextTag(text: viewModel.currentScriptNameShort, icon: "doc.text.fill", viewModel: viewModel)
                            }
                        } else {
                            clickableNoContextTag(viewModel: viewModel)
                        }
                    }

                    Spacer()

                    Button(action: { viewModel.submitAIPrompt() }) {
                        HStack(spacing: 6) {
                            Text(viewModel.isPreparingAIContext ? "准备中" : "发送")
                                .font(.system(size: 11, weight: .bold))
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 10))
                        }
                        .foregroundColor(
                            viewModel.isPrivacyMode
                                ? viewModel.presentationStyle.secondaryTextColor.opacity(isSubmitDisabled ? 0.2 : 0.45)
                                : (isSubmitDisabled ? viewModel.presentationStyle.secondaryTextColor.opacity(0.3) : .white)
                        )
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(
                            viewModel.isPrivacyMode
                                ? (isSubmitDisabled ? Color.clear : viewModel.presentationStyle.secondaryTextColor.opacity(0.08))
                                : (isSubmitDisabled ? viewModel.presentationStyle.secondaryTextColor.opacity(0.08) : viewModel.presentationStyle.accentColor)
                        )
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(isSubmitDisabled)
                    .animation(.easeInOut(duration: 0.15), value: isSubmitDisabled)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            }
            .background { PanelBackground(bgOpacity: viewModel.bgOpacity, style: viewModel.presentationStyle, usesMaterial: !viewModel.isPrivacyMode) }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(viewModel.presentationStyle.panelBorderOpacity), lineWidth: 1)
            )
            .shadow(color: .black.opacity(viewModel.presentationStyle.shadowOpacity * 0.8), radius: viewModel.presentationStyle.shadowRadius * 6, x: 0, y: viewModel.presentationStyle.shadowYOffset * 4)
            .opacity(viewModel.presentationStyle.panelOpacityMultiplier)
            .blur(radius: viewModel.presentationStyle.blurRadius)
            .frame(maxWidth: 600)
            .padding(.horizontal, 20)
            .padding(.top, 16)


            // Error message
            if !viewModel.aiErrorMessage.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(viewModel.isPrivacyMode ? viewModel.presentationStyle.accentColor : .orange)
                        .font(.system(size: 11))
                    Text(viewModel.aiErrorMessage)
                        .font(.caption)
                        .foregroundColor(viewModel.isPrivacyMode ? viewModel.presentationStyle.secondaryTextColor : .orange)
                        .lineLimit(2)
                        .truncationMode(.tail)
                    Spacer()
                }
                .padding(.horizontal, 32)
                .padding(.top, 8)
            }
        }
        .onAppear {
            viewModel.windowController?.window?.makeKey()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                isFocused = true
            }
        }
    }

    private var isSubmitDisabled: Bool {
        viewModel.aiPrompt.isEmpty || viewModel.isAIStreaming || viewModel.isPreparingAIContext
    }

    private func labelTag(text: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.system(size: 10, weight: .medium))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            viewModel.isPrivacyMode
                ? viewModel.presentationStyle.secondaryTextColor.opacity(0.04)
                : viewModel.presentationStyle.accentColor.opacity(0.12)
        )
        .foregroundColor(
            viewModel.isPrivacyMode
                ? viewModel.presentationStyle.secondaryTextColor.opacity(0.35)
                : viewModel.presentationStyle.accentColor
        )
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(
                    viewModel.isPrivacyMode
                        ? Color.clear
                        : viewModel.presentationStyle.accentColor.opacity(0.25),
                    lineWidth: viewModel.isPrivacyMode ? 0 : 0.5
                )
        )
    }
}

// MARK: - AI Streaming Banner

private struct AIStreamingBanner: View {
    @ObservedObject var viewModel: SparklePromptViewModel
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(
                    viewModel.isPrivacyMode
                        ? viewModel.presentationStyle.secondaryTextColor.opacity(0.3)
                        : (viewModel.autoFollowEnabled ? viewModel.presentationStyle.accentColor : Color.gray)
                )
                .frame(width: 8, height: 8)
                .scaleEffect(pulse ? 1.3 : 0.8)
                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulse)

            Text(statusText)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(viewModel.presentationStyle.secondaryTextColor.opacity(0.9))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()

            if !viewModel.autoFollowEnabled {
                Button(action: {
                    viewModel.autoFollowEnabled = true
                    viewModel.scrollToBottom()
                }) {
                    Label("恢复追随", systemImage: "arrow.down.to.line.compact")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(
                            viewModel.isPrivacyMode
                                ? viewModel.presentationStyle.secondaryTextColor.opacity(0.45)
                                : viewModel.presentationStyle.accentColor
                        )
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            viewModel.isPrivacyMode
                                ? viewModel.presentationStyle.secondaryTextColor.opacity(0.06)
                                : viewModel.presentationStyle.accentColor.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 6)
                        )
                }
                .buttonStyle(.borderless)
            }

            Button(action: { viewModel.cancelAIGeneration() }) {
                Text("停止")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(
                        viewModel.isPrivacyMode
                            ? viewModel.presentationStyle.secondaryTextColor.opacity(0.4)
                            : .red
                    )
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        viewModel.isPrivacyMode
                            ? viewModel.presentationStyle.secondaryTextColor.opacity(0.06)
                            : Color.red.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 6)
                    )
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background { PanelBackground(bgOpacity: viewModel.bgOpacity, style: viewModel.presentationStyle, usesMaterial: !viewModel.isPrivacyMode) }
        .panelChrome(style: viewModel.presentationStyle)
        .opacity(viewModel.presentationStyle.panelOpacityMultiplier)
        .blur(radius: viewModel.presentationStyle.blurRadius)
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .onAppear { pulse = true }
    }

    private var statusText: String {
        if viewModel.isPreparingAIContext {
            return "正在准备工作区上下文…"
        }

        return viewModel.autoFollowEnabled ? "AI 生成中…" : "已锁定位置 (AI 继续生成中)"
    }
}

// MARK: - Controls Bar

private struct ControlsBar: View {
    @ObservedObject var viewModel: SparklePromptViewModel

    var body: some View {
        ViewThatFits(in: .horizontal) {
            // 1. 完整版：功能全开
            controlsContent(density: .full)
            // 2. 标准版：折叠部分设置项
            controlsContent(density: .standard)
            // 3. 极简版：仅保留核心安全指标
            controlsContent(density: .compact)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16) // ✨ 恢复标准内边距，提升呼吸感
        .padding(.vertical, 10)
        .background { PanelBackground(bgOpacity: viewModel.bgOpacity, style: viewModel.presentationStyle, usesMaterial: !viewModel.isPrivacyMode) }
        .panelChrome(style: viewModel.presentationStyle)
        .opacity(viewModel.presentationStyle.panelOpacityMultiplier)
        .blur(radius: viewModel.presentationStyle.blurRadius)
    }

    private enum Density { case full, standard, compact }

    @ViewBuilder
    private func controlsContent(density: Density) -> some View {
        let spacing: CGFloat = density == .compact ? 10 : (density == .standard ? 14 : 18)
        let iconSize: CGFloat = 15

        HStack(spacing: spacing) {
            // Playback Group
            HStack(spacing: 8) {
                Button(action: viewModel.togglePlay) {
                    Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: iconSize + 1, weight: .bold))
                        .frame(width: 24, height: 24)
                }
                Button(action: viewModel.reset) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: iconSize - 1, weight: .medium))
                }
            }

            Divider().frame(height: 16).background(Color.white.opacity(viewModel.presentationStyle.dividerOpacity))

            // Timer Widget (Unified with Ghost Mode)
            Button(action: {
                if viewModel.mousePenetration {
                    // 幽灵模式下点击无效（虽然点不到，但逻辑上保持一致）
                } else if viewModel.isGhostModePending {
                    viewModel.cancelGhostPrep()
                } else {
                    viewModel.toggleTimer()
                }
            }) {
                HStack(spacing: 6) {
                    switch viewModel.timerDisplayMode {
                    case .ghostPrep:
                        Image(systemName: "hourglass.badge.plus")
                            .font(.system(size: iconSize - 2))
                            .foregroundColor(.orange)
                        Text("READY \(viewModel.ghostModeCountdown)")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(.orange)

                    case .ghostRun:
                        Image(systemName: "lock.fill")
                            .font(.system(size: iconSize - 2))
                            .foregroundColor(.orange)
                        Text(formatTime(viewModel.ghostModeTimeRemaining))
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(.orange)
                            .frame(width: 52, alignment: .leading)

                    case .speech:
                        Image(systemName: "timer")
                            .font(.system(size: iconSize - 2))
                            .foregroundColor(viewModel.isTimerActive ? viewModel.presentationStyle.accentColor : viewModel.presentationStyle.secondaryTextColor.opacity(0.4))
                        Text(formatTime(viewModel.timerElapsedTime))
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(viewModel.isTimerActive ? viewModel.presentationStyle.secondaryTextColor : viewModel.presentationStyle.secondaryTextColor.opacity(0.6))
                            .frame(width: 52, alignment: .leading)
                    }
                }
            }
            .buttonStyle(.plain)
            .help(viewModel.mousePenetration ? "幽灵模式锁定中" : "计时器")

            Divider().frame(height: 16).background(Color.white.opacity(viewModel.presentationStyle.dividerOpacity))

            // ✨ 极简模式：语速调节 (稍微放宽一点宽度)
            if density == .compact {
                HStack(spacing: 6) {
                    Image(systemName: "speedometer").font(.system(size: 11)).foregroundColor(viewModel.presentationStyle.accentColor)
                    Slider(value: $viewModel.speed, in: 5...300).frame(width: 60)
                    Text("\(Int(viewModel.speed))")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(viewModel.presentationStyle.secondaryTextColor.opacity(0.8))
                        .frame(width: 24, alignment: .trailing)
                }

                Divider().frame(height: 16).background(Color.white.opacity(viewModel.presentationStyle.dividerOpacity))
            }

            // Sliders Group (Only in standard/full)
            if density != .compact {
                HStack(spacing: spacing) {
                    sliderGroup(icon: "speedometer", value: $viewModel.speed, range: 5...300, suffix: "px/s", width: density == .full ? 85 : 60)
                    sliderGroup(icon: "textformat.size", value: $viewModel.fontSize, range: 16...140, suffix: "pt", width: density == .full ? 85 : 60)
                    if density == .full {
                        sliderGroup(icon: "circle.lefthalf.filled", value: $viewModel.bgOpacity, range: 0...1, suffix: nil, width: 65)
                    }
                }
            }

            if density == .full {
                Spacer(minLength: 12)
            } else {
                Spacer(minLength: 4).frame(maxWidth: 20)
            }

            // Toggles & Security Group
            HStack(spacing: spacing) {
                // 1. Library
                Button(action: { viewModel.showLibrary.toggle() }) {
                    Image(systemName: "books.vertical")
                        .font(.system(size: iconSize, weight: .medium))
                        .foregroundStyle(viewModel.showLibrary ? viewModel.presentationStyle.accentColor : viewModel.presentationStyle.secondaryTextColor)
                }

                // 2. Always on Top
                Button(action: { viewModel.toggleAlwaysOnTop() }) {
                    Image(systemName: viewModel.alwaysOnTop ? "pin.fill" : "pin")
                        .font(.system(size: iconSize, weight: .medium))
                        .foregroundStyle(viewModel.alwaysOnTop ? viewModel.presentationStyle.accentColor : viewModel.presentationStyle.secondaryTextColor)
                        .opacity(viewModel.isPrivacyMode ? 0.6 : viewModel.presentationStyle.panelOpacityMultiplier)
                }
                .disabled(viewModel.isPrivacyMode)
                .help(viewModel.isPrivacyMode ? "隐私防护模式下强制置顶" : "置顶")

                // 3. Privacy Mode (Stealth + Capture)
                Button(action: { viewModel.togglePrivacy() }) {
                    Image(systemName: viewModel.isPrivacyMode ? "shield.fill" : "shield")
                        .font(.system(size: iconSize, weight: .medium))
                        .foregroundStyle(viewModel.isPrivacyMode ? viewModel.presentationStyle.accentColor : viewModel.presentationStyle.secondaryTextColor)
                }
                .help("隐私防护 (隐藏图标+录屏防护)")

                if density == .full {
                    Group {
                        Button(action: { viewModel.toggleMirrorH() }) {
                            Image(systemName: "arrow.left.and.right.square")
                                .font(.system(size: iconSize))
                                .foregroundStyle(viewModel.mirroredHorizontal ? viewModel.presentationStyle.accentColor : viewModel.presentationStyle.secondaryTextColor)
                        }
                        Button(action: { viewModel.toggleMirrorV() }) {
                            Image(systemName: "arrow.up.and.down.square")
                                .font(.system(size: iconSize))
                                .foregroundStyle(viewModel.mirroredVertical ? viewModel.presentationStyle.accentColor : viewModel.presentationStyle.secondaryTextColor)
                        }
                        Button(action: { viewModel.showAIPromptBar.toggle() }) {
                            Image(systemName: "sparkles")
                                .font(.system(size: iconSize))
                                .foregroundStyle(viewModel.isAIStreaming ? viewModel.presentationStyle.accentColor : viewModel.presentationStyle.secondaryTextColor)
                        }
                        Button(action: {
                            if !viewModel.isPrivacyMode {
                                viewModel.isEditing = true
                            }
                        }) {
                            Image(systemName: "pencil")
                                .font(.system(size: iconSize))
                                .foregroundStyle(viewModel.isPrivacyMode ? viewModel.presentationStyle.secondaryTextColor.opacity(0.3) : viewModel.presentationStyle.secondaryTextColor)
                        }
                        .disabled(viewModel.isPrivacyMode)
                        Button(action: viewModel.pasteFromClipboard) { Image(systemName: "doc.on.clipboard").font(.system(size: iconSize)).foregroundStyle(viewModel.presentationStyle.secondaryTextColor) }
                    }
                    Divider().frame(height: 16).background(Color.white.opacity(viewModel.presentationStyle.dividerOpacity))
                }

                // Core Utilities
                Button(action: { viewModel.showSettings.toggle() }) {
                    Image(systemName: "gearshape")
                        .font(.system(size: iconSize, weight: .medium))
                        .foregroundStyle(viewModel.showSettings ? viewModel.presentationStyle.accentColor : viewModel.presentationStyle.secondaryTextColor)
                }

                if density == .full {
                    Button(action: viewModel.showHelp) {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: iconSize))
                            .foregroundColor(viewModel.presentationStyle.secondaryTextColor.opacity(0.6))
                    }
                }

                Button(action: { if !viewModel.isPrivacyMode { viewModel.showControls = false } }) {
                    Image(systemName: "arrow.down.to.line")
                        .font(.system(size: iconSize))
                        .foregroundColor(viewModel.presentationStyle.secondaryTextColor.opacity(0.4))
                }
            }
        }
    }

    private func sliderGroup(icon: String, value: Binding<Double>, range: ClosedRange<Double>, suffix: String?, width: CGFloat) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 12)).foregroundStyle(viewModel.presentationStyle.secondaryTextColor.opacity(0.6))
            Slider(value: value, in: range)
                .frame(width: width)
                .tint(viewModel.presentationStyle.accentColor)
            if let suffix {
                Text("\(Int(value.wrappedValue)) \(suffix)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(viewModel.presentationStyle.secondaryTextColor.opacity(0.8))
                    .frame(width: 52, alignment: .trailing)
            } else {
                Text("\(Int(value.wrappedValue * 100))%")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(viewModel.presentationStyle.secondaryTextColor.opacity(0.8))
                    .frame(width: 32, alignment: .trailing)
            }
        }
    }

    private func formatTime(_ seconds: Int) -> String {
        let mins = seconds / 60
        let secs = seconds % 60

        if mins >= 60 {
            let hours = mins / 60
            let remainingMins = mins % 60
            return String(format: "%02d:%02d:%02d", hours, remainingMins, secs)
        } else {
            return String(format: "%02d:%02d", mins, secs)
        }
    }
}

// MARK: - Library Sidebar

private struct LibrarySidebar: View {
    @ObservedObject var viewModel: SparklePromptViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                ZStack {
                    Circle().fill(viewModel.presentationStyle.accentColor.opacity(0.15)).frame(width: 32, height: 32)
                    Image(systemName: "books.vertical.fill")
                        .foregroundStyle(viewModel.presentationStyle.accentColor)
                        .font(.system(size: 14))
                }
                Text("剧本库")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(viewModel.presentationStyle.secondaryTextColor)
                Spacer()

                Button(action: viewModel.refreshCurrentWorkspace) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(viewModel.presentationStyle.accentColor.opacity(0.8))
                }
                .buttonStyle(.borderless)
                .help("刷新当前工作区 (从磁盘同步)")

                Button(action: viewModel.importToLibrary) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(viewModel.presentationStyle.accentColor)
                }
                .buttonStyle(.borderless)
                .help("导入剧本或文件夹")
            }
            .padding(.horizontal, 16)
            .padding(.top, 10) // ✨ Move header up to utilize the top space
            .padding(.bottom, 12)

            // ✨ Search Bar: Utilizing the top space
            HStack {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundColor(viewModel.presentationStyle.secondaryTextColor.opacity(0.4))

                TextField("", text: $viewModel.scriptSearchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundColor(viewModel.presentationStyle.secondaryTextColor)
                    .tint(viewModel.presentationStyle.accentColor)

                if !viewModel.scriptSearchQuery.isEmpty {
                    Button(action: viewModel.clearLibrarySearch) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(viewModel.presentationStyle.secondaryTextColor.opacity(viewModel.presentationStyle.hintOpacity))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.white.opacity(viewModel.presentationStyle.subtleFillOpacity), in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 16)
            .padding(.bottom, 16)

            Divider().background(Color.white.opacity(viewModel.presentationStyle.dividerOpacity))

            if viewModel.isLibraryEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 40))
                        .foregroundColor(viewModel.presentationStyle.secondaryTextColor.opacity(0.2))
                    Text("暂无剧本")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(viewModel.presentationStyle.secondaryTextColor.opacity(0.4))
                    Text("点击 + 或直接拖拽文件/文件夹\n导入到库中")
                        .font(.caption)
                        .foregroundColor(viewModel.presentationStyle.secondaryTextColor.opacity(viewModel.presentationStyle.hintOpacity))
                        .multilineTextAlignment(.center)
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.librarySections) { section in
                            WorkspaceSectionView(
                                section: section,
                                style: viewModel.presentationStyle,
                                textOpacityMultiplier: viewModel.presentationStyle.textOpacityMultiplier,
                                hintOpacity: viewModel.presentationStyle.hintOpacity,
                                refreshingWorkspaceId: viewModel.refreshingWorkspaceId,
                                moveTargets: viewModel.libraryMoveTargets,
                                onToggle: { viewModel.toggleWorkspaceExpansion(at: section.index) },
                                onRefresh: { viewModel.refreshWorkspace(at: section.index) },
                                onRemove: { viewModel.removeWorkspace(at: section.index) },
                                onSelectScript: { scriptIndex in viewModel.switchToScript(at: scriptIndex, in: section.index) },
                                onDeleteScript: { scriptIndex in viewModel.removeScript(at: scriptIndex, in: section.index) },
                                onMoveScript: { scriptIndex, targetIndex in viewModel.moveScript(from: section.index, at: scriptIndex, to: targetIndex) },
                                onExportScript: { scriptIndex in viewModel.exportScript(at: scriptIndex, in: section.index) },
                                onRenameScript: { scriptIndex, title in
                                    showRenameAlert(initialTitle: title) { newName in
                                        viewModel.renameScript(at: scriptIndex, in: section.index, to: newName)
                                    }
                                }
                            )
                        }
                    }
                    .padding(.vertical, 12)
                }
            }

            // Footer / Navigation
            if viewModel.activeScriptCount > 0 {
                Divider().background(viewModel.presentationStyle.secondaryTextColor.opacity(viewModel.presentationStyle.dividerOpacity))
                HStack {
                    Button(action: viewModel.prevScript) {
                        Image(systemName: "arrow.up")
                    }
                    .buttonStyle(.borderless)

                    Spacer()
                    Text("\(viewModel.activeScriptIndex + 1) / \(viewModel.activeScriptCount)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(viewModel.presentationStyle.secondaryTextColor.opacity(0.5))
                    Spacer()

                    Button(action: viewModel.nextScript) {
                        Image(systemName: "arrow.down")
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .foregroundStyle(viewModel.presentationStyle.secondaryTextColor.opacity(0.6))
            }
        }
        .opacity(viewModel.presentationStyle.panelOpacityMultiplier)
        .blur(radius: viewModel.presentationStyle.blurRadius)
        .frame(width: SparklePromptViewModel.sidebarWidth)
        .background {
            viewModel.presentationStyle.backgroundColor
                .opacity(viewModel.bgOpacity)
                .ignoresSafeArea()
        }
        .overlay(alignment: .leading) {
            Divider()
                .frame(width: 1)
                .background(viewModel.presentationStyle.secondaryTextColor.opacity(viewModel.presentationStyle.dividerOpacity))
        }
    }
}


private struct WorkspaceSectionView: View {
    let section: LibraryWorkspaceSection
    let style: PromptPresentationStyle
    let textOpacityMultiplier: Double
    let hintOpacity: Double
    let refreshingWorkspaceId: UUID?
    let moveTargets: [LibraryMoveTarget]
    let onToggle: () -> Void
    let onRefresh: () -> Void
    let onRemove: () -> Void
    let onSelectScript: (Int) -> Void
    let onDeleteScript: (Int) -> Void
    let onMoveScript: (Int, Int) -> Void
    let onExportScript: (Int) -> Void
    let onRenameScript: (Int, String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            header
            scripts
        }
    }

    private var header: some View {
        HStack {
            Button(action: onToggle) {
                HStack(spacing: 6) {
                    Image(systemName: (section.isExpanded || section.showsScripts) ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(style.secondaryTextColor.opacity(0.4))
                        .frame(width: 12)

                    Image(systemName: section.isFolderMissing ? "folder.badge.questionmark" : "folder.fill")
                        .font(.system(size: 12))
                        .foregroundColor(
                            section.isFolderMissing ? .orange.opacity(textOpacityMultiplier) :
                                (section.isActive ? style.accentColor : style.secondaryTextColor.opacity(0.5))
                        )

                    Text(section.name)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(section.isActive ? style.secondaryTextColor : style.secondaryTextColor.opacity(0.6))
                        .lineLimit(1)

                    if section.isFolderMissing {
                        Text("路径失效")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(.orange.opacity(0.8 * textOpacityMultiplier))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.15 * textOpacityMultiplier), in: RoundedRectangle(cornerRadius: 3))
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer()

            if section.index != 0 || moveTargets.count > 1 {
                HStack(spacing: 8) {
                    if section.hasFolderURL {
                        Button(action: onRefresh) {
                            Image(systemName: "arrow.clockwise")
                                .foregroundColor(style.secondaryTextColor.opacity(hintOpacity))
                                .font(.system(size: 10))
                                .rotationEffect(.degrees(refreshingWorkspaceId == section.id ? 360 : 0))
                                .animation(
                                    refreshingWorkspaceId == section.id
                                        ? .linear(duration: 0.6).repeatForever(autoreverses: false)
                                        : .default,
                                    value: refreshingWorkspaceId
                                )
                        }
                        .buttonStyle(.plain)
                        .help(section.isFolderMissing ? "⚠️ 文件夹路径失效" : "同步文件夹内容")
                        .disabled(section.isFolderMissing)
                    }

                    Button(action: onRemove) {
                        Image(systemName: "trash")
                            .foregroundColor(style.secondaryTextColor.opacity(0.2))
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                    .help("移除工作区")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var scripts: some View {
        if section.showsScripts {
            if section.isEmpty && section.scripts.isEmpty {
                Text("空工作区")
                    .font(.caption)
                    .foregroundColor(style.secondaryTextColor.opacity(hintOpacity))
                    .padding(.leading, 36)
                    .padding(.vertical, 4)
            } else if !section.scripts.isEmpty {
                VStack(spacing: 2) {
                    ForEach(section.scripts) { script in
                        ScriptRow(
                            script: script,
                            style: style,
                            currentWorkspaceIndex: section.index,
                            moveTargets: moveTargets,
                            onSelect: { onSelectScript(script.originalIndex) },
                            onDelete: { onDeleteScript(script.originalIndex) },
                            onMove: { targetIndex in onMoveScript(script.originalIndex, targetIndex) },
                            onExport: { onExportScript(script.originalIndex) },
                            onRename: { onRenameScript(script.originalIndex, script.title) }
                        )
                    }
                }
                .padding(.leading, 12)
                .padding(.trailing, 8)
            }
        }
    }
}

private struct ScriptRow: View {
    let script: LibraryScriptRowData
    let style: PromptPresentationStyle
    let currentWorkspaceIndex: Int
    let moveTargets: [LibraryMoveTarget]
    let onSelect: () -> Void
    let onDelete: () -> Void
    let onMove: (Int) -> Void
    let onExport: () -> Void
    let onRename: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(script.isAIGenerated ? style.accentColor.opacity(0.2) : style.accentColor.opacity(0.12))
                        .frame(width: 28, height: 28)
                    Image(systemName: script.isAIGenerated ? "sparkles" : "doc.text.fill")
                        .font(.system(size: 11))
                        .foregroundColor(style.accentColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(script.title)
                        .font(.system(size: 13, weight: script.isSelected ? .bold : .medium))
                        .foregroundColor(script.isSelected ? style.secondaryTextColor : style.secondaryTextColor.opacity(0.8))
                        .lineLimit(1)
                    Text("\(script.contentCharacterCount) 字")
                        .font(.system(size: 10))
                        .foregroundColor(style.secondaryTextColor.opacity(0.4))
                }

                Spacer()

                if script.isSelected {
                    Circle().fill(style.accentColor).frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background {
                if script.isSelected {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(style.secondaryTextColor.opacity(style.subtleFillOpacity))
                } else {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(style.secondaryTextColor.opacity(style.subtleFillOpacity * 0.35))
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            // ✨ 重命名
            Button(action: onRename) {
                Label("重命名", systemImage: "pencil")
            }

            Divider()

            // ✨ 移动到其他工作区
            if moveTargets.count > 1 {
                Menu("移动到...") {
                    ForEach(moveTargets) { target in
                        if target.index != currentWorkspaceIndex {
                            Button(action: { onMove(target.index) }) {
                                Label(target.name, systemImage: target.usesFolderIcon ? "folder.fill" : "tray")
                            }
                        }
                    }
                }
            }

            // ✨ 导出为文件
            Button(action: onExport) {
                Label("导出为文件...", systemImage: "square.and.arrow.up")
            }

            Divider()

            Button(role: .destructive, action: onDelete) {
                Label("移除脚本", systemImage: "trash")
            }
        }
    }
}

// MARK: - Editor Overlay

private struct EditorOverlay: View {
    @ObservedObject var viewModel: SparklePromptViewModel
    @FocusState private var editorFocused: Bool

    var body: some View {
        ZStack {
            // Scrim: Respect presentationStyle for premium opacity and stealthiness
            viewModel.presentationStyle.backgroundColor
                .opacity(max(0.7, viewModel.bgOpacity * viewModel.presentationStyle.panelOpacityMultiplier))
                .ignoresSafeArea()

            VStack(spacing: 16) {
                HStack {
                    Text("编辑脚本")
                        .font(.title3.weight(.bold))
                        .foregroundColor(viewModel.presentationStyle.primaryTextColor)
                    Spacer()
                    Button(action: viewModel.pasteFromClipboard) {
                        Label("粘贴", systemImage: "doc.on.clipboard")
                            .foregroundColor(viewModel.presentationStyle.secondaryTextColor)
                    }
                    Button("完成") {
                        viewModel.saveCurrentTextToLibrary()
                        viewModel.isEditing = false
                        viewModel.reset()
                    }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .tint(viewModel.presentationStyle.accentColor)
                }
                .buttonStyle(.plain)

                TextEditor(text: $viewModel.text)
                    .focused($editorFocused)
                    .font(.system(size: 15))
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .background(viewModel.presentationStyle.backgroundColor.opacity(0.5))
                    .foregroundColor(viewModel.presentationStyle.primaryTextColor)
                    .tint(viewModel.presentationStyle.accentColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(viewModel.presentationStyle.panelBorderOpacity), lineWidth: 1)
                    )
                HStack(spacing: 12) {
                    Text("支持 Markdown (**加粗**、*斜体*、# 标题)")
                    Text("⌘↩ 保存并关闭 · ESC 取消")
                }
                .font(.caption)
                .foregroundColor(viewModel.presentationStyle.secondaryTextColor.opacity(viewModel.presentationStyle.hintOpacity))
            }
            .padding(30)
        }
        .onAppear { editorFocused = true }
    }
}

// MARK: - Helpers

@MainActor
private func clickableContextTag(text: String, icon: String, viewModel: SparklePromptViewModel) -> some View {
    HStack(spacing: 4) {
        Image(systemName: icon)
            .font(.system(size: 9))
        Text(text)
            .font(.system(size: 10, weight: .medium))
    }
    .foregroundColor(
        viewModel.isPrivacyMode
            ? viewModel.presentationStyle.secondaryTextColor.opacity(0.4)
            : viewModel.presentationStyle.accentColor
    )
    .padding(.horizontal, 8)
    .padding(.vertical, 3)
    .background(
        viewModel.isPrivacyMode
            ? viewModel.presentationStyle.secondaryTextColor.opacity(0.06)
            : viewModel.presentationStyle.accentColor.opacity(0.12),
        in: Capsule()
    )
    .overlay(
        Capsule().stroke(
            viewModel.isPrivacyMode
                ? Color.clear
                : viewModel.presentationStyle.accentColor.opacity(0.25),
            lineWidth: viewModel.isPrivacyMode ? 0 : 0.5
        )
    )
    .contentShape(Capsule())
    .onTapGesture {
        Task { @MainActor in
            viewModel.useAnyContextForAI = false
        }
    }
    .help("点击清除背景资料")
}

@MainActor
private func clickableNoContextTag(viewModel: SparklePromptViewModel) -> some View {
    HStack(spacing: 4) {
        Image(systemName: "xmark.circle.fill")
            .font(.system(size: 9))
        Text("无背景")
            .font(.system(size: 10, weight: .medium))
    }
    .foregroundColor(
        viewModel.isPrivacyMode
            ? viewModel.presentationStyle.secondaryTextColor.opacity(0.25)
            : viewModel.presentationStyle.secondaryTextColor.opacity(0.4)
    )
    .padding(.horizontal, 8)
    .padding(.vertical, 3)
    .background(
        viewModel.isPrivacyMode
            ? viewModel.presentationStyle.secondaryTextColor.opacity(0.03)
            : Color.white.opacity(0.06),
        in: Capsule()
    )
    .overlay(
        Capsule().stroke(
            viewModel.isPrivacyMode
                ? Color.clear
                : Color.white.opacity(0.12),
            lineWidth: viewModel.isPrivacyMode ? 0 : 0.5
        )
    )
    .contentShape(Capsule())
    .onTapGesture {
        Task { @MainActor in
            viewModel.useAnyContextForAI = true
        }
    }
    .help("点击开启背景资料")
}

@MainActor
private func showRenameAlert(initialTitle: String, completion: @escaping (String) -> Void) {
    let alert = NSAlert()
    alert.messageText = "重命名剧本"
    alert.informativeText = "请输入新的剧本名称："
    alert.addButton(withTitle: "确定")
    alert.addButton(withTitle: "取消")

    let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
    textField.stringValue = initialTitle
    alert.accessoryView = textField

    let response = alert.runModal()
    if response == .alertFirstButtonReturn {
        let newName = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !newName.isEmpty {
            completion(newName)
        }
    }
}
