# Models Layer

## Overview
The Models layer defines the data structures and state managers that form the backbone of Explorer. It includes pure data models (FileItem, ViewMode, sort descriptors), container types (BrowserTab, PaneState), and observable state managers (TabManager, SplitScreenManager).

## Type Inventory

| Type | Kind | File | Observable | Purpose |
|------|------|------|:---:|---------|
| FileItem | struct | FileItem.swift | — | Single file/directory representation |
| ViewMode | enum | ViewMode.swift | — | List vs icon display mode |
| SortField | enum | SortDescriptor.swift | — | Which attribute to sort by |
| SortOrder | enum | SortDescriptor.swift | — | Ascending vs descending |
| FileSortDescriptor | struct | SortDescriptor.swift | — | Combined sort configuration |
| BrowserTab | struct | TabManager.swift | — | Container pairing navigation + directory VMs |
| TabManager | class | TabManager.swift | ✓ | Manages tabs within a pane |
| PaneState | struct | SplitScreenManager.swift | — | Container pairing pane ID + tab manager |
| SplitScreenManager | class | SplitScreenManager.swift | ✓ | Manages split-screen layout and pane activation |

---

## FileItem (FileItem.swift)

### Purpose
Represents a single file or directory on the filesystem. Used throughout the app as the primary data unit displayed in list/grid views.

### Properties
| Property | Type | Access | Source |
|----------|------|--------|--------|
| url | URL | let | URLResourceValues |
| name | String | let | .nameKey |
| size | Int64 | let | .fileSizeKey |
| dateModified | Date | let | .contentModificationDateKey |
| kind | String | let | UTType or fallback ("Folder"/"Document") |
| isDirectory | Bool | let | .isDirectoryKey |
| isHidden | Bool | let | .isHiddenKey |
| isPackage | Bool | let | .isPackageKey |
| _icon | NSImage? | private var | Icon cache |

### Computed Properties
| Property | Type | Logic |
|----------|------|-------|
| id | URL | Identifiable conformance |
| icon | NSImage | Returns cached `_icon` if set, otherwise loads from NSWorkspace.shared.icon(forFile:) on demand |

### Initializer
```swift
init(
    url: URL, name: String, size: Int64, dateModified: Date, kind: String,
    isDirectory: Bool, isHidden: Bool, isPackage: Bool,
    icon: NSImage? = nil
)
```
All stored properties set directly. `icon` parameter defaults to `nil` — when nil, the `icon` computed property falls back to NSWorkspace lookup.

### Protocol Conformances
- **Identifiable**: id = url
- **Hashable**: hash by url
- **Equatable**: equality by url
- **Comparable**: directories before files, then alphabetical (localized case-insensitive)

### Factory Method
```swift
static func fromURL(_ url: URL) -> FileItem?
```
Queries 7 URLResourceKeys, derives kind from UTType, eagerly loads icon via NSWorkspace. Returns nil on failure.

### Resource Keys Used
```swift
[.nameKey, .fileSizeKey, .contentModificationDateKey,
 .typeIdentifierKey, .isDirectoryKey, .isHiddenKey, .isPackageKey]
```

---

## ViewMode (ViewMode.swift)

### Purpose
Enum toggling between list and icon display modes.

### Cases
| Case | systemImage | label |
|------|-------------|-------|
| .list | "list.bullet" | "List" |
| .icon | "square.grid.2x2" | "Icons" |

### Conformances
String raw value, CaseIterable, Identifiable (by rawValue)

---

## Sort System (SortDescriptor.swift)

### SortField
| Case | label |
|------|-------|
| .name | "Name" |
| .dateModified | "Date Modified" |
| .size | "Size" |
| .kind | "Kind" |

Conformances: String raw value, CaseIterable, Identifiable, Codable

### SortOrder
| Case | label | toggled |
|------|-------|---------|
| .ascending | "Ascending" | .descending |
| .descending | "Descending" | .ascending |

Conformances: String raw value, CaseIterable, Identifiable, Codable

### FileSortDescriptor
```swift
struct FileSortDescriptor: Equatable, Codable {
    var field: SortField = .name
    var order: SortOrder = .ascending
    
    func compare(_ lhs: FileItem, _ rhs: FileItem) -> Bool
}
```

**Comparison Logic:**
1. Directories always sort before files
2. Within same type, compare by field:
   - `.name`/`.kind`: localizedCaseInsensitiveCompare
   - `.size`: numeric comparison
   - `.dateModified`: Date.compare()
3. Apply ascending/descending order

---

## BrowserTab (TabManager.swift)

### Purpose
Container struct pairing a NavigationViewModel and DirectoryViewModel for one tab. Each tab has independent navigation history and directory state.

### Properties
| Property | Type | Purpose |
|----------|------|---------|
| id | UUID | Unique tab identifier |
| navigationVM | NavigationViewModel | Navigation history for this tab |
| directoryVM | DirectoryViewModel | Directory contents for this tab |

