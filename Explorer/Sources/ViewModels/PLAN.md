# ViewModels Layer Plan

## Overview
The ViewModels layer contains 3 `@Observable` classes that manage the business logic and state for file browsing. They follow the MVVM pattern — views read their state, services handle I/O, and ViewModels coordinate between them. ViewModels do **not** reference each other directly; views mediate all cross-ViewModel communication.

## Type Inventory

| ViewModel | File | @MainActor | Key State |
|-----------|------|:---:|-----------|
| DirectoryViewModel | DirectoryViewModel.swift | ✓ | File list, filtering, sorting, selection |
| NavigationViewModel | NavigationViewModel.swift | — | Current URL, back/forward history |
| SidebarViewModel | SidebarViewModel.swift | — | Favorites, volumes, system locations |

---

## DirectoryViewModel (DirectoryViewModel.swift)

### Purpose
Manages directory contents, filtering, sorting, selection, and search for one browser tab. Acts as the data source for FileListView and IconGridView.

### Class Declaration
```swift
@MainActor @Observable final class DirectoryViewModel
```
- `@MainActor`: All state mutations on main thread (required for UI updates)
- `@Observable`: Modern Swift observation (no @Published needed)
- `final`: Cannot be subclassed

### Properties

| Property | Type | Access | Default | Purpose |
|----------|------|--------|---------|---------|
| items | [FileItem] | private(set) | [] | Filtered + sorted files shown in UI |
| allItems | [FileItem] | private(set) | [] | Unfiltered complete directory contents |
| selectedItems | Set\<FileItem.ID\> | public | [] | Currently selected file IDs |
| sortDescriptor | FileSortDescriptor | public | .name/.ascending | Current sort config (has didSet → applyFilter) |
| viewMode | ViewMode | public | .list | Display mode |
| showHidden | Bool | public | false | Show hidden files (has didSet → applyFilter) |
| isLoading | Bool | public | false | Loading indicator state |
| showInspector | Bool | public | false | Inspector panel visibility |
| loadedURL | URL? | private(set) | nil | Currently loaded directory |
| searchText | String | public | "" | Search filter (has didSet → applyFilter) |

### Computed Properties

| Property | Type | Logic |
|----------|------|-------|
| itemCount | Int | items.count |
| selectedCount | Int | selectedItems.count |
| selectedURLs | [URL] | Maps selected IDs → URLs via allItems lookup |
| inspectedItem | FileItem? | First item matching selectedItems |

### Dependencies
```swift
private let fileSystemService: FileSystemService  // Actor for file I/O
private let watcher: DirectoryWatcher              // FS change monitoring
```

### Initialization
```swift
nonisolated init(fileSystemService: FileSystemService = FileSystemService(),
                 watcher: DirectoryWatcher = DirectoryWatcher())
```
- `nonisolated`: Avoids @MainActor requirement in init
- Dependency injection with defaults (enables testing with custom watcher/service)
- Both `fileSystemService` and `watcher` are injectable for test isolation
- Sets up watcher callback: `watcher.onChange → Task { reloadCurrentDirectory() }`
- `[weak self]` prevents retain cycles

### Core Methods

#### loadDirectory(url: URL) async
Loads directory contents from disk.
1. Set `isLoading = true`, clear `selectedItems`
2. Call `fileSystemService.fullEnumerate(url:, showHidden: true)` — loads ALL items
3. Store in `allItems`
4. Call `applyFilter()` to derive `items`
5. Start watching directory with `watcher.watch(url:)`
6. Set `isLoading = false`, update `loadedURL`

**Error handling**: Catches silently, clears both arrays. No error state exposed.

#### reloadCurrentDirectory() async
Refreshes directory without losing selection state.
- Preserves: current selection, sort order, search text
- Used by: DirectoryWatcher callback when external changes detected

#### sort(by descriptor: FileSortDescriptor)
Direct sort — sets sortDescriptor, triggers applyFilter via didSet.

#### sort(by field: SortField)
Smart sort — if already sorting by field, toggles direction; otherwise sets ascending.

#### toggleHidden()
Toggles showHidden flag, triggers applyFilter via didSet.

