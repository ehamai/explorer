# Content Views

Views that display directory contents in list or grid format.

## ContentAreaView (ContentAreaView.swift)

Conditional container switching between display states:
1. `isLoading` → ProgressView
2. `items.isEmpty` → "Folder is empty" placeholder
3. `viewMode == .list` → FileListView
4. `viewMode == .icon` → IconGridView

```
State Machine:
                    ┌──────────────┐
                    │  isLoading?  │
                    └──────┬───────┘
                      yes/ \no
                      /     \
              ┌──────▼──┐  ┌▼────────────┐
              │ Progress │  │items.isEmpty?│
              │  View    │  └──────┬──────┘
              └─────────┘    yes/ \no
                             /     \
                  ┌─────────▼┐  ┌──▼──────────┐
                  │ "Folder  │  │  viewMode?   │
                  │ is empty"│  └──────┬───────┘
                  └──────────┘   .list/ \.icon
                                 /       \
                       ┌────────▼┐  ┌─────▼──────┐
                       │FileList │  │ IconGrid    │
                       │View     │  │ View        │
                       └─────────┘  └─────────────┘
```

**Drop Handling:** Drop target for entire content area with visual feedback (rounded rectangle accent border).
**Background Context Menu:** Paste, New Folder.

**Environment:** `DirectoryViewModel`, `NavigationViewModel`, `ClipboardManager`, `SplitScreenManager`
**Local State:** `isDropTarget: Bool`

## FileListView (FileListView.swift)

Table-based multi-column file display.

```
┌──────────────────────────────────────────────────────────┐
│  Name ▲           │ Date Modified  │   Size  │ Kind      │  ← Sortable headers
├───────────────────┼────────────────┼─────────┼───────────┤
│ 📁 Documents      │ 2 hours ago    │   --    │ Folder    │
│ 📁 Downloads      │ Yesterday      │   --    │ Folder    │  ← Directories first
│┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┼┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┼┄┄┄┄┄┄┄┄┄┼┄┄┄┄┄┄┄┄┄┄┄│
│ 📄 README.md      │ 5 min ago      │  4 KB   │ Markdown  │
│ 📄 Package.swift  │ 1 hour ago     │  1 KB   │ Swift     │  ← Files after
│ 📄 notes.txt      │ Mar 15, 2024   │  340 B  │ Plain Text│
│ ░░ cut-file.txt░░ │ ░░░░░░░░░░░░░░ │ ░░░░░░░ │ ░░░░░░░░░ │  ← Cut items (0.4 opacity)
└───────────────────┴────────────────┴─────────┴───────────┘
```

**Columns:** Name (with icon), Date Modified, Size, Kind — all sortable.

**Key Features:**
- SwiftUI Table with multi-selection via `$directoryVM.selectedItems`
- Context menu per row: Open, Cut, Copy, Paste, Copy Path, Rename, Pin to Favorites (folders), Properties, Move to Trash
- Drag source from any row; drop target on folder rows and background
- Rename alert dialog; Return key opens selected items
- Cut items displayed at 0.4 opacity

**Environment:** `DirectoryViewModel`, `NavigationViewModel`, `ClipboardManager`, `FavoritesManager`, `SplitScreenManager`
**Local State:** `itemToRename`, `renameName`, `showRenameAlert`, `dropTargetID`, `isBackgroundDropTarget`

## IconGridView (IconGridView.swift)

Grid-based file display with large icons.

**Layout:** LazyVGrid with adaptive columns (100pt minimum, 16pt spacing).

**Key Features:**
- Custom double-click detection (0.4s threshold between clicks)
- Command-key multi-selection toggle
- Same context menu, drag/drop, rename, and visual feedback as FileListView

```
┌─────────────────────────────────────────────────────────┐
│                                                         │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌────────┐  │
│  │   📁     │  │   📁     │  │   📄     │  │  📄    │  │
│  │          │  │          │  │          │  │        │  │
│  │  src     │  │  docs    │  │ README   │  │Package │  │
│  │          │  │          │  │ .md      │  │.swift  │  │
│  └──────────┘  └──────────┘  └──[████]──┘  └────────┘  │  ← [████] = selected
│                                                         │
│  ┌──────────┐  ┌──────────┐                             │
│  │   📄     │  │ ░░📄░░░░ │                             │
│  │          │  │ ░░░░░░░░ │                             │
│  │ notes    │  │ ░cut░░░░ │                             │
│  │ .txt     │  │ ░file░░░ │                             │  ← ░░░ = cut item (0.4 opacity)
│  └──────────┘  └──────────┘                             │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

**IconCell Subview:** 64pt icon + 2-line text label, rounded rectangle background for selection/drop state.

**Environment:** Same as FileListView
**Local State:** Same as FileListView + `lastClickItem`, `lastClickTime` (double-click detection)
