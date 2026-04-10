import SwiftUI
import AppKit

/// Programmatically moves keyboard focus to a specific NSView in the content area.
/// Used only for mosaic/grid modes where a KeyCaptureView.KeyView needs AppKit
/// first responder status. For list mode, SwiftUI's @FocusState handles focus.
struct ContentFocusHelper: NSViewRepresentable {
    var focusTrigger: Int

    final class HelperView: NSView {
        override var acceptsFirstResponder: Bool { false }
        private var pendingWork: DispatchWorkItem?

        func requestContentFocus() {
            guard self.window != nil else { return }
            pendingWork?.cancel()

            let work = DispatchWorkItem { [weak self] in
                guard let self, let window = self.window else { return }

                // Find KeyCaptureView.KeyView in our subtree
                if let keyView = self.findNearbyKeyView() {
                    if window.firstResponder === keyView { return }
                    window.makeFirstResponder(keyView)
                }
            }
            pendingWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
        }

        private func findNearbyKeyView() -> NSView? {
            var current: NSView? = self.superview
            while let container = current {
                if let keyView = findDescendantKeyView(in: container) {
                    return keyView
                }
                current = container.superview
            }
            return nil
        }

        private func findDescendantKeyView(in view: NSView) -> NSView? {
            let typeName = String(describing: type(of: view))
            if typeName == "KeyView" && view.acceptsFirstResponder {
                return view
            }
            for subview in view.subviews {
                if let found = findDescendantKeyView(in: subview) {
                    return found
                }
            }
            return nil
        }
    }

    func makeNSView(context: Context) -> HelperView {
        HelperView()
    }

    func updateNSView(_ nsView: HelperView, context: Context) {
        if focusTrigger != context.coordinator.lastTrigger {
            context.coordinator.lastTrigger = focusTrigger
            nsView.requestContentFocus()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator {
        var lastTrigger: Int = -1
    }
}
