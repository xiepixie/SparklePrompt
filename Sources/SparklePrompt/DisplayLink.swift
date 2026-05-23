import AppKit
import QuartzCore

/// A wrapper for CADisplayLink to provide a smooth, screen-refresh-synced animation loop on macOS.
///
/// Simplified version: Fires a callback on every screen refresh.
@MainActor
final class DisplayLink {
    @MainActor
    private final class Target: NSObject {
        var onFrame: (@MainActor @Sendable (Double) -> Void)?

        init(onFrame: @MainActor @Sendable @escaping (Double) -> Void) {
            self.onFrame = onFrame
        }

        @objc func frameDidFire(_ displayLink: CADisplayLink) {
            onFrame?(displayLink.timestamp)
        }
    }

    private let target: Target
    private var displayLink: CADisplayLink?

    init(onFrame: @MainActor @Sendable @escaping (Double) -> Void) {
        self.target = Target(onFrame: onFrame)

        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let displayLink = screen.displayLink(target: target, selector: #selector(Target.frameDidFire(_:)))
        displayLink.isPaused = true
        displayLink.add(to: .main, forMode: .common)
        self.displayLink = displayLink
    }

    func start() {
        displayLink?.isPaused = false
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        target.onFrame = nil
    }

    deinit {
        displayLink?.invalidate()
    }
}
