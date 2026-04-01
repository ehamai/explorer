# Views Layer

## Overview
The Views layer implements Explorer's UI using SwiftUI. Views read state from ViewModels and state managers via `@Environment` injection. They coordinate cross-ViewModel actions (e.g., navigate + load directory).

## Window Layout

```
┌─────────────────────────────────────────────────────────────────────────┐
│  ◀ ▶ ▲   [≡ List ▾]                                    [⫏ Split]      │  ← Toolbar
├────────────┬────────────────────────────┬───────────────────────────────┤
│  🔍 Search │  Tab1 │ Tab2 │ Tab3       │  Tab1 │ Tab2                  │
│            ├────────────────────────────┼───────────────────────────────┤
│ FAVORITES  │  / ▸ Users ▸ me ▸ Docs    │  / ▸ Users ▸ me ▸ Downloads  │  ← PathBarView
│  ★ Desktop │════════════════════════════╪═══════════════════════════════│
│  ★ Docs    │  Name       Date     Size │  Name       Date       Size  │
│  ★ Downloads│ 📁 src    2 hrs ago  --  │  📄 a.zip  Yesterday  12 MB  │  ← Content
│            │ 📁 docs   3 days ago  --  │  📄 b.pdf  Mar 15     1.2 MB │    (FileListView
│ LOCATIONS  │ 📄 README  1 hr ago  4 KB │  📄 c.txt  2 hrs ago  340 B  │     or IconGridView)
│  🖥 Desktop│ 📄 pkg.sw 5 min ago 1 KB │                               │
│  📄 Docs   ├────────────────────────────┼───────────────────────────────┤
│  ⬇ Downlds │  12 items · 2 selected    │  3 items        48.2 GB free │  ← StatusBarView
│  🏠 Home   │         142.5 GB free     │                               │
│            │                            │                               │
│ VOLUMES    │                            │                               │
│  💾 Macint.│                            │                               │
│            │                            │                               │
│ [+ Add]    │                            │                               │
└────────────┴────────────────────────────┴───────────────────────────────┘
               ← Left Pane (active) →      ← Right Pane (inactive) →
```

## View Hierarchy

```
ExplorerApp (WindowGroup)
└── MainView (Root)
    ├── NavigationSplitView
    │   ├── SidebarView (sidebar column)
    │   └── Detail column
    │       ├── [Single Pane] → PaneView(leftPane)
    │       └── [Split Screen] → HSplitView
    │           ├── PaneView(leftPane)
    │           └── PaneView(rightPane)
    └── Toolbar (Back, Forward, Up, ViewMode picker, Split toggle)

ExplorerApp (WindowGroup "mediaViewer")
└── MediaViewerWindow
    ├── ImageViewerView (for images)
    └── VideoViewerView (for videos)

PaneView (per-pane container)
├── TabBarView (if tabs.count > 1)
├── PathBarView (breadcrumb or editable text field)
├── ContentAreaView
│   ├── FileListView (viewMode == .list)
│   └── IconGridView (viewMode == .icon)
├── StatusBarView
└── InspectorView (right panel via .inspector modifier)
```

See subdirectory README.md files for detailed documentation:
- [`Components/README.md`](Components/README.md) — FileIconView, InspectorView
- [`Content/README.md`](Content/README.md) — ContentAreaView, FileListView, IconGridView
- [`Sidebar/README.md`](Sidebar/README.md) — SidebarView
- [`StatusBar/README.md`](StatusBar/README.md) — StatusBarView
- [`Toolbar/README.md`](Toolbar/README.md) — PathBarView, TabBarView

## MainView (MainView.swift)

Root view managing split-screen layout and global toolbar.

**Responsibilities:**
- Renders NavigationSplitView with SidebarView + detail content
- Switches between single-pane and HSplitView based on `splitManager.isSplitScreen`
- Installs NSEvent double-click monitor (click count == 2 → resolve target → navigate or open)
- Provides toolbar with navigation buttons, view mode picker, split toggle

