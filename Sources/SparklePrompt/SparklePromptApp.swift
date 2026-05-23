import SwiftUI
import AppKit

@main
struct SparklePromptApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow!
    let viewModel = SparklePromptViewModel()

    /// The canonical width of the main content area (without sidebar).
    /// This is the single source of truth for all window size calculations.
    /// It is ONLY updated:
    ///   1. At initialization
    ///   2. When the user manually drags the window edge (windowDidEndLiveResize)
    /// It is NEVER modified during programmatic sidebar toggle animations.
    private var baseWindowWidth: CGFloat = 620

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Release bundles start as LSUIElement agent apps, so decide the visible
        // app identity before any window can appear.
        NSApp.setActivationPolicy(viewModel.isPrivacyMode ? .accessory : .regular)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let startsPrivate = viewModel.isPrivacyMode

        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        // 优化后的尺寸：620x700
        // 这个尺寸在 16 寸 MBP 上既能显示足够的文字，又不会导致严重的眼球扫视。
        let defaultWidth: CGFloat = 620
        let defaultHeight: CGFloat = 700

        let frame = NSRect(
            x: screen.midX - defaultWidth / 2,
            y: screen.midY - defaultHeight / 2,
            width: defaultWidth,
            height: defaultHeight
        )

        window = SparklePromptWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        (window as? NSPanel)?.becomesKeyOnlyIfNeeded = false
        (window as? NSPanel)?.hidesOnDeactivate = false
        (window as? SparklePromptWindow)?.isStealthMode = startsPrivate

        // 强制禁用窗口状态恢复，确保设置的初始尺寸生效
        window.isRestorable = false
        window.setFrame(frame, display: true)

        window.minSize = NSSize(width: 450, height: 400)
        window.maxSize = NSSize(width: 1000, height: 1200)

        window.title = "SparklePrompt"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isMovableByWindowBackground = true
        window.level = startsPrivate ? .mainMenu : (viewModel.alwaysOnTop ? .floating : .normal)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.sharingType = startsPrivate ? .none : .readOnly
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true

        viewModel.windowController = self

        let root = SparklePromptView(viewModel: viewModel)
        let host = NSHostingView(rootView: root)
        host.frame = window.contentLayoutRect
        host.autoresizingMask = [.width, .height]
        window.contentView = host

        window.delegate = self
        baseWindowWidth = defaultWidth

        // Apply capture/stealth policy before the first visible frame.
        setHideFromCapture(startsPrivate)
        setStealthMode(startsPrivate)

        if startsPrivate {
            window.orderFrontRegardless()
        } else {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func setAlwaysOnTop(_ on: Bool) {
        // 如果处于隐私防护模式，由 setStealthMode 统一管理层级 (.mainMenu)
        if viewModel.isPrivacyMode { return }
        window?.level = on ? .floating : .normal
    }

    func setHideFromCapture(_ hide: Bool) {
        window?.sharingType = hide ? .none : .readOnly
    }

    func setMousePenetration(_ enabled: Bool) {
        window?.ignoresMouseEvents = enabled
    }

    func setStealthMode(_ isStealth: Bool) {
        guard let window = window as? SparklePromptWindow else { return }
        window.isStealthMode = isStealth

        // 1. 提升窗口层级
        window.level = isStealth ? NSWindow.Level.mainMenu : (viewModel.alwaysOnTop ? .floating : .normal)

        // 2. 修改应用激活策略
        NSApp.setActivationPolicy(isStealth ? .accessory : .regular)

        // 退出隐私模式时不强制激活应用和窗口，避免暴露

        // if !isStealth {
        //     NSApp.activate(ignoringOtherApps: true)
        //     window.makeKeyAndOrderFront(self)
        // }
    }

    // MARK: - NSWindowDelegate

    /// Called ONLY when the user finishes manually dragging the window edge.
    /// Does NOT fire during programmatic animations (NSAnimationContext).
    func windowDidEndLiveResize(_ notification: Notification) {
        guard let window = window else { return }
        if viewModel.showLibrary {
            baseWindowWidth = window.frame.width - SparklePromptViewModel.sidebarWidth
        } else {
            baseWindowWidth = window.frame.width
        }
    }

    // MARK: - Sidebar Toggle

    func toggleSidebar(show: Bool) {
        guard let window = window else { return }
        let sidebarWidth = SparklePromptViewModel.sidebarWidth

        // ABSOLUTE target computation from baseWindowWidth.
        // No matter how many times this is called mid-animation,
        // the target is always deterministic:
        //   open  → baseWindowWidth + sidebarWidth
        //   close → baseWindowWidth
        var frame = window.frame
        frame.size.width = show ? baseWindowWidth + sidebarWidth : baseWindowWidth

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.45
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(frame, display: true)
        })
    }
}

final class SparklePromptWindow: NSPanel {
    var isStealthMode: Bool = false

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        // 阻止 ESC 键关闭窗口的默认行为
        if event.keyCode == 53 {
            // 不调用 super，阻止默认关闭行为
            return
        }
        super.keyDown(with: event)
    }
}
