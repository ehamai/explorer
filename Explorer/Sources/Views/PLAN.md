# Views Layer Plan

## Overview
The Views layer implements the entire UI for Explorer using SwiftUI. It consists of 11 view structs organized in a hierarchical composition pattern, plus several subview components. All views read state from the environment (ViewModels and state managers injected by parent views).

## View Hierarchy

```
ExplorerApp (WindowGroup)
└── MainView (Root)
    ├── NavigationSplitView
    │   ├── SidebarView (sidebar column)
    │   │   ├── Search field
    │   │   ├── Favorites section (FavoriteItem rows)
    │   │   ├── Locations section (SidebarLocation rows)
    │   │   ├── Volumes section (SidebarLocation rows)
    │   │   └── "Add Current Folder" button
    │   └── Detail column
    │       ├── [Single Pane] → PaneView(leftPane)
    │       └── [Split Screen] → HSplitView
    │           ├── PaneView(leftPane)
    │           └── PaneView(rightPane)
    └── Toolbar
        ├── Navigation buttons (Back, Forward, Up)
        ├── ViewMode picker (segmented)
        └── Split toggle button

PaneView (per-pane container)
├── TabBarView (shown if tabs.count > 1)
│   └── TabItemView (per tab)
├── Divider
├── PathBarView (breadcrumb or editable text field)
├── Divider (with active pane gradient indicator)
├── ContentAreaView
│   ├── ProgressView (loading state)
│   ├── Empty folder placeholder
│   ├── FileListView (viewMode == .list)
│   │   └── Table rows with FileIconView
│   └── IconGridView (viewMode == .icon)
│       └── IconCell (per item)
├── Divider
├── StatusBarView
└── [InspectorView attached as right panel via .inspector(isPresented:) modifier]
```

## View Details

### MainView (MainView.swift)
**Purpose**: Root view managing split-screen layout and global toolbar.

**Key Responsibilities**:
- Renders NavigationSplitView with SidebarView + detail content
- Switches between single-pane and HSplitView based on splitManager.isSplitScreen
- Installs NSEvent double-click monitor on appear (removed on disappear)
- Provides toolbar with navigation buttons, view mode picker, split toggle

**State**:
- `@Environment(SplitScreenManager.self)` — split-screen state
- `@Environment(ClipboardManager.self)` — clipboard operations
- `@State private var doubleClickMonitor: Any?` — NSEvent monitor reference

**Double-Click Handling**:
- Installs `NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown)` on appear
- Checks click count == 2 and calls `splitManager.resolveDoubleClickTarget()`
- If target is directory → navigates; if file → opens with NSWorkspace

**View Builders**: `detailContent`, `toolbarContent`, `navButtons()`

---

### PaneView (PaneView.swift)
**Purpose**: Container for a single file browser pane (tabs + path + content + status).

**Key Responsibilities**:
- Renders tab bar, path bar, content area, and status bar vertically
- Injects per-tab environment objects (TabManager, NavigationViewModel, DirectoryViewModel)
- Shows active pane indicator (gradient border) in split mode
- Click overlay to activate pane in split mode
- Triggers directory load on URL change via .onChange

**State**:
- `@Environment(SplitScreenManager.self)` — pane management
- `@Environment(ClipboardManager.self)` — clipboard access
- Parameters: `pane: PaneState`, `isActive: Bool`, `isRightPane: Bool`
- Uses `@Bindable` for DirectoryViewModel bindings

**Active Pane Visual**:
- Gradient overlay on divider for active pane
- Semi-transparent dark overlay on inactive pane
- Click anywhere on inactive pane to activate

---

### ContentAreaView (ContentAreaView.swift)
**Purpose**: Conditional container switching between loading, empty, list, and grid states.

**States Displayed**:
1. `isLoading` → ProgressView
2. `items.isEmpty` → "Folder is empty" placeholder
3. `viewMode == .list` → FileListView
4. `viewMode == .icon` → IconGridView

**Drop Handling**: Drop target for the entire content area with visual feedback (rounded rectangle border with accent color).

**Background Context Menu**: Paste, New Folder

**State**:
- `@Environment(DirectoryViewModel.self)`, `@Environment(NavigationViewModel.self)`
- `@Environment(ClipboardManager.self)`, `@Environment(SplitScreenManager.self)`
- `@State private var isDropTarget: Bool`

---

### FileListView (FileListView.swift)
**Purpose**: Table-based multi-column file display.

**Columns**: Name (with icon), Date Modified, Size, Kind

