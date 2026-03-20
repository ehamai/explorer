# Split-Screen File Explorer Plan

## Problem
Add a dual-pane split-screen mode so users can view two file explorers side by side within the same window. This is a classic "commander-style" feature (like Total Commander, Midnight Commander) that makes file operations between two locations much easier.

## Approach
Each side of the split is a **pane** that has its own `TabManager` (and therefore its own tabs, navigation, and directory state). The existing `MainView` content becomes a reusable `PaneView` that is rendered once (single-pane mode) or twice (split-screen mode) inside an `HSplitView`. A new `SplitScreenManager` tracks which pane is active and whether split mode is on.

## ASCII Mockup

### Single Pane (default, current behavior):
```
┌──────────────────────────────────────────────────────────────────────────────┐
│ ● ● ●   [◀][▶][↑]  │  🏠 > Users > ehamai > Documents    │ [≡⊞⫏] [⫿] 🔍 │
├─────────────┬────────────────────────────────────────────────────────────────┤
│  FAVORITES  │  Name              Date Modified     Size       Kind          │
│  📁 Work    │  📁 Projects      Dec 1, 2024       --         Folder        │
│  📁 Music   │  📄 readme.md     Dec 10, 2024      4 KB       Markdown      │
│  📁 dev     │  📄 report.pdf    Dec 9, 2024       2.1 MB     PDF           │
│             │                                                               │
│  LOCATIONS  │                                                               │
│  🖥 Desktop │                                                               │
│  📥 Downlds │                                                               │
├─────────────┴────────────────────────────────────────────────────────────────┤
│  8 items  •  1 selected  •  42.5 GB available                               │
└──────────────────────────────────────────────────────────────────────────────┘
                                                         [⫿] = Split button
```

### Split Screen (after pressing [⫿] or Ctrl+\):
```
┌──────────────────────────────────────────────────────────────────────────────┐
│ ● ● ●   [◀][▶][↑]  │  (active pane path bar)             │ [≡⊞⫏] [⫿] 🔍 │
├─────────┬──────────────────────────────┬─────────────────────────────────────┤
│ SIDEBAR │  LEFT PANE (active)          │  RIGHT PANE                        │
│         │  Tab1 │ Tab2                 │  Tab1                              │
│ FAVS    │ ──────────────────────────── │ ─────────────────────────────────  │
│ 📁 Work │ / > Users > ehamai > Docs   │ / > Users > ehamai > Downloads    │
│ 📁 Music│ ──────────────────────────── │ ─────────────────────────────────  │
│ 📁 dev  │  Name          Size   Kind  │  Name          Size   Kind         │
│         │  📁 Projects   --     Fold  │  📦 app.dmg    45 MB  Disk Image  │
│ LOCS    │  📄 readme.md  4 KB   Mark  │  📄 notes.txt  1 KB   Text        │
│ 🖥 Dsktp│  📄 report.pdf 2.1MB  PDF   │  📄 photo.jpg  3 MB   JPEG        │
│ 📥 Dwnl │  ░░ cut.txt░░  512B   Text  │                                    │
│         │                              │                                    │
│         │  ← active pane border ───→   │                                    │
├─────────┴──────────────────────────────┴─────────────────────────────────────┤
│  LEFT: 4 items • 1 selected          RIGHT: 3 items • 0 selected           │
└──────────────────────────────────────────────────────────────────────────────┘
```

Key visual details:
- Active pane has a subtle blue/accent border or highlight
- Click a pane to make it active
- Sidebar navigation targets the active pane
- Toolbar (back/fwd/up, view mode, search) targets the active pane
- Cut in left pane → paste in right pane works naturally via shared ClipboardManager
- Each pane has its own tabs, path bar, and content area

## Todos

### 1. split-manager — Create SplitScreenManager
- New `@Observable` class with:
  - `isSplitScreen: Bool` (default false)
  - `leftPane: PaneState` / `rightPane: PaneState`
  - `activePaneID: UUID` — which pane is focused
  - `activePane: PaneState` (computed)
  - `toggle()` — activates/deactivates split
- `PaneState` holds a `TabManager` instance per pane
- When split is toggled ON: create a right pane with a new TabManager
- When split is toggled OFF: close the right pane, keep left pane

### 2. pane-view — Extract PaneView from MainView
- Move the detail content (tab bar, path bar, content area, status bar) into a reusable `PaneView`
- PaneView takes a `PaneState` and injects its TabManager + active tab VMs into the environment
- PaneView has a click handler to set itself as the active pane
- Active pane gets a subtle accent border

### 3. main-view-split — Update MainView for split layout
- Single pane: current layout (sidebar + PaneView)
- Split screen: sidebar + HSplitView { PaneView | PaneView }
- The HSplitView uses a draggable divider so panes can be resized

### 4. toolbar-split — Add split toggle button and keyboard shortcut
- Add [⫿] button to toolbar (SF Symbol: `rectangle.split.2x1`)
- Add Ctrl+\ keyboard shortcut in ExplorerApp commands
- Button toggles `splitScreenManager.toggle()`

### 5. active-pane-routing — Route actions to active pane
- Toolbar back/fwd/up targets active pane's NavigationVM
- Menu commands (⌘X/C/V, ⌘1/2/3, etc.) target active pane
- Sidebar clicks navigate the active pane
- Double-click handler opens items in the active pane

### 6. status-bar-split — Update StatusBarView for split mode
- In split mode, show both panes' item counts
- Or: each PaneView has its own StatusBarView (simpler)

## Notes
- ClipboardManager is shared across both panes, so cut-left → paste-right works out of the box
- FavoritesManager and SidebarViewModel are also shared (sidebar is global)
- Each pane has its own TabManager, so tabs are independent per pane
- The existing `reloadTabs(showing:)` needs to check BOTH panes' TabManagers
