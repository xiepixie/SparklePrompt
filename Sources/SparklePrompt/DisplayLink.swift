import Foundation
import CoreVideo

/// A wrapper for CVDisplayLink to provide a smooth, screen-refresh-synced animation loop on macOS.
///
/// Simplified version: Fires a callback on every screen refresh.
/// Safety: Uses `passRetained` to prevent use-after-free in the CVDisplayLink callback.
final class DisplayLink {
    private var displayLink: CVDisplayLink?
    private let onFrame: (Double) -> Void
    /// Retained reference pointer for safe release in deinit.
    private var retainedSelf: Unmanaged<DisplayLink>?

    init(onFrame: @escaping (Double) -> Void) {
        self.onFrame = onFrame
        
        // Create CVDisplayLink
        var dl: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&dl)
        self.displayLink = dl
        
        guard let displayLink = self.displayLink else { return }
        
        // Retain self so the callback pointer remains valid for the lifetime of CVDisplayLink.
        let retained = Unmanaged.passRetained(self)
        self.retainedSelf = retained
        
        // Set the output callback
        let callback: CVDisplayLinkOutputCallback = { _, inNow, _, _, _, userData in
            let link = Unmanaged<DisplayLink>.fromOpaque(userData!).takeUnretainedValue()
            
            // 获取当前硬件时间点 (秒)
            let seconds = Double(inNow.pointee.videoTime) / Double(inNow.pointee.videoTimeScale)
            
            // Use DispatchQueue.main.async for faster scheduling than Task
            DispatchQueue.main.async {
                link.onFrame(seconds)
            }
            
            return kCVReturnSuccess
        }
        
        CVDisplayLinkSetOutputCallback(displayLink, callback, retained.toOpaque())
    }

    func start() {
        guard let dl = displayLink, !CVDisplayLinkIsRunning(dl) else { return }
        CVDisplayLinkStart(dl)
    }

    func stop() {
        guard let dl = displayLink, CVDisplayLinkIsRunning(dl) else { return }
        CVDisplayLinkStop(dl)
    }

    deinit {
        stop()
        // Release the retained reference to balance the passRetained in init.
        retainedSelf?.release()
    }
}
