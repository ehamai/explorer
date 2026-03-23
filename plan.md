# Explorer — Architecture & Application Plan

## Overview
Explorer is a native macOS file browser built with SwiftUI, targeting macOS 14+ (Sonoma). It provides a Finder-like experience with dual-pane split-screen, tabbed browsing, drag-and-drop file operations, favorites, and an inspector panel. Built as a Swift Package Manager executable using swift-tools-version 5.10.

## Project Structure
```
explorer/
├── Package.swift                    # SPM manifest (macOS 14+, swift-testing 0.12+)
├── Package.resolved                 # Dependency lock file  
├── plan.md                          # This file — architectural overview
├── .github/
│   └── copilot-instructions.md      # AI assistant instructions
├── Explorer/
│   ├── Sources/
│   │   ├── ExplorerApp.swift        # @main entry point, window/scene/command setup
│   │   ├── Helpers/
│   │   │   ├── PLAN.md              # Helpers documentation
│   │   │   └── FormatHelpers.swift  # File size, date, kind formatting
│   │   ├── Models/
│   │   │   ├── PLAN.md              # Models documentation
│   │   │   ├── FileItem.swift       # File/directory representation
│   │   │   ├── ViewMode.swift       # List vs icon display mode
│   │   │   ├── SortDescriptor.swift # Sort field/order configuration
│   │   │   ├── TabManager.swift     # BrowserTab + TabManager
│   │   │   └── SplitScreenManager.swift  # PaneState + SplitScreenManager
│   │   ├── Services/
│   │   │   ├── PLAN.md              # Services documentation
│   │   │   ├── FileSystemService.swift   # Actor — file I/O operations
│   │   │   ├── ClipboardManager.swift    # Cut/copy/paste state
│   │   │   ├── DirectoryWatcher.swift    # FS change monitoring
│   │   │   ├── FavoritesManager.swift    # Persistent favorites
│   │   │   └── FileMoveService.swift     # Drag-drop validation + moves
│   │   ├── ViewModels/
│   │   │   ├── PLAN.md              # ViewModels documentation
│   │   │   ├── DirectoryViewModel.swift  # Directory contents + filtering
│   │   │   ├── NavigationViewModel.swift # History + path management
│   │   │   └── SidebarViewModel.swift    # Favorites + volumes + locations
│   │   └── Views/
│   │       ├── PLAN.md              # Views documentation
│   │       ├── MainView.swift       # Root view, split layout, toolbar
│   │       ├── PaneView.swift       # Single pane container
│   │       ├── ContentAreaView.swift # Content switching (list/grid/loading)
│   │       ├── FileListView.swift   # Table-based file display
│   │       ├── IconGridView.swift   # Grid-based file display
│   │       ├── SidebarView.swift    # Navigation sidebar
│   │       ├── StatusBarView.swift  # Item counts + disk space
│   │       ├── PathBarView.swift    # Breadcrumb/editable path
│   │       ├── TabBarView.swift     # Tab management UI
│   │       ├── FileIconView.swift   # Reusable icon component
│   │       └── InspectorView.swift  # File properties panel
│   ├── Resources/
│   │   └── Explorer.entitlements    # Sandbox configuration
│   └── Tests/
│       ├── PLAN.md                  # Test documentation
│       ├── DirectoryViewModelTests.swift
│       ├── FileMoveServiceTests.swift
│       ├── PasteboardCommandTests.swift
│       └── SplitScreenDoubleClickTests.swift
```

## Architecture Pattern: MVVM + Services

The app uses Model-View-ViewModel (MVVM) with a dedicated Services layer:

```
┌─────────────────────────────────────────────────────────────────────┐
│                        ExplorerApp (@main)                          │
│  Creates & owns: SplitScreenManager, SidebarViewModel,             │
│                  ClipboardManager, FavoritesManager                 │
│  Injects via: .environment() modifier                              │
│  Handles: Keyboard shortcuts, menu commands, window configuration  │
└────────────────────────────┬────────────────────────────────────────┘
                             │ environment injection
┌────────────────────────────▼────────────────────────────────────────┐
│                           Views                                     │
│  MainView → PaneView → ContentAreaView → FileListView/IconGridView │
│  SidebarView, PathBarView, TabBarView, StatusBarView, InspectorView│
│  Read state from ViewModels via @Environment                       │
│  Coordinate cross-ViewModel actions (e.g., navigate + load)        │
└──────────┬────────────────────────────────┬─────────────────────────┘
           │ reads/writes                   │ reads/writes
┌──────────▼──────────┐         ┌───────────▼─────────────┐
│     ViewModels      │         │    Model-Layer State     │
│  DirectoryViewModel │         │  SplitScreenManager      │
│  NavigationViewModel│         │  TabManager / BrowserTab │
│  SidebarViewModel   │         │  PaneState               │
└──────────┬──────────┘         └──────────────────────────┘
           │ delegates I/O
┌──────────▼──────────────────────────────────────────────┐
│                       Services                          │
│  FileSystemService (Actor) — file I/O, enumeration      │
│  ClipboardManager — cut/copy/paste state machine        │
│  DirectoryWatcher — FS change monitoring via GCD        │
│  FavoritesManager — JSON persistence + bookmarks        │
│  FileMoveService — drag-drop validation + bulk moves    │
└─────────────────────────────────────────────────────────┘
           │ operates on
┌──────────▼──────────────────────────────────────────────┐
│                        Models                           │
│  FileItem — file/directory representation               │
│  ViewMode — list/icon display mode                      │
│  FileSortDescriptor — sort field + order                │
│  FavoriteItem — bookmarked location with persistence    │
│  SidebarLocation — navigation target in sidebar         │
└─────────────────────────────────────────────────────────┘
```