#### applyFilter() (private)
**Core filtering pipeline:**
```
allItems
  → filter: exclude hidden (unless showHidden)
  → filter: case-insensitive name substring match (if searchText non-empty)
  → sort: FileSortDescriptor.compare() (directories first, then by field/order)
  → assign to items
```
Triggered automatically by didSet observers on: sortDescriptor, showHidden, searchText.

#### selectAll() / clearSelection()
Select all visible items / clear selection set.

### Reactive State Flow
```
User changes searchText
  → didSet fires
  → applyFilter() called
  → items re-derived from allItems
  → @Observable triggers view re-render
```

---

## NavigationViewModel (NavigationViewModel.swift)

### Purpose
Manages browser-like navigation with back/forward history stacks and breadcrumb generation.

### Class Declaration
```swift
@Observable final class NavigationViewModel
```
No @MainActor (URL operations are thread-safe).

### Properties

| Property | Type | Access | Purpose |
|----------|------|--------|---------|
| currentURL | URL | private(set) | Current directory path |
| backStack | [URL] | private(set) | LIFO stack of previous locations |
| forwardStack | [URL] | private(set) | LIFO stack for forward navigation |

### Computed Properties

| Property | Type | Logic |
|----------|------|-------|
| canGoBack | Bool | !backStack.isEmpty |
| canGoForward | Bool | !forwardStack.isEmpty |
| canGoUp | Bool | currentURL.path != "/" |
| pathComponents | [(name: String, url: URL)] | Computed breadcrumb trail from root to current |

### Breadcrumb Generation (pathComponents)
Walks up directory tree collecting components, reverses, adds root:
```
Input:  /Users/ehamai/Documents
Output: [("/", /), ("Users", /Users), ("ehamai", /Users/ehamai), ("Documents", /Users/ehamai/Documents)]
```

### Initialization
```swift
init(startingURL: URL = FileManager.default.homeDirectoryForCurrentUser)
```
Defaults to home directory. Normalizes to standardized file URL.

### Navigation Methods

#### navigate(to url: URL)
**Most complex method** — handles symlink resolution and case normalization.
1. Attempt symlink resolution via `FileManager.destinationOfSymbolicLink`
2. Fallback to `resolvingSymlinksInPath` for case normalization
3. Guard against navigating to current URL (no-op)
4. Push current to backStack, clear forwardStack
5. Update currentURL

**Why symlink resolution**: macOS filesystems are case-insensitive but case-preserving. Without normalization, /Users/Foo and /Users/foo would create duplicate history entries.

#### goBack()
Pop from backStack, push current to forwardStack, update currentURL.
Does NOT call navigate() (avoids re-resolving symlinks).

#### goForward()
Inverse of goBack().

#### goUp()
Navigate to parent directory (via navigate(), so history is updated).

#### navigateToPathComponent(url:)
Navigate to a breadcrumb item. Standardizes URL and delegates to navigate().

---

## SidebarViewModel (SidebarViewModel.swift)

### Purpose
Manages sidebar content: favorites (persistent), system locations (hardcoded), and mounted volumes (scanned).

### Class Declaration
```swift
@Observable final class SidebarViewModel
```

### SidebarLocation Model (defined in same file)
```swift
struct SidebarLocation: Identifiable {
    let id: URL
    let name: String
    let url: URL
    let icon: String  // SF Symbol name
}
```

### Properties

| Property | Type | Access | Purpose |
|----------|------|--------|---------|
| favorites | [FavoriteItem] | private(set) | User's bookmarked folders |
| volumes | [SidebarLocation] | private(set) | Mounted drives |

### Computed Properties
```swift
var systemLocations: [SidebarLocation] {
    // Hardcoded quick links:
    // Desktop (desktopcomputer), Documents (doc.fill), Downloads (arrow.down.circle.fill),
    // Home (house.fill), Applications (square.grid.2x2.fill)
}
```

### Dependencies
```swift
private let favoritesManager: FavoritesManager  // Persistence layer
```

### Initialization
```swift
init(favoritesManager: FavoritesManager = FavoritesManager())
```
- Loads favorites from disk via syncFavorites()
- Scans volumes via refreshVolumes()
- Dependency injection for testing

### Methods

#### addFavorite(url: URL)
Delegates to FavoritesManager.addFavorite(), then syncs.

#### removeFavorite(id: UUID)
Delegates to FavoritesManager.removeFavorite(), then syncs.

