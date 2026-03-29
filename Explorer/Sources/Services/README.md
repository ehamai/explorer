# Services Layer

## Overview
The Services layer contains 5 components that handle file system I/O, clipboard state, filesystem monitoring, favorites persistence, and drag-drop validation. The layer uses a mix of concurrency patterns: Swift actors, GCD dispatch sources, and synchronous operations.

## Service Inventory

| Service | Kind | Concurrency | Persistence | Error Strategy |
|---------|------|-------------|-------------|----------------|
| FileSystemService | actor | async/await | None | Throws (caller handles) |
| ClipboardManager | @Observable class | Mixed | In-memory | Throws (propagated) |
| DirectoryWatcher | class | GCD DispatchQueue | None | Silent failure |
| FavoritesManager | @Observable class | Synchronous | JSON file | Graceful degradation |
| FileMoveService | enum (static) | Synchronous | None | Partial success |

## Dependency Graph

```
ExplorerApp
├── ClipboardManager ──uses──→ FileSystemService
├── SplitScreenManager (model layer, uses no services directly)
├── SidebarViewModel ──uses──→ FavoritesManager
└── DirectoryViewModel ──uses──→ FileSystemService
                       ──owns──→ DirectoryWatcher

FileMoveService (stateless, used directly by Views)
```

---

## FileSystemService (FileSystemService.swift)

### Purpose
Actor providing thread-safe file system operations. Primary abstraction over FileManager for all file I/O in the app.

### Declaration
```swift
actor FileSystemService
```
Actor isolation prevents data races. All methods are implicitly actor-isolated.

### Static Optimization
```swift
private static let resourceKeys: [URLResourceKey] = [
    .nameKey, .fileSizeKey, .contentModificationDateKey,
    .typeIdentifierKey, .isDirectoryKey, .isHiddenKey, .isPackageKey
]
private static let resourceKeySet = Set(resourceKeys)
```
Static constants avoid repeated allocation of key sets.

### Public API

#### enumerate(url: URL) -> AsyncStream\<[FileItem]\>
**Streaming directory enumeration** for large directories.
- Yields items in **500-item batches** via AsyncStream
- Executes in `Task.detached` to avoid blocking
- Supports cancellation via `continuation.onTermination`
- Options: `.skipsSubdirectoryDescendants` (shallow) + `.skipsPackageDescendants`
- Pre-allocates batch capacity for memory efficiency

#### fullEnumerate(url: URL, showHidden: Bool) async throws -> [FileItem]
**Complete directory enumeration** — loads all items at once.
- Uses synchronous `contentsOfDirectory(at:)` API
- Respects `showHidden` flag
- Returns complete array (used when full list needed upfront)
- Pre-allocates array capacity

#### moveItems(_ urls: [URL], to destination: URL) async throws
Bulk move operation. Sequential per-item moves using `FileManager.moveItem`.

#### copyItems(_ urls: [URL], to destination: URL) async throws
Bulk copy. Sequential per-item copies using `FileManager.copyItem`.

#### deleteItems(_ urls: [URL]) async throws
Bulk delete. Uses `FileManager.trashItem` (moves to Trash, not permanent delete).

#### renameItem(at url: URL, to newName: String) async throws -> URL
Rename via `FileManager.moveItem`. Returns new URL.

#### createFolder(in directory: URL, name: String) async throws -> URL
Creates new directory. Returns new URL.

#### fileExists(at url: URL) -> Bool
Synchronous existence check.

#### isDirectory(at url: URL) -> Bool
Synchronous directory check.

### Performance Characteristics
- **No caching**: Every call reads from disk
- **Batch streaming**: 500-item batches prevent memory spikes
- **Pre-allocation**: `.reserveCapacity()` on arrays
- **Sequential operations**: Move/copy/delete are sequential (no parallel I/O)
- **Task cancellation**: Streaming enum checks `Task.isCancelled`

---

## ClipboardManager (ClipboardManager.swift)

### Purpose
Tracks cut/copy/paste state for file operations. Shared across panes to enable cross-pane cut-paste workflows.

### Declaration
```swift
@Observable final class ClipboardManager
```

### State Model
```
            cut(urls)              paste(to:)
  ┌──────┐──────────▶┌──────┐──────────────▶┌──────┐
  │ IDLE │           │ CUT  │   move files   │ IDLE │
  │      │◀──────────│      │◀───────────────│      │
  └──┬───┘  clear()  └──────┘                └──────┘
     │
     │ copy(urls)           paste(to:)
     └──────────▶┌──────┐──────────────▶ (stays COPY)
                 │ COPY │   copy files    sourceURLs kept
                 │      │◀──────────────  for re-paste
                 └──────┘
```
```swift
enum ClipboardOperation: Equatable {
    case idle, cut, copy
}
```

