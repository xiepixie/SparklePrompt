import SwiftUI
import AppKit

struct KeyEventBridge: NSViewRepresentable {
    let viewModel: SparklePromptViewModel

    func makeNSView(context: Context) -> KeyHandlingView {
        let v = KeyHandlingView()
        v.viewModel = viewModel
        return v
    }

    func updateNSView(_ nsView: KeyHandlingView, context: Context) {
        nsView.viewModel = viewModel
    }
}

final class KeyHandlingView: NSView {
    weak var viewModel: SparklePromptViewModel? {
        didSet {
            guard oldValue !== viewModel else { return }
            setupMonitors(viewModel != nil)
        }
    }
    private nonisolated(unsafe) var monitor: Any?
    private nonisolated(unsafe) var scrollMonitor: Any?

    private struct KeySignature: Equatable {
        let keyCode: UInt16
        let modifiers: NSEvent.ModifierFlags
    }

    private struct DispatchGate {
        let signature: KeySignature
        let timestamp: TimeInterval
    }

    private static var lastDispatchGate: DispatchGate?
    private static let shortcutDebounceInterval: TimeInterval = 0.1

    private func isEventInSidebar(_ event: NSEvent) -> Bool {
        guard let window else { return false }
        let width = window.contentView?.bounds.width ?? window.frame.width
        let sidebarStartX = max(0, width - SparklePromptViewModel.sidebarWidth)
        return event.locationInWindow.x >= sidebarStartX
    }