#### moveFavorite(from: IndexSet, to: Int)
Drag-and-drop reordering. Delegates + syncs.

#### syncFavorites() (private)
One-way sync: `favorites = favoritesManager.favorites`

#### refreshVolumes()
Scans `/Volumes` directory:
1. Read directory contents
2. Skip root volume symlink (deduplicate)
3. Query volumeIsInternal for each volume
4. Assign icon: "internaldrive.fill" or "externaldrive.fill"
5. Sort by localized name

---

## Inter-ViewModel Communication

ViewModels **never reference each other**. Communication is mediated by views:

### Pattern: View-Coordinated Actions
```swift
// In a View (e.g., SidebarView, PaneView):
Button(action: {
    navigationVM.navigate(to: url)           // Update navigation
    Task { await directoryVM.loadDirectory(url: url) }  // Load content
})
```

### Pattern: App-Level Coordination
```swift
// In ExplorerApp commands:
Button("Paste") {
    let url = activeNav.currentURL              // Read from NavigationVM
    let sourceDir = try await clipboard.paste(to: url)  // Execute via service
    await activeDir.loadDirectory(url: url)     // Refresh DirectoryVM
    await splitManager.reloadAllPanes(showing: sourceDir) // Refresh other panes
}
```

### Communication Diagram
```
Views coordinate:
  SidebarView → NavigationVM.navigate() + DirectoryVM.loadDirectory()
  PaneView.onChange → DirectoryVM.loadDirectory() on URL change
  ExplorerApp commands → reads NavigationVM, writes DirectoryVM
  
Services as shared backends:
  DirectoryVM → FileSystemService (file enumeration)
  ClipboardManager → FileSystemService (cut/copy operations)
  SidebarVM → FavoritesManager (persistence)
```

---

## State Management Patterns

### Pattern 1: @Observable Macro
All ViewModels use `@Observable` instead of older `ObservableObject`:
- No `@Published` required — all stored properties automatically tracked
- Views use `@Environment` to access (not `@ObservedObject` or `@StateObject`)
- Compiler-time property tracking for efficient re-renders

### Pattern 2: didSet Observers for Derived State
DirectoryViewModel uses didSet to maintain the invariant: `items = filter(sort(allItems))`:
```swift
var sortDescriptor: FileSortDescriptor = ... { didSet { applyFilter() } }
var showHidden: Bool = false { didSet { applyFilter() } }
var searchText: String = "" { didSet { applyFilter() } }
```

### Pattern 3: private(set) for Controlled Mutation
Properties like `items`, `allItems`, `currentURL`, `backStack`, `forwardStack`, `favorites`, `volumes` use `private(set)` — views can read but only the ViewModel can write.

### Pattern 4: @MainActor for Thread Safety
DirectoryViewModel uses @MainActor to guarantee all state mutations happen on the main thread. This is critical because:
- UI frameworks require main-thread state updates
- Async file operations return on arbitrary threads
- Actor isolation provides compile-time safety

### Pattern 5: Dependency Injection
All ViewModels accept dependencies via init parameters with defaults:
```swift
init(fileSystemService: FileSystemService = FileSystemService(), watcher: DirectoryWatcher = DirectoryWatcher())
init(favoritesManager: FavoritesManager = FavoritesManager())
```
This enables unit testing with real or mock dependencies.

### Pattern 6: Closure-Based Notifications
DirectoryWatcher uses `onChange` closure (with `[weak self]`) rather than Combine publishers or delegation, keeping coupling minimal.

---

## Error Handling

### Current State
| ViewModel | Method | On Error |
|-----------|--------|----------|
| DirectoryViewModel | loadDirectory | Catches silently, clears items arrays |
| DirectoryViewModel | reloadCurrentDirectory | Catches silently |
| NavigationViewModel | navigate | `try?` for symlink resolution, falls back |
| SidebarViewModel | refreshVolumes | Guard with empty array |

### Gap
No ViewModel exposes an error property. UI cannot display file operation failure messages. Silent failures may confuse users (e.g., empty directory shown when permissions denied).

### Recommended Enhancement
```swift
@Observable final class DirectoryViewModel {
    var lastError: Error? = nil  // Add error state
    
    func loadDirectory(url: URL) async {
        do { ... }
        catch { self.lastError = error }  // Expose to UI
    }
}
```
