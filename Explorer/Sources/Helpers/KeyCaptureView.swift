import SwiftUI
import AppKit

/// An NSView that accepts first responder and forwards key events
/// to a handler closure. Used by mosaic/grid views for keyboard input.
/// Does NOT aggressively grab focus — focus is managed by ContentFocusHelper.
struct KeyCaptureView: NSViewRepresentable {
    let onKeyDown: (UInt16) -> Bool

    final class KeyView: NSView {
        var onKeyDown: ((UInt16) -> Bool)?

        override var acceptsFirstResponder: Bool { true }
        override var canBecomeKeyView: Bool { true }

        override func keyDown(with event: NSEvent) {
            if let handler = onKeyDown, handler(event.keyCode) {
                return
            }
            super.keyDown(with: event)
        }
    }

    func makeNSView(context: Context) -> KeyView {
        let view = KeyView()
        view.onKeyDown = onKeyDown
        return view
    }

    func updateNSView(_ nsView: KeyView, context: Context) {
        nsView.onKeyDown = onKeyDown
    }
}
