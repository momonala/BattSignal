import AppKit
import SwiftUI

/// Shrinks the menu bar window when its content gets shorter. `MenuBarExtra` grows the window for taller
/// content but never shrinks it, which leaves the content hanging below an empty band.
struct WindowFitsContent: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowShrinkingView { WindowShrinkingView() }
    func updateNSView(_ nsView: WindowShrinkingView, context: Context) {}
}

final class WindowShrinkingView: NSView {
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        DispatchQueue.main.async { [weak self] in self?.shrinkWindow() }
    }

    private func shrinkWindow() {
        guard let window else { return }
        let excess = window.contentRect(forFrameRect: window.frame).height - bounds.height
        guard excess > 0.5 else { return }
        var frame = window.frame
        frame.origin.y += excess
        frame.size.height -= excess
        window.setFrame(frame, display: true)
    }
}