**Key Features**:
- SwiftUI Table with sortable columns
- Multi-selection via `$directoryVM.selectedItems`
- Context menu per row: Open, Cut, Copy, Paste, Copy Path, Rename, Pin to Favorites (folders), Properties, Move to Trash
- Drag source from any row
- Drop target on folder rows (highlights target folder)
- Drop target on background (move to current directory)
- Rename alert dialog
- Return key opens selected items
- Cut items displayed at 0.4 opacity

**State**:
- `@Environment`: DirectoryViewModel, NavigationViewModel, ClipboardManager, FavoritesManager, SplitScreenManager
- `@State`: itemToRename, renameName, showRenameAlert, dropTargetID, isBackgroundDropTarget

---

### IconGridView (IconGridView.swift)
**Purpose**: Grid-based file display with large icons.

**Layout**: LazyVGrid with adaptive columns (100pt minimum, 16pt spacing)

**Key Features**:
- Custom double-click detection (0.4s threshold between clicks)
- Command-key multi-selection toggle
- Same context menu as FileListView
- Same drag/drop, rename, and visual feedback as FileListView

**IconCell Subview**: 64pt icon + 2-line text label, rounded rectangle background for selection/drop state

**State**:
- Same @Environment as FileListView
- `@State`: lastClickItem, lastClickTime (double-click detection), plus same rename/drop states

---

### SidebarView (SidebarView.swift)
**Purpose**: Navigation sidebar with search, favorites, locations, and volumes.

**Sections**:
1. **Search**: Text field bound to `directoryVM.searchText`
2. **Favorites**: Reorderable list of FavoriteItem (drag to reorder, drop to add, context menu to remove)
3. **Locations**: System shortcuts — Desktop, Documents, Downloads, Home, Applications (SF Symbol icons)
4. **Volumes**: Mounted drives (internal/external with appropriate icons)
5. **Add Button**: "Add Current Folder" at bottom

**SidebarRow Subview**: Button with icon + name, hover effect (pointer cursor), highlighted background for active location

**State**:
- `@Environment`: NavigationViewModel, DirectoryViewModel, SidebarViewModel
- Uses `@Bindable` for directoryVM.searchText binding

---

### PathBarView (PathBarView.swift)
**Purpose**: Breadcrumb navigation with editable text mode.

**Two Modes**:
1. **Breadcrumb Mode**: Horizontal scroll of clickable path components with chevron separators and folder icons. Each component is a drop target for file moves.
2. **Edit Mode**: Monospaced text field with path validation. Supports ~ expansion for home directory. Shows red border on invalid path (1s timeout). Escape cancels.

**State**:
- `@Environment`: NavigationViewModel, SplitScreenManager
- `@State`: isEditing, editText, showError, dropTargetURL
- `@FocusState`: textFieldFocused

---

### TabBarView (TabBarView.swift)
**Purpose**: Tab management UI shown when multiple tabs exist.

**TabItemView Subview**:
- Close button (appears on hover, only if multiple tabs)
- Folder icon + tab display name
- Active tab highlighted background
- Drag-over: blinking animation + auto-switch after 0.5s via DispatchWorkItem

**State**: `@Environment(TabManager.self)`, per-item: isHovering, isBlinking, switchWorkItem

---

### StatusBarView (StatusBarView.swift)
**Purpose**: Bottom bar showing counts and disk space.

**Content**: "{N} items" (with plural), "• {N} selected" (if any), available disk space (right-aligned)

**State**: @Environment(DirectoryViewModel, NavigationViewModel) — display-only, no local state

---

### FileIconView (FileIconView.swift)
**Purpose**: Reusable file icon display component.

**Props**: FileItem, CGFloat size. Displays NSImage icon with aspect-fit scaling. No state.

---

### InspectorView (InspectorView.swift)
**Purpose**: Right sidebar panel showing detailed file properties.

**Sections** (when item selected):
- **Header**: 64pt icon, file name (2 lines), kind
- **Information**: Kind, Size (or folder item count), Modified date, Created date, Full path (selectable)
- **Details**: Hidden status, POSIX permissions (octal), Owner

**Empty State**: Magnifying glass icon + "No Selection"

**State**: @Environment(DirectoryViewModel) — reads inspectedItem computed property, folderSize, createdDate, posixPermissions, fileOwner helper methods

---

## State Management Summary

### Environment Objects Used Per View

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


### Local State (@State) Per View

| View | State Variables |
|------|----------------|
| MainView | doubleClickMonitor |
| ContentAreaView | isDropTarget |
| FileListView | itemToRename, renameName, showRenameAlert, dropTargetID, isBackgroundDropTarget |
| IconGridView | itemToRename, renameName, showRenameAlert, lastClickItem, lastClickTime, dropTargetID, isBackgroundDropTarget |
| PathBarView | isEditing, editText, showError, dropTargetURL, @FocusState textFieldFocused |
| TabItemView | isHovering, isBlinking, switchWorkItem |

