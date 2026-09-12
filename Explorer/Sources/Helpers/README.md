# Helpers Layer

## Overview
The Helpers layer contains utility functions for formatting file system data, keyboard/focus management for content views, native file dragging, and zoom gesture handling.

## FormatHelpers (FormatHelpers.swift)

### Purpose
Centralized formatting utility providing standardized display formatting for file sizes, dates, and file type descriptions. Used by views (InspectorView, FileListView, StatusBarView) to present file metadata.

### Declaration
```swift
enum FormatHelpers  // Enum with no cases — namespace for static functions
```

### Static Formatters (Cached)
Three formatters are lazily initialized as static properties for reuse across calls:

| Formatter | Type | Configuration |
|-----------|------|---------------|
| byteCountFormatter | ByteCountFormatter | countStyle = .file |
| relativeDateFormatter | RelativeDateTimeFormatter | unitsStyle = .abbreviated |
| absoluteDateFormatter | DateFormatter | dateFormat = "MMM d, yyyy" |

### Functions

#### formatFileSize(_ bytes: Int64) -> String
Formats byte counts into human-readable file sizes using system conventions.
```
Input:  1_536_000
Output: "1.5 MB"
```
Uses ByteCountFormatter with `.file` count style (matches Finder formatting).

#### formatDate(_ date: Date) -> String
Intelligent date formatting with relative/absolute switching:
- **Within 7 days**: Relative format (e.g., "2 hours ago", "3 days ago")
- **Older than 7 days**: Absolute format (e.g., "Mar 15, 2024")

```swift
let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
if date > sevenDaysAgo {
    return relativeDateFormatter.localizedString(for: date, relativeTo: Date())
} else {
    return absoluteDateFormatter.string(from: date)
}
```

#### fileKindDescription(for url: URL) -> String
Returns human-readable file type description with multi-level fallback:

1. **Primary**: Query `typeIdentifierKey` from URL resource values → look up UTType → use `localizedDescription`
2. **Fallback 1**: Query `contentTypeKey` → use `localizedDescription`
3. **Fallback 2**: Derive from file extension via `UTType(filenameExtension:)` → use `localizedDescription`
4. **Fallback 3**: Return "Folder" (if directory) or "Document" (if file)

### Design Patterns

- **Static utility enum**: No instances, all static methods — prevents accidental instantiation
- **Lazy static formatters**: Created once, reused across all calls — avoids formatter allocation overhead
- **Fallback chains**: Multiple strategies for type detection ensure a result is always returned
- **System integration**: Uses Apple's ByteCountFormatter and RelativeDateTimeFormatter for locale-correct formatting

### Usage Locations
- **InspectorView**: File size, modification date, creation date, file kind
- **FileListView**: Date Modified column, Size column
- **StatusBarView**: Available disk space formatting

---

## KeyCaptureView (KeyCaptureView.swift)

### Purpose
NSViewRepresentable wrapping an NSView that accepts first responder and forwards key events to a handler closure. Used by MosaicView for keyboard input handling (arrow keys, Enter, Delete).

### Declaration
```swift
struct KeyCaptureView: NSViewRepresentable
```

### Parameters
| Parameter | Type | Purpose |
|-----------|------|---------|
| onKeyDown | (UInt16) -> Bool | Handler receiving key codes; return true if handled |

### Inner Class: KeyView
- `acceptsFirstResponder: true`
- `canBecomeKeyView: true`
- Forwards `keyDown` events to `onKeyDown` closure

---

## ContentFocusHelper (ContentFocusHelper.swift)

### Purpose
NSViewRepresentable that programmatically moves keyboard focus to the `KeyCaptureView.KeyView` in mosaic/grid modes. Searches the NSView hierarchy to find the target view and makes it first responder. Used as a fallback for view modes where SwiftUI's `@FocusState` alone isn't sufficient.

### Declaration
```swift
struct ContentFocusHelper: NSViewRepresentable
```

### Parameters
| Parameter | Type | Purpose |
|-----------|------|---------|
| focusTrigger | Int | Incremented to trigger a focus request |

### Focus Strategy
1. Walk up from helper view's position in the NSView hierarchy
2. Search each ancestor's subtree for a `KeyView` (from `KeyCaptureView`)
3. Make the found view first responder via `window.makeFirstResponder()`

---

## FileDragSource (FileDragSource.swift)

### Purpose
NSViewRepresentable overlay that makes a SwiftUI cell a native AppKit drag source. SwiftUI's `.onDrag` can only vend a single `NSItemProvider`, so it cannot drag several files at once. FileDragSource starts an `NSDraggingSession` with one `NSDraggingItem` per URL, so AppKit stacks the drag images and draws a count badge, like Finder and `NSTableView`. Used by IconGridView and MosaicView.

### Declaration
```swift
struct FileDragSource: NSViewRepresentable
```

### Parameters
| Parameter | Type | Purpose |
|-----------|------|---------|
| urlsToDrag | () -> [URL] | URLs to drag, evaluated when the drag starts |
| dragImage | (URL) -> NSImage | Drag image per URL (aspect-fit, capped at 128pt, centered under cursor) |
| onMouseDown | (Int, NSEvent.ModifierFlags) -> Void | Left mouse-down with click count and modifiers |
| onClick | (Int, NSEvent.ModifierFlags) -> Void | Left mouse-up when no drag started |

### Inner Class: DragSourceView
- Handles left-mouse events; `hitTest` returns `nil` for right/control-clicks, scrolls, and gestures so SwiftUI context menus, scrolling, and pinch-to-zoom keep working
- Starts the drag after a 3pt threshold; `draggingFormation = .stack`
- Each dragging item is an `NSPasteboardItem` with `.fileURL` data set eagerly (a lazily-provided `NSURL` writer made in-app SwiftUI drops lag by seconds)
- Source operation mask: copy/move/generic within the app (drop targets perform the move), copy outside the app
- `acceptsFirstMouse: true`

### isEventOverDragSource(_:)
Static helper that hit-tests the event's window to check whether a click landed on a `DragSourceView`. SwiftUI tap gestures on ancestor views still fire for clicks the overlay handles, so the background tap handlers in IconGridView and MosaicView (which clear the selection) call this and ignore clicks on cells.

---

## PinchToZoomModifier (ScrollWheelZoomModifier.swift)

### Purpose
ViewModifier providing pinch-to-zoom (MagnifyGesture) on the mosaic view.

### Declaration
```swift
struct PinchToZoomModifier: ViewModifier
```

### Parameters
| Parameter | Type | Purpose |
|-----------|------|---------|
| zoom | Binding<CGFloat> | Current zoom level |
| range | ClosedRange<CGFloat> | Min/max zoom bounds |

### Extension
```swift
extension View {
    func pinchToZoom(_ zoom: Binding<CGFloat>, range: ClosedRange<CGFloat>) -> some View
}
```

Uses `.interactiveSpring` animation during gesture and `.easeInOut` on completion.