## State Ownership & Data Flow

### Composition Hierarchy
```
SplitScreenManager (@Observable)
├── leftPane: PaneState (always exists)
│   └── tabManager: TabManager (@Observable)
│       └── tabs: [BrowserTab]
│           ├── navigationVM: NavigationViewModel (@Observable)
│           │   ├── currentURL: URL
│           │   ├── backStack: [URL]
│           │   ├── forwardStack: [URL]
│           │   └── pathComponents: [(name, url)]
│           └── directoryVM: DirectoryViewModel (@Observable, @MainActor)
│               ├── allItems: [FileItem]
│               ├── items: [FileItem] (filtered/sorted)
│               ├── selectedItems: Set<FileItem.ID>
│               ├── sortDescriptor: FileSortDescriptor
│               ├── viewMode: ViewMode
│               ├── searchText: String
│               └── showHidden: Bool
└── rightPane: PaneState? (nil when not in split mode)
    └── (same structure as leftPane)
```

### Environment Object Injection
All major state objects are injected via SwiftUI's `.environment()` at the app level:

| Object | Scope | Purpose |
|--------|-------|---------|
| SplitScreenManager | Global | Split-screen state, pane activation, active tab routing |
| SidebarViewModel | Global | Favorites, system locations, mounted volumes |
| ClipboardManager | Global | Cut/copy/paste state shared across panes |
| FavoritesManager | Global | Persistent favorites storage |
| TabManager | Per-pane | Tab list and active tab for one pane |
| NavigationViewModel | Per-tab | Navigation history for one tab |
| DirectoryViewModel | Per-tab | Directory contents for one tab |

Per-pane/per-tab objects are injected by PaneView as it renders each tab.

## Feature Inventory

### File Browsing
- **List view**: Multi-column table (Name, Date Modified, Size, Kind) with sortable headers
- **Icon view**: Adaptive grid with 100pt minimum icon cells, double-click detection
- **Path bar**: Breadcrumb navigation with editable mode (type path, ~ expansion, validation)
- **Status bar**: Item count, selection count, available disk space

### Navigation
- **Back/Forward**: Browser-style history with URL stacks, symlink resolution
- **Go Up**: Parent directory navigation
- **Sidebar**: Favorites (persistent, reorderable), system locations (Desktop, Documents, Downloads, Home, Applications), mounted volumes (internal/external drives)
- **Breadcrumbs**: Click any path component to navigate; drop files to move

### Tabbed Browsing
- **Multiple tabs per pane**: Each tab has independent navigation and directory state
- **Tab bar**: Click to switch, hover for close button, drag-over auto-switches after 0.5s
- **Keyboard**: Cmd+T new tab, Cmd+W close tab

### Split-Screen (Dual-Pane)
- **Toggle**: Cmd+\ or toolbar button
- **Independent panes**: Each has its own tabs, navigation, and content
- **Active pane**: Visual indicator (gradient border), click to activate
- **Cross-pane operations**: Cut in left → paste in right via shared ClipboardManager

### File Operations
- **Cut/Copy/Paste**: Cmd+X/C/V with dual-mode (text editing vs file operations)
- **Move to Trash**: Cmd+Delete (uses FileManager.trashItem for safe deletion)
- **Rename**: Via context menu, alert dialog
- **New Folder**: Cmd+Shift+N with auto-incrementing names
- **Drag & Drop**: Move files between directories, panes, sidebar, path bar components

### Drag & Drop Detail
- **Drag sources**: File list rows, icon grid cells, sidebar items
- **Drop targets**: Folder rows/cells, content area background, path bar breadcrumbs, sidebar favorites, tab bar tabs
- **Validation**: Prevents self-drops, circular references (parent→child), duplicate drops
- **Visual feedback**: Highlighted border on drop target, blinking animation on tabs

