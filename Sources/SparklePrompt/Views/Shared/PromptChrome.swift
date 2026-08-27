import AppKit
import SwiftUI

/// Shared panel background that syncs with the teleprompter's global opacity.
struct PanelBackground: View {
    let bgOpacity: Double
    let style: PromptPresentationStyle
    let usesMaterial: Bool

    var body: some View {
        ZStack {
            style.backgroundColor.opacity(bgOpacity)
            if usesMaterial {
                Rectangle().fill(.ultraThinMaterial)
            }
        }
    }
}

/// Shared panel chrome (clip + border + shadow).
extension View {
    func panelChrome(style: PromptPresentationStyle, cornerRadius: CGFloat = 16) -> some View {
        self
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(style.panelBorderOpacity), lineWidth: 1)
            )
            .shadow(
                color: .black.opacity(style.shadowOpacity),
                radius: style.shadowRadius * 5,
                x: 0,
                y: style.shadowYOffset * 5
            )
    }
}

struct TextViewIntrospector: NSViewRepresentable {
    var configure: (NSTextView) -> Void

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            var parent: NSView? = nsView.superview
            while parent != nil {
                if let scrollView = findScrollView(in: parent!) {
                    if let textView = scrollView.documentView as? NSTextView {
                        configure(textView)
                    }
                    break
                }
                parent = parent?.superview
            }
        }
    }

    private func findScrollView(in view: NSView) -> NSScrollView? {
        if let scrollView = view as? NSScrollView {
            return scrollView
        }
        for subview in view.subviews {
            if let found = findScrollView(in: subview) {
                return found
            }
        }
        return nil
    }
}

// MARK: - Stealth Mouse Cursor Blending

struct StealthCursorView: NSViewRepresentable {
    let isPrivacyMode: Bool

    func makeNSView(context: Context) -> StealthCursorNSView {
        let view = StealthCursorNSView()
        view.isPrivacyMode = isPrivacyMode
        return view
    }

    func updateNSView(_ nsView: StealthCursorNSView, context: Context) {
        nsView.isPrivacyMode = isPrivacyMode
    }
}

final class StealthCursorNSView: NSView {
    var isPrivacyMode: Bool = false {
        didSet {
            guard oldValue != isPrivacyMode else { return }
            updateTrackingAreas()
            window?.invalidateCursorRects(for: self)
        }
    }

    private var trackingArea: NSTrackingArea?

    override var mouseDownCanMoveWindow: Bool {
        true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateTrackingAreas()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let options: NSTrackingArea.Options = [
            .activeAlways,
            .cursorUpdate,
            .inVisibleRect,
            .mouseEnteredAndExited,
            .mouseMoved
        ]
        let newArea = NSTrackingArea(rect: .zero, options: options, owner: self)
        addTrackingArea(newArea)
        trackingArea = newArea
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        if isPrivacyMode {
            addCursorRect(bounds, cursor: .iBeam)
        }
    }

    override func cursorUpdate(with event: NSEvent) {
        if isPrivacyMode {
            NSCursor.iBeam.set()
        } else {
            super.cursorUpdate(with: event)
        }
    }

    override func mouseEntered(with event: NSEvent) {
        if isPrivacyMode {
            NSCursor.iBeam.set()
        }
    }

    override func mouseMoved(with event: NSEvent) {
        if isPrivacyMode {
            NSCursor.iBeam.set()
        }
    }
}