**Environment:** `SplitScreenManager`, `ClipboardManager`
**Local State:** `doubleClickMonitor: Any?`

## MediaViewerWindow (Views/MediaViewer/MediaViewerWindow.swift)

Root view for media viewer windows opened via `openWindow(id: "mediaViewer", value:)`.

**Responsibilities:**
- Creates MediaViewerViewModel from a MediaViewerContext
- Displays images (via ImageViewerView) or videos (via VideoViewerView) with black background
- Handles left/right arrow key navigation between sibling media files
- Shows toolbar with previous/next buttons and "N of M" status
- Sets window title to filename via `.navigationTitle`
- Displays error states and loading indicators
- Cleans up AVPlayer on disappear

**State:** `@State viewModel: MediaViewerViewModel`
**Parameters:** `context: MediaViewerContext`

## ImageViewerView (Views/MediaViewer/ImageViewerView.swift)

Displays an NSImage scaled to fit the window.

**Responsibilities:**
- Renders image with `.resizable().scaledToFit()` — maintains aspect ratio without distortion
- Black background, padding for aesthetics
- Scales automatically with window resize

**Parameters:** `image: NSImage`

## VideoViewerView (Views/MediaViewer/VideoViewerView.swift)

Displays a video using AVKit's VideoPlayer.

**Responsibilities:**
- Wraps `AVKit.VideoPlayer(player:)` for native playback controls
- Auto-plays on appear, pauses on disappear
- Standard macOS controls (play/pause, scrubber, volume, fullscreen)

**Parameters:** `player: AVPlayer`

## PaneView (PaneView.swift)

Container for a single file browser pane (tabs + path + content + status).

**Responsibilities:**
- Renders tab bar, path bar, content area, and status bar vertically
- Injects per-tab environment objects (TabManager, NavigationViewModel, DirectoryViewModel)
- Shows active pane indicator (gradient border) in split mode
- Click overlay to activate pane; triggers directory load on URL change via `.onChange`

**Environment:** `SplitScreenManager`, `ClipboardManager`
**Parameters:** `pane: PaneState`, `isActive: Bool`, `isRightPane: Bool`

## Environment Objects Per View

| View | SplitScreen | Clipboard | Directory | Navigation | TabManager | Favorites | Sidebar |
|------|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| MainView | ✓ | ✓ | — | — | — | — | — |
| PaneView | ✓ | ✓ | ✓ | ✓ | ✓ | — | — |
| ContentAreaView | ✓ | ✓ | ✓ | ✓ | — | — | — |
| FileListView | ✓ | ✓ | ✓ | ✓ | — | ✓ | — |
| IconGridView | ✓ | ✓ | ✓ | ✓ | — | ✓ | — |
| SidebarView | — | — | ✓ | ✓ | — | — | ✓ |
| PathBarView | ✓ | — | — | ✓ | — | — | — |
| TabBarView | — | — | — | — | ✓ | — | — |
| StatusBarView | — | — | ✓ | ✓ | — | — | — |
| InspectorView | — | — | ✓ | — | — | — | — |

## Navigation Flows

1. **Breadcrumb Click:** PathBarView → `navigationVM.navigate(to:)` → PaneView `.onChange` → `directoryVM.loadDirectory(url:)`
2. **Sidebar Click:** SidebarView → `navigationVM.navigate(to:)` → `directoryVM.loadDirectory(url:)`
3. **Double-Click:** NSEvent monitor → `splitManager.resolveDoubleClickTarget()` → navigate (directory), open in media viewer (image/video), or `NSWorkspace.open` (other files)
4. **Media Viewer Navigation:** Arrow keys → `viewModel.goToNext()`/`goToPrevious()` → reload media
4. **Path Edit:** PathBarView edit mode → validate path → navigate or show red border (1s)

## Code Duplication Notes

FileListView and IconGridView share nearly identical logic for context menus, rename alerts, drop targets, cut item feedback, and file operations. A shared ViewModifier could reduce this duplication.
