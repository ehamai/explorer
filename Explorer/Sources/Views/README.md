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
3. **Double-Click:** NSEvent monitor → `splitManager.resolveDoubleClickTarget()` → navigate (directory) or `NSWorkspace.open` (file)
4. **Path Edit:** PathBarView edit mode → validate path → navigate or show red border (1s)

## Code Duplication Notes

FileListView and IconGridView share nearly identical logic for context menus, rename alerts, drop targets, cut item feedback, and file operations. A shared ViewModifier could reduce this duplication.