---

## User Interactions Catalog

### Click/Tap
| View | Interaction | Action |
|------|------------|--------|
| MainView | Navigation buttons | goBack/goForward/goUp |
| MainView | View mode picker | Switch list/icon |
| MainView | Split toggle | splitManager.toggle() |
| FileListView | Table row | Select item |
| IconGridView | Icon cell | Select (single-click), open (double-click) |
| IconGridView | Cmd+click | Toggle multi-selection |
| SidebarView | Sidebar item | Navigate to location |
| SidebarView | "Add Current Folder" | Add to favorites |
| PathBarView | Breadcrumb component | Navigate to path |
| PathBarView | Click area | Enter edit mode |
| TabItemView | Tab | Activate tab |
| TabItemView | Close button | Close tab |
| PaneView | Click overlay | Activate pane (split mode) |

### Drag & Drop
| Source | Target | Action |
|--------|--------|--------|
| FileListView row | Folder row | Move file to folder |
| FileListView row | Content background | Move to current dir |
| FileListView row | PathBar breadcrumb | Move to breadcrumb dir |
| FileListView row | Sidebar favorite | Move to favorite dir |
| IconGridView cell | Folder cell | Move to folder |
| IconGridView cell | Content background | Move to current dir |
| Sidebar item | — | Drag from sidebar |
| Folder (external) | Sidebar favorites | Add to favorites |
| Any file | TabItemView | Auto-switch tab after 0.5s |

### Context Menus
**File/Folder Context Menu** (FileListView, IconGridView):
- Open
- Divider
- Cut / Copy / Paste / Copy Path
- Divider
- Rename…
- Pin to Favorites (folders only)
- Properties (toggle inspector)
- Divider
- Move to Trash

**Background Context Menu** (ContentAreaView):
- Paste
- New Folder

**Sidebar Context Menu**:
- Remove from Favorites

### Keyboard
| Key | View | Action |
|-----|------|--------|
| Return | FileListView, IconGridView | Open selected items |
| Escape | PathBarView | Cancel edit mode |
| Cmd-key held | IconGridView | Multi-select mode |

---

## Navigation Flows

### Flow 1: Breadcrumb Click
```
User clicks breadcrumb in PathBarView
→ navigationVM.navigate(to: url)    (updates history stacks)
→ PaneView.onChange detects currentURL change
→ directoryVM.loadDirectory(url:)   (async load + filter/sort)
→ Views re-render with new items
```

### Flow 2: Sidebar Click
```
User clicks sidebar item
→ navigationVM.navigate(to: url)
→ directoryVM.loadDirectory(url:)
→ Views re-render
```

### Flow 3: File Double-Click
```
MainView NSEvent monitor detects double-click
→ splitManager.resolveDoubleClickTarget()
→ Returns active tab + selected items
→ If directory: navigationVM.navigate(to:) + directoryVM.loadDirectory(url:)
→ If file: NSWorkspace.shared.open(url)
```

### Flow 4: Path Edit
```
User clicks PathBarView → enters edit mode
→ Types path (~ expansion supported)
→ Presses Enter
→ Validates path exists
→ If valid directory: navigate + load
→ If valid file: NSWorkspace.open()
→ If invalid: red border for 1 second
→ Escape: cancel edit mode
```

---

## Visual Feedback Patterns

| Feedback | Trigger | Visual |
|----------|---------|--------|
| Drop target | File dragged over folder | Rounded rectangle accent border |
| Active pane | Pane is active in split mode | Gradient overlay on divider |
| Inactive pane | Pane is inactive | Semi-transparent dark overlay |
| Cut items | Items marked for cut | 0.4 opacity |
| Selected items | Items in selection set | Highlighted background |
| Invalid path | Bad path entered in PathBarView | Red border (1s) |
| Tab drag-over | File held over tab | Blinking animation |
| Hover | Mouse over breadcrumb/button | Pointing hand cursor |

---

## Code Duplication Notes

### Duplicated Patterns Between FileListView and IconGridView
These two views implement nearly identical functionality with different layouts:
- Context menu construction (same items)
- Rename alert dialog state machine
- Drop target tracking logic
- Cut item visual feedback (0.4 opacity)
- File operation methods (openItem, performRename, moveToTrash)
- Return key handling

**Potential refactor**: Extract shared file operations and context menu into a shared ViewModifier or helper.

### No Custom ViewModifiers
The app uses only standard SwiftUI modifiers. No custom ViewModifiers are defined.