### Computed Properties
- `displayName: String` — last path component of current URL

### Initialization
Creates fresh ViewModels with optional starting URL (defaults to home directory).

Conformances: Identifiable

---

## TabManager (TabManager.swift)

### Purpose
Observable class managing an array of BrowserTabs within a single pane. Ensures at least one tab always exists.

### Properties
| Property | Type | Purpose |
|----------|------|---------|
| tabs | [BrowserTab] | All open tabs |
| activeTabID | UUID | Currently active tab |

### Computed Properties
- `activeTab: BrowserTab?` — first tab matching activeTabID

### Methods
| Method | Behavior |
|--------|----------|
| addTab(url: URL?) | Creates new tab, activates it, triggers async directory load |
| closeTab(id: UUID) | Removes tab (guards against closing last tab), updates activeTabID |
| closeActiveTab() | Convenience wrapper for closeTab |
| reloadTabs(showing url: URL) | Reloads all tabs displaying the specified URL |

### Invariants
- tabs.count >= 1 (closing last tab is prevented)
- activeTabID always references a valid tab

Conformances: @Observable

---

## PaneState (SplitScreenManager.swift)

### Purpose
Lightweight container representing one side of the split-screen layout.

### Properties
| Property | Type | Purpose |
|----------|------|---------|
| id | UUID | Unique pane identifier |
| tabManager | TabManager | Manages tabs within this pane |

Conformances: Identifiable

---

## SplitScreenManager (SplitScreenManager.swift)

### Purpose
Observable class managing single/split-screen layout. Owns the pane hierarchy and tracks which pane is active.

### Properties
| Property | Type | Purpose |
|----------|------|---------|
| isSplitScreen | Bool | Whether split mode is active |
| leftPane | PaneState | Left pane (always exists) |
| rightPane | PaneState? | Right pane (nil when not split) |
| activePaneID | UUID | Currently active pane |

### Computed Properties
- `activePane: PaneState` — returns rightPane if active and exists, else leftPane
- `activeTabManager: TabManager` — shortcut to active pane's TabManager

### Methods
| Method | Behavior |
|--------|----------|
| toggle() | Enables/disables split mode; creates/destroys right pane |
| activate(pane:) | Sets pane as active |
| isActive(_:) -> Bool | Checks if pane is currently active |
| @MainActor resolveDoubleClickTarget() | Returns active tab + selected items for double-click |
| reloadAllPanes(showing:) async | Reloads matching tabs across both panes |

### State Transitions
```
                 toggle()                    toggle()
  ┌────────────────────────────┐  ┌────────────────────────────┐
  │                            ▼  │                            ▼
┌─┴──────────────────┐     ┌──┴──────────────────┐
│  SINGLE PANE MODE  │     │   SPLIT PANE MODE   │
│                    │     │                      │
│  leftPane: active  │     │  leftPane: exists    │
│  rightPane: nil    │     │  rightPane: created  │
│                    │     │  activePaneID: right  │
└────────────────────┘     └──────────────────────┘
```

Conformances: @Observable

---

## Composition Hierarchy

```
SplitScreenManager (@Observable)
├── leftPane: PaneState
│   └── tabManager: TabManager (@Observable)
│       └── tabs: [BrowserTab]
│           ├── navigationVM: NavigationViewModel
│           └── directoryVM: DirectoryViewModel
└── rightPane: PaneState? (split mode only)
    └── tabManager: TabManager (@Observable)
        └── tabs: [BrowserTab]
            ├── navigationVM: NavigationViewModel
            └── directoryVM: DirectoryViewModel
```

## Design Patterns

| Pattern | Where | Why |
|---------|-------|-----|
| Factory | FileItem.fromURL() | Safe creation with error handling |
| Observable | TabManager, SplitScreenManager | SwiftUI automatic view invalidation |
| Container | BrowserTab, PaneState | Pair related objects with clear ownership |
| Value Object | FileItem, FavoriteItem | Identity by URL, immutable semantics |
| State Machine | SplitScreenManager.toggle() | Controlled state transitions with side effects |
| Eager Icon Loading | FileItem.fromURL() | Loads icon during factory creation; fallback on-demand via NSWorkspace |
| Descriptor | FileSortDescriptor | Encapsulate reusable sort configuration |

## Serialization

| Type | Codable | Persisted |
|------|:---:|:---:|
| FileItem | ✗ | ✗ |
| ViewMode | ✗ | ✗ |
| SortField | ✓ | ✗ (could be) |
| SortOrder | ✓ | ✗ (could be) |
| FileSortDescriptor | ✓ | ✗ (could be) |
| BrowserTab | ✗ | ✗ |
| TabManager | ✗ | ✗ |
| PaneState | ✗ | ✗ |
| SplitScreenManager | ✗ | ✗ |