### Properties

| Property | Type | Purpose |
|----------|------|---------|
| sourceURLs | [URL] | Files marked for cut/copy |
| operation | ClipboardOperation | Current operation type |
| sourceDirectory | URL? | Directory containing source files |

### Computed Properties
- `hasPendingOperation: Bool` — operation != .idle && !sourceURLs.isEmpty
- `isCut: Bool` — operation == .cut

### Initialization
```swift
init(fileSystemService: FileSystemService = FileSystemService())
```
Dependency injection with default instance.

### Methods

#### cut(urls: [URL])
Stores URLs with `.cut` operation. Posts `clipboardStateChanged` notification.

#### copy(urls: [URL])
Stores URLs with `.copy` operation. Posts notification.

#### paste(to destination: URL) async throws -> URL?
Executes the pending operation:
- `.cut`: Moves files via FileSystemService, clears state, returns source directory (for UI refresh)
- `.copy`: Copies files via FileSystemService, returns nil
- `.idle`: No-op, returns nil

**Atomic capture**: State captured to local vars before async execution (prevents race conditions).

#### clear()
Resets operation to `.idle`, clears sourceURLs. Posts notification.

### Notification
```swift
extension Notification.Name {
    static let clipboardStateChanged = Notification.Name("Explorer.clipboardStateChanged")
}
```
Posted after every state change for non-SwiftUI observers.

### Dependencies
```swift
private let fileSystemService: FileSystemService
```

---

## DirectoryWatcher (DirectoryWatcher.swift)

### Purpose
Monitors a directory for filesystem changes using GCD dispatch sources. Triggers a debounced callback when changes detected.

### Declaration
```swift
class DirectoryWatcher
```
Not an actor or @Observable — simple reference type with manual lifecycle.

### Properties

| Property | Type | Purpose |
|----------|------|---------|
| source | DispatchSourceFileSystemObject? | GCD dispatch source |
| fileDescriptor | Int32 | POSIX file descriptor (O_EVTONLY) |
| debounceWorkItem | DispatchWorkItem? | Pending debounced callback |
| debounceInterval | TimeInterval | 0.3 seconds (hardcoded) |
| queue | DispatchQueue | "com.explorer.directorywatcher", utility QoS |
| onChange | (() -> Void)? | Callback fired on changes |

### Lifecycle

#### watch(url: URL)
1. Stop any existing watch (cleanup)
2. Open file descriptor with `O_EVTONLY` (events-only, no data access)
3. Create DispatchSource monitoring `.write` events
4. Set event handler → calls `handleEvent()` (debounced)
5. Set cancel handler → closes file descriptor
6. Resume source

#### stop()
1. Cancel debounce work item
2. Cancel dispatch source (triggers cancel handler → closes fd)
3. Or close fd directly if no source

#### deinit
Calls `stop()` for cleanup.

### Debounce Strategy
```
FS events:  ──●──●●●──●──────●──●───────────▶ time
                                              
Debounce:   ──[cancel][cancel][0.3s wait]──▶ fire onChange()
                                              
Result:     One callback per burst of changes (0.3s quiet period)
```
Multiple rapid changes (e.g., batch file operations) collapse into a single callback.

### Limitations
- Monitors single directory only (not recursive)
- `.write` events only (no rename/delete detection via event mask — relies on directory write timestamp change)
- No error reporting if `open()` fails
- 0.3s debounce is hardcoded (not configurable)

---

## FavoritesManager (FavoritesManager.swift)

### Purpose
Persists user's favorite directories as JSON with security-scoped bookmarks for sandbox access.

### Declaration
```swift
@Observable final class FavoritesManager
```

### Data Model
```swift
struct FavoriteItem: Identifiable, Codable, Equatable {
    let id: UUID
    let url: URL
    let name: String
    let bookmarkData: Data  // Security-scoped bookmark
}
```

### Storage
```
~/Library/Application Support/Explorer/favorites.json
```
JSON-encoded array of FavoriteItem.

### Properties

| Property | Type | Purpose |
|----------|------|---------|
| favorites | [FavoriteItem] | Observable array of bookmarked locations |

### Methods

#### init(storageDirectory: URL? = nil)
Loads favorites from disk. If empty (first launch), populates defaults: Desktop, Documents, Downloads, Home.
- `storageDirectory`: Optional injectable storage path. When nil (default), uses `~/Library/Application Support/Explorer/`. When provided, uses the given directory — enables test isolation without polluting real favorites.