    func setupMonitors(_ active: Bool) {
        // 强制清理旧监听器，防止捕获失效
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        if let m = scrollMonitor { NSEvent.removeMonitor(m); scrollMonitor = nil }

        if active {
            installMonitor()
            installScrollMonitor()
        }
    }

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window = window {
            window.makeFirstResponder(self)
            // Normal mode can claim key focus for local shortcuts; privacy mode must stay non-activating.
            let isStealthWindow = (window as? SparklePromptWindow)?.isStealthMode ?? false
            let isPrivacyMode = viewModel?.isPrivacyMode == true
            if NSApp.isActive && !isStealthWindow && !isPrivacyMode {
                window.makeKeyAndOrderFront(self)
            }
            setupMonitors(viewModel != nil)
        } else {
            setupMonitors(false)
        }
    }

    deinit {
        if let m = monitor { NSEvent.removeMonitor(m) }
        if let m = scrollMonitor { NSEvent.removeMonitor(m) }
    }

    private func installMonitor() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, let vm = self.viewModel else { return event }
            Self.keepCursorVisibleDuringKeyInput()

            // 1. 拦截 ESC (keyCode 53)
            if event.keyCode == 53 {
                guard Self.shouldDispatch(event, isContinuous: false) else { return nil }
                if vm.showSettings { DispatchQueue.main.async { vm.showSettings = false }; return nil }
                if vm.isEditing { DispatchQueue.main.async { vm.isEditing = false }; return nil }
                if vm.showAIPromptBar {
                    DispatchQueue.main.async {
                        vm.showAIPromptBar = false
                        vm.aiPrompt = ""
                    }
                    return nil
                }
                // 没有匹配任何UI关闭条件，也阻止ESC键的默认行为（防止关闭窗口）
                return nil
            }

            // 2. 面板活跃及输入框聚焦判定
            // 优先检查当前是否有文本输入框（如搜索框、AI输入框、文本编辑器等）处于聚焦状态，放行所有普通输入按键
            if let window = self.window, let firstResponder = window.firstResponder {
                let className = String(describing: type(of: firstResponder))
                if className.contains("TextView") || className.contains("TextField") || firstResponder is NSText {
                    let modifiers = event.modifierFlags.intersection([.command, .option, .control])
                    if modifiers.isEmpty {
                        return event
                    }
                }
            }

            if vm.isEditing { return event }
            if vm.showSettings { return event }
            if vm.showAIPromptBar {
                // 如果在 AI 面板中按空格或普通字符，放行
                if (event.keyCode == 49 || (event.keyCode >= 0 && event.keyCode <= 51)) {
                    let modifiers = event.modifierFlags.intersection([.command, .option, .control])
                    if modifiers.isEmpty { return event }
                }
            }

            // 3. 正常模式快捷键分发
            if Self.handle(event: event, viewModel: vm) {
                return nil
            }
            return event
        }
    }

    private static func isContinuousAction(_ action: ShortcutAction) -> Bool {
        switch action {
        case .increaseFontSize, .decreaseFontSize,
             .increaseBgOpacity, .decreaseBgOpacity,
             .increaseTextOpacity, .decreaseTextOpacity:
            return true
        default:
            return false
        }
    }

    private static func handle(event: NSEvent, viewModel vm: SparklePromptViewModel) -> Bool {
        // ✨ 关键优化：只关注核心修饰符，忽略 CapsLock 等系统标志
        let coreModifiers = event.modifierFlags.intersection([.command, .option, .shift, .control])

        for (action, shortcut) in vm.shortcuts {
            if event.keyCode == shortcut.keyCode && shortcut.normalizedModifiers == coreModifiers {
                let isContinuous = isContinuousAction(action)
                guard shouldDispatch(event, isContinuous: isContinuous) else { return true }

                // 🔒 隐私模式下禁用编辑模式快捷键
                if action == .toggleEdit && vm.isPrivacyMode {
                    return true
                }

                DispatchQueue.main.async {
                    print("⌨️ Shortcut triggered: \(action)")
                    switch action {
                    case .playPause: vm.togglePlay()
                    case .reset: vm.reset()
                    case .toggleLibrary: vm.showLibrary.toggle()
                    case .prevScript: vm.prevScript()
                    case .nextScript: vm.nextScript()
                    case .aiPrompt: vm.showAIPromptBar.toggle()
                    case .toggleControls: vm.toggleControls()
                    case .toggleAlwaysOnTop: vm.toggleAlwaysOnTop()
                    case .togglePrivacy: vm.togglePrivacy()
                    case .paste: vm.pasteFromClipboard()
                    case .toggleEdit: vm.isEditing.toggle()
                    case .prevWorkspace: vm.prevWorkspace()
                    case .nextWorkspace: vm.nextWorkspace()
                    case .increaseFontSize: vm.adjustFontSize(2)
                    case .decreaseFontSize: vm.adjustFontSize(-2)
                    case .increaseBgOpacity: vm.adjustBgOpacity(0.05)
                    case .decreaseBgOpacity: vm.adjustBgOpacity(-0.05)
                    case .increaseTextOpacity: vm.adjustOpacity(0.05)
                    case .decreaseTextOpacity: vm.adjustOpacity(-0.05)
                    case .toggleTimer: vm.toggleTimer()
                    case .resetTimer: vm.resetTimer()
                    case .toggleMirrorH: vm.toggleMirrorH()
                    case .toggleMirrorV: vm.toggleMirrorV()
                    }
                }
                return true
            }
        }

        switch event.keyCode {
        case 126: // Up
            guard shouldDispatch(event, isContinuous: true) else { return true }
            DispatchQueue.main.async { vm.adjustSpeed(5) }
            return true
        case 125: // Down
            guard shouldDispatch(event, isContinuous: true) else { return true }
            DispatchQueue.main.async { vm.adjustSpeed(-5) }
            return true
        default:
            return false
        }
    }

    private static func keepCursorVisibleDuringKeyInput() {
        NSCursor.setHiddenUntilMouseMoves(false)
        DispatchQueue.main.async {
            NSCursor.setHiddenUntilMouseMoves(false)
        }
    }

    private static func shouldDispatch(_ event: NSEvent, isContinuous: Bool) -> Bool {
        let signature = KeySignature(
            keyCode: event.keyCode,
            modifiers: event.modifierFlags.intersection([.command, .option, .shift, .control])
        )

        if event.isARepeat {
            if isContinuous {
                return true
            } else {
                lastDispatchGate = DispatchGate(signature: signature, timestamp: event.timestamp)
                return false
            }
        }

        if !isContinuous {
            if let last = lastDispatchGate,
               last.signature == signature,
               event.timestamp - last.timestamp < shortcutDebounceInterval {
                lastDispatchGate = DispatchGate(signature: signature, timestamp: event.timestamp)
                return false
            }
        }

        lastDispatchGate = DispatchGate(signature: signature, timestamp: event.timestamp)
        return true
    }

    private func installScrollMonitor() {
        guard scrollMonitor == nil else { return }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self = self, let vm = self.viewModel else { return event }
            if vm.isEditing || vm.showSettings { return event }

            if vm.showLibrary && self.isEventInSidebar(event) {
                return event
            }

            if event.momentumPhase != [] && event.momentumPhase != .began {
                return event
            }

            let dy = event.scrollingDeltaY
            if dy != 0 {
                let multiplier: CGFloat = event.hasPreciseScrollingDeltas ? 1.5 : 12.0
                DispatchQueue.main.async { vm.handleScrollWheel(deltaY: dy, multiplier: multiplier) }
            }
            return event
        }
    }
}