### Inspector Panel
- **Toggle**: Cmd+I or context menu → Properties
- **Shows**: File icon (64pt), name, kind, size (or item count for folders), dates (modified, created), full path (selectable), hidden status, POSIX permissions, owner

### Search
- **Integrated**: Search field in sidebar filters current directory contents
- **Real-time**: Case-insensitive substring matching on file names
- **Scope**: Current directory only (not recursive)

### File System Monitoring
- **DirectoryWatcher**: DispatchSource-based monitoring with 0.3s debounce
- **Auto-reload**: Directory contents refresh automatically on external changes
- **Scope**: Single directory (not recursive), write events only

### Sorting
- **Fields**: Name, Date Modified, Size, Kind
- **Toggle**: Click column header to sort; click again to reverse order
- **Invariant**: Directories always sort before files regardless of sort field
- **Comparison**: Localized case-insensitive for text fields

## Keyboard Shortcuts

| Shortcut | Action | Context |
|----------|--------|---------|
| Cmd+T | New Tab | Always |
| Cmd+W | Close Tab / Window | Close tab if >1, else window |
| Cmd+Shift+N | New Folder | Always |
| Cmd+\ | Toggle Split View | Always |
| Cmd+[ | Go Back | When canGoBack |
| Cmd+] | Go Forward | When canGoForward |
| Cmd+↑ | Enclosing Folder | When not at root |
| Cmd+1 | View as List | Always |
| Cmd+2 | View as Icons | Always |
| Cmd+Shift+. | Toggle Hidden Files | Always |
| Cmd+X | Cut | Text editing or file selection |
| Cmd+C | Copy | Text editing or file selection |
| Cmd+V | Paste | Text editing or file paste |
| Cmd+A | Select All | Text editing or file selection |
| Cmd+Delete | Move to Trash | When selection exists |
| Cmd+I | Properties/Inspector | Always |
| Return | Open Selected | In file list/grid |
| Escape | Cancel Path Edit | In path bar edit mode |

## Entitlements & Sandboxing
- **Sandboxed**: `com.apple.security.app-sandbox = true`
- **User-selected file access**: `com.apple.security.files.user-selected.read-write = true`
- **Bookmark scoping**: `com.apple.security.files.bookmarks.app-scope = true`
- **Strategy**: Minimal entitlements; relies on user-selected file access and security-scoped bookmarks for persistent access to favorites

## Persistence
- **Favorites**: `~/Library/Application Support/Explorer/favorites.json` — JSON-encoded array of FavoriteItem (id, url, name, bookmarkData)
- **Security bookmarks**: Automatically refreshed on load if stale; fallback chain (security-scoped → plain → raw URL)
- **No other persistence**: Sort preferences, view mode, window state are not persisted

## Build & Run
```bash
# Build
swift build

# Run
swift run Explorer
# Or: open .build/debug/Explorer (after build)

# Test
swift test

# Clean
swift package clean
```

**Requirements**: Swift 5.10+, macOS 14+ (Sonoma), Xcode 15.3+ (for swift-testing support)

**Dependencies**: `swift-testing` 0.12+ (test framework only — no runtime dependencies)

## Error Handling Philosophy
- **Silent failures**: Most operations catch errors silently (empty arrays, no-ops)
- **No error UI**: No user-facing error messages for file operation failures
- **Graceful degradation**: Bookmark resolution uses fallback chains
- **Gap**: No error state properties on ViewModels for UI display

## Concurrency Model
- **FileSystemService**: Swift Actor — thread-safe file I/O isolation
- **DirectoryViewModel**: @MainActor — all state mutations on main thread
- **DirectoryWatcher**: GCD DispatchQueue (utility QoS) with main-thread callbacks
- **FavoritesManager**: Synchronous I/O on calling thread
- **FileMoveService**: Synchronous (no async/await)
- **Pattern**: Async operations via Task {} blocks in views; actor isolation for shared file operations

## Sub-Plans
For detailed documentation of each layer, see:
- [`Explorer/Sources/Models/PLAN.md`](Explorer/Sources/Models/PLAN.md) — All model types and relationships
- [`Explorer/Sources/Views/PLAN.md`](Explorer/Sources/Views/PLAN.md) — View hierarchy and interactions
- [`Explorer/Sources/ViewModels/PLAN.md`](Explorer/Sources/ViewModels/PLAN.md) — ViewModel logic and state management
- [`Explorer/Sources/Services/PLAN.md`](Explorer/Sources/Services/PLAN.md) — Service APIs and concurrency
- [`Explorer/Sources/Helpers/PLAN.md`](Explorer/Sources/Helpers/PLAN.md) — Formatting utilities
- [`Explorer/Tests/PLAN.md`](Explorer/Tests/PLAN.md) — Test coverage and patterns