#### addFavorite(url: URL)
1. Guard against duplicates (by URL)
2. Try creating security-scoped bookmark: `url.bookmarkData(options: [.withSecurityScope])`
3. On failure: fallback to plain bookmark (`options: []`) or empty `Data()` if both fail
4. Create FavoriteItem, append to array, save

#### removeFavorite(id: UUID)
Remove by ID, save.

#### moveFavorite(from: IndexSet, to: Int)
Reorder via IndexSet move, save.

#### loadFavorites()
1. Read JSON from storage path
2. Decode [FavoriteItem]
3. For each item, resolve bookmark:
   a. Try security-scoped resolution → if stale, refresh bookmark
   b. Try non-scoped resolution
   c. Fallback: use stored URL directly
4. compactMap filters out completely unresolvable items

#### saveFavorites()
1. Create storage directory if needed (withIntermediateDirectories)
2. JSON-encode favorites array
3. Write atomically to prevent corruption

### Security Bookmark Flow
```
addFavorite:
  url ──▶ bookmarkData(withSecurityScope) ──▶ FavoriteItem.bookmarkData
           │ (fails)
           └──▶ bookmarkData(plain) ──▶ FavoriteItem.bookmarkData
                 │ (fails)
                 └──▶ empty Data()

loadFavorites:
  bookmarkData ──▶ URL(resolvingBookmarkData, withSecurityScope)
                    │ (stale) → re-create bookmark
                    │ (fails)
                    └──▶ URL(resolvingBookmarkData, plain)
                          │ (fails)
                          └──▶ use stored URL directly
```

### Default Favorites
On first launch: Desktop, Documents, Downloads, Home directory — only if paths exist on disk.

---

## FileMoveService (FileMoveService.swift)

### Purpose
Stateless utility for validating and executing drag-and-drop file moves. Used directly by views (not through ViewModels).

### Declaration
```swift
enum FileMoveService  // Enum with no cases — namespace for static functions
```

### Result Type
```swift
struct MoveResult {
    let movedCount: Int
    let sourceDirs: Set<URL>  // Directories that need UI refresh
}
```

### Static Methods

#### validURLsForFolderDrop(_ urls: [URL], destination: URL) -> [URL]
Validates URLs for dropping onto a folder:
- Rejects: self-drop (url == destination)
- Rejects: circular reference (destination path starts with `url.path + "/"` — prevents parent-into-child moves while avoiding false prefix matches like `/Users/file` vs `/Users/file2`)

#### validURLsForBackgroundDrop(_ urls: [URL], destination: URL) -> [URL]
Stricter validation for dropping onto content area background:
- All folder-drop validations, plus:
- Rejects: items already in destination directory (parent path matches)

#### moveItems(_ urls: [URL], to destination: URL) -> MoveResult
Executes bulk file moves:
1. Track source directories in Set\<URL\>
2. For each URL: construct destination path, attempt FileManager.moveItem
3. On error: skip item, continue
4. Return MoveResult with count and source dirs

**Characteristics**:
- Synchronous (blocks calling thread)
- Partial success (some items may fail)
- @discardableResult (caller may ignore result)
- No error details (only success count)

---

## Cross-Service Patterns

### Concurrency Model

| Service | Thread Model | Why |
|---------|-------------|-----|
| FileSystemService | Actor + async/await | Thread-safe shared resource; multiple callers |
| ClipboardManager | Observable (main thread) | SwiftUI state; simple property updates |
| DirectoryWatcher | GCD utility queue | Low-priority FS monitoring; main-thread callbacks |
| FavoritesManager | Synchronous (caller thread) | Simple JSON I/O; infrequent operations |
| FileMoveService | Synchronous (caller thread) | Direct FileManager calls; used in drop handlers |

### Error Handling Philosophy

| Strategy | Used By | Behavior |
|----------|---------|----------|
| **Throw** | FileSystemService, ClipboardManager | Caller must handle errors |
| **Silent failure** | DirectoryWatcher | Best-effort monitoring |
| **Graceful degradation** | FavoritesManager | Fallback chain (security → plain → raw) |
| **Partial success** | FileMoveService | Skip failed items, return count |

### Performance Optimizations
1. **Streaming + batching**: FileSystemService.enumerate yields 500-item batches
2. **Pre-allocated collections**: reserveCapacity() calls throughout
3. **Static resource keys**: Avoid repeated Set allocations
4. **Debounced callbacks**: DirectoryWatcher 0.3s delay collapses rapid events
5. **Atomic writes**: FavoritesManager prevents JSON corruption
6. **Bookmark caching**: FavoriteItem stores resolved bookmark data
7. **Deferred operations**: ClipboardManager doesn't execute until paste()
