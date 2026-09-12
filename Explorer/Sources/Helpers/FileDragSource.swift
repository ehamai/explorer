import SwiftUI
import AppKit

/// Transparent overlay that makes a SwiftUI cell a native AppKit drag source.
/// Starts an NSDraggingSession with one NSDraggingItem per URL, so AppKit stacks
/// the drag images and draws a count badge (like Finder and NSTableView).
/// Because it receives left-mouse input for the cell, it also reports mouse-down
/// and click events. Right/control-clicks, scrolls, and gestures pass through.
struct FileDragSource: NSViewRepresentable {
    let urlsToDrag: () -> [URL]
    let dragImage: (URL) -> NSImage
    let onMouseDown: (_ clickCount: Int, _ modifiers: NSEvent.ModifierFlags) -> Void
    let onClick: (_ clickCount: Int, _ modifiers: NSEvent.ModifierFlags) -> Void

    /// Whether a left-mouse event landed on a drag-source cell. SwiftUI tap gestures
    /// on ancestor views still fire for clicks handled by this overlay, so background
    /// tap handlers use this to ignore clicks on cells.
    static func isEventOverDragSource(_ event: NSEvent?) -> Bool {
        guard let event, let contentView = event.window?.contentView else { return false }
        let point = contentView.superview?.convert(event.locationInWindow, from: nil) ?? event.locationInWindow
        return contentView.hitTest(point) is DragSourceView
    }

    final class DragSourceView: NSView, NSDraggingSource {
        var urlsToDrag: (() -> [URL])?
        var dragImage: ((URL) -> NSImage)?
        var onMouseDown: ((Int, NSEvent.ModifierFlags) -> Void)?
        var onClick: ((Int, NSEvent.ModifierFlags) -> Void)?

        private var mouseDownEvent: NSEvent?
        private var didStartDrag = false

        private static let dragThreshold: CGFloat = 3
        private static let maxDragImageSide: CGFloat = 128

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent else { return super.hitTest(point) }
            switch event.type {
            case .leftMouseDown, .leftMouseDragged, .leftMouseUp:
                // Control-click opens the context menu — let SwiftUI handle it
                if event.modifierFlags.contains(.control) { return nil }
                return super.hitTest(point)
            default:
                return nil
            }
        }

        override func mouseDown(with event: NSEvent) {
            mouseDownEvent = event
            didStartDrag = false
            onMouseDown?(event.clickCount, event.modifierFlags)
        }

        override func mouseDragged(with event: NSEvent) {
            guard !didStartDrag, let down = mouseDownEvent else { return }
            let start = down.locationInWindow
            let current = event.locationInWindow
            guard hypot(current.x - start.x, current.y - start.y) >= Self.dragThreshold else { return }
            guard let urls = urlsToDrag?(), !urls.isEmpty else { return }
            didStartDrag = true

            let anchor = convert(start, from: nil)
            let items = urls.map { url -> NSDraggingItem in
                // Provide file-url data eagerly — a lazily-provided writer (NSURL) makes
                // in-app SwiftUI drop targets wait seconds for the data.
                let pasteboardItem = NSPasteboardItem()
                pasteboardItem.setString(url.absoluteString, forType: .fileURL)
                let item = NSDraggingItem(pasteboardWriter: pasteboardItem)
                let image = dragImage?(url) ?? NSWorkspace.shared.icon(forFile: url.path)
                item.setDraggingFrame(dragFrame(for: image, centeredAt: anchor), contents: image)
                return item
            }
            let session = beginDraggingSession(with: items, event: event, source: self)
            session.draggingFormation = .stack
            session.animatesToStartingPositionsOnCancelOrFail = true
        }

        override func mouseUp(with event: NSEvent) {
            defer { mouseDownEvent = nil }
            guard mouseDownEvent != nil, !didStartDrag else { return }
            onClick?(event.clickCount, event.modifierFlags)
        }

        /// Aspect-fit the image into the cell (capped) and center it under the cursor.
        private func dragFrame(for image: NSImage, centeredAt anchor: NSPoint) -> NSRect {
            let maxSide = min(Self.maxDragImageSide, max(bounds.width, bounds.height))
            let size = image.size
            let scale = (size.width > 0 && size.height > 0)
                ? min(maxSide / size.width, maxSide / size.height)
                : 1
            let width = size.width * scale
            let height = size.height * scale
            return NSRect(x: anchor.x - width / 2, y: anchor.y - height / 2, width: width, height: height)
        }

        // MARK: - NSDraggingSource

        func draggingSession(
            _ session: NSDraggingSession,
            sourceOperationMaskFor context: NSDraggingContext
        ) -> NSDragOperation {
            // In-app drop targets perform moves themselves; other apps (e.g. Finder) copy
            context == .withinApplication ? [.copy, .move, .generic] : .copy
        }
    }

    func makeNSView(context: Context) -> DragSourceView {
        let view = DragSourceView()
        update(view)
        return view
    }

    func updateNSView(_ nsView: DragSourceView, context: Context) {
        update(nsView)
    }

    private func update(_ view: DragSourceView) {
        view.urlsToDrag = urlsToDrag
        view.dragImage = dragImage
        view.onMouseDown = onMouseDown
        view.onClick = onClick
    }
}
