# MediaViewer Views

## Overview
Views for the built-in media viewer feature. Opens images and videos in separate windows with keyboard navigation between sibling media files in the same directory.

## Views

| View | File | Purpose |
|------|------|---------|
| MediaViewerWindow | MediaViewerWindow.swift | Root view for viewer windows; keyboard nav, toolbar, delete confirmation |
| ImageViewerView | ImageViewerView.swift | Displays NSImage with aspect-fit scaling |
| VideoViewerView | VideoViewerView.swift | Wraps AVKit VideoPlayer with auto-play/pause |
| DeleteConfirmationOverlay | MediaViewerWindow.swift | Custom modal dialog with Tab/Enter/Escape keyboard support |

## Window Lifecycle
```
openWindow(id: "mediaViewer", value: MediaViewerContext)
  → MediaViewerWindow.init(context:)
  → .onAppear: loadMedia() + startListeningForDeletions()
  → .onDisappear: cleanup()
  → .onChange(shouldDismiss): dismiss()
```

## Keyboard Shortcuts
| Key | Action | Blocked during dialog |
|-----|--------|:---:|
| ← | Previous media | ✓ |
| → | Next media | ✓ |
| Escape | Close viewer (or cancel dialog) | ✓ |
| ⌘D | Delete confirmation dialog | — |
| Tab | Switch dialog buttons | — |
| Enter | Confirm selected dialog button | — |
