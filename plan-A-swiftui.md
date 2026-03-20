# Plan A: macOS File Explorer — Swift + SwiftUI (Native)

---

## 1. Executive Summary

This plan describes a native macOS file explorer application built entirely with **Swift and SwiftUI**, targeting macOS 14 (Sonoma) and later. The app — codename **Explorer** — aims to fill the gap left by Finder's missing "cut-to-move" workflow and limited customization, while preserving the native macOS look and feel that users expect. The core value proposition is a familiar, high-performance file browser with Windows Explorer–style conveniences: an always-visible "Up" button, true Cut/Paste file moving, a user-managed favorites sidebar, and multiple view modes with column-header sorting.

SwiftUI is chosen as the UI framework because it provides first-class support for macOS idioms — sidebars with `NavigationSplitView`, vibrancy materials, dark mode, and toolbar APIs — while dramatically reducing boilerplate compared to AppKit. Where SwiftUI falls short (e.g., `NSTableView`-level virtualization for 100k+ file directories, drag-and-drop edge cases, or context menus on specific rows), we bridge to AppKit via `NSViewRepresentable`. This hybrid strategy gives us the best of both worlds: rapid, declarative UI development with SwiftUI and battle-tested performance from AppKit's virtualized collection views.

The architecture follows **MVVM** (Model–View–ViewModel) with a unidirectional data flow. A central `NavigationViewModel` owns the current path, history stack, and sort state. A `FileSystemService` actor handles all async I/O on background threads, streaming directory contents via `AsyncSequence`. A `ClipboardManager` singleton manages the cut/paste buffer, tracking source paths and the pending operation (cut vs. copy). Favorites are persisted to a simple JSON file in `~/Library/Application Support/Explorer/`. The entire app is sandboxed with user-selected file access via security-scoped bookmarks, making it suitable for Mac App Store distribution or direct notarized distribution.

---

## 2. Technology Stack

| Layer              | Technology                         | Version / Notes                              |
| ------------------ | ---------------------------------- | -------------------------------------------- |
| Language           | Swift                              | 5.10+                                        |
| UI Framework       | SwiftUI                            | macOS 14+ (Sonoma)                           |
| AppKit Bridge      | NSViewRepresentable                | For virtualized list/table in 100k+ dirs     |
| File System        | Foundation (`FileManager`, `URL`)  | POSIX-level via `FileManager`                |
| Async I/O          | Swift Concurrency (async/await)    | Structured concurrency, `AsyncStream`        |
| File Monitoring    | `DispatchSource.makeFileSystemObjectSource` / `FSEvents` | Live directory change detection |
| Persistence        | `Codable` + JSON file              | Favorites, preferences                       |
| Security           | App Sandbox + Security-Scoped Bookmarks | Required for file access persistence    |
| Image Thumbnails   | QuickLook Thumbnails (`QLThumbnailGenerator`) | For icon/grid view previews         |
| Icons              | `NSWorkspace.shared.icon(forFile:)` | System file-type icons                      |
| Build System       | Xcode 15+                          | Swift Package Manager for deps               |
| Min Deployment     | macOS 14.0 (Sonoma)                | `NavigationSplitView` stability              |
| Distribution       | Developer ID / Mac App Store       | Notarization via `notarytool`                |

---

## 3. Architecture

### 3.1 MVVM Pattern

```
┌─────────────────────────────────────────────────────────────────────┐
│                              VIEWS (SwiftUI)                        │
│  ┌─────────────┐ ┌──────────────┐ ┌────────────┐ ┌──────────────┐  │
│  │ SidebarView  │ │ ToolbarView  │ │ ContentView│ │ StatusBarView│  │
│  │ (Favorites)  │ │ (Up, Path,   │ │ (List/Icon/ │ │ (Item count, │  │
│  │              │ │  ViewMode)   │ │  Column)    │ │  disk space) │  │
│  └──────┬───────┘ └──────┬───────┘ └─────┬──────┘ └──────┬───────┘  │
│         │                │               │               │          │
│         └────────────────┴───────┬───────┴───────────────┘          │
│                                  │ @ObservedObject / @EnvironmentObj│
└──────────────────────────────────┼──────────────────────────────────┘
                                   │
┌──────────────────────────────────┼──────────────────────────────────┐
│                          VIEW MODELS                                │
│  ┌──────────────────────┐  ┌────┴───────────────┐  ┌─────────────┐  │
│  │  NavigationViewModel │  │  DirectoryViewModel │  │ Favorites   │  │
│  │  - currentURL        │  │  - items: [FileItem]│  │ ViewModel   │  │
│  │  - backStack         │  │  - sortKey          │  │ - pins      │  │
│  │  - forwardStack      │  │  - sortAscending    │  │ - add/remove│  │
│  │  - navigateTo(url)   │  │  - viewMode         │  │ - persist() │  │
│  │  - goUp()            │  │  - loadDirectory()  │  │             │  │
│  │  - goBack()          │  │  - search/filter    │  │             │  │
│  └──────────┬───────────┘  └────────┬────────────┘  └──────┬──────┘  │
│             │                       │                      │         │
└─────────────┼───────────────────────┼──────────────────────┼─────────┘
              │                       │                      │
┌─────────────┼───────────────────────┼──────────────────────┼─────────┐
│             │              SERVICES / MODEL                │         │
│  ┌──────────┴───────────┐  ┌────────┴────────┐  ┌─────────┴──────┐  │
│  │  ClipboardManager    │  │ FileSystemService│  │ Persistence    │  │
│  │  (singleton)         │  │ (actor)          │  │ Service        │  │
│  │  - cutPaths: [URL]   │  │ - enumerate()    │  │ - loadFavs()   │  │
│  │  - operation: .cut   │  │ - move/copy/del  │  │ - saveFavs()   │  │
│  │  - paste(to:)        │  │ - watch(dir)     │  │ - loadPrefs()  │  │
│  └──────────────────────┘  └─────────────────┘  └────────────────┘  │
│                                                                      │
│  ┌──────────────────────────────────────────────────────────────┐    │
│  │  FileItem (struct, Identifiable, Hashable, Comparable)       │    │
│  │  - id: URL  - name: String  - size: Int64  - dateModified   │    │
│  │  - kind: UTType  - isDirectory: Bool  - icon: NSImage       │    │
│  └──────────────────────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────────────────┘
```

### 3.2 Data Flow (Unidirectional)

```
User Action (click, ⌘X, ⌘V, click "Up")
       │
       ▼
  View calls ViewModel method
       │
       ▼
  ViewModel updates @Published state
       │              │
       │              ▼
       │     ViewModel calls Service (async)
       │              │
       │              ▼
       │     Service performs I/O, returns result
       │              │
       ▼              ▼
  @Published properties update → SwiftUI re-renders
```

### 3.3 Key Design Decisions

- **`@Observable` macro (Observation framework)**: Use the new `@Observable` macro (macOS 14+) instead of `ObservableObject` for view models. This gives fine-grained property tracking and eliminates unnecessary re-renders.
- **Actor for file I/O**: `FileSystemService` is a Swift actor, ensuring all file system mutations are serialized and thread-safe.
- **`AsyncStream` for directory enumeration**: Large directories are streamed in batches (e.g., 500 items) so the UI can render incrementally.
- **Security-scoped bookmarks**: When the user grants folder access, we persist a security-scoped bookmark so the app can re-access that folder on relaunch without re-prompting.

---

## 4. Core Features Implementation

### 4.1 "Up" Button — Parent Folder Navigation

**User Perspective:**
An always-visible toolbar button (chevron-up SF Symbol or a labeled "Up" button) sits in the toolbar next to Back/Forward. Clicking it navigates to the parent directory of the current location. When already at a root volume (`/` or `/Volumes/X`), the button is disabled (grayed out). Keyboard shortcut: **⌘↑** (Cmd+Up Arrow), matching Finder's existing shortcut.

**SwiftUI Components:**
- `ToolbarItem(placement: .navigation)` containing a `Button` with `systemImage: "chevron.up"`.
- Disabled state bound to `navigationVM.canGoUp`.

**State Management:**
```swift
@Observable
final class NavigationViewModel {
    var currentURL: URL = FileManager.default.homeDirectoryForCurrentUser
    private(set) var backStack: [URL] = []
    private(set) var forwardStack: [URL] = []

    var canGoUp: Bool {
        currentURL.pathComponents.count > 1
    }

    func goUp() {
        let parent = currentURL.deletingLastPathComponent()
        guard parent != currentURL else { return }
        backStack.append(currentURL)
        forwardStack.removeAll()
        currentURL = parent
    }

    func navigateTo(_ url: URL) {
        guard url != currentURL else { return }
        backStack.append(currentURL)
        forwardStack.removeAll()
        currentURL = url
    }

    func goBack() {
        guard let prev = backStack.popLast() else { return }
        forwardStack.append(currentURL)
        currentURL = prev
    }

    func goForward() {
        guard let next = forwardStack.popLast() else { return }
        backStack.append(currentURL)
        currentURL = next
    }
}
```

**Keyboard Shortcuts:**
| Action      | Shortcut   |
| ----------- | ---------- |
| Go Up       | ⌘↑         |
| Go Back     | ⌘[         |
| Go Forward  | ⌘]         |
| Open Folder | ⌘↓ / Enter |

---

### 4.2 Cut/Paste to Move Files

**User Perspective:**
Select one or more files → **⌘X** cuts them (icons dim with 50% opacity to indicate "pending move"). Navigate to the destination folder → **⌘V** moves the files. If the user presses **⌘C** instead, it's a copy (standard). Right-click context menu also shows "Cut", "Copy", "Paste" options. If the user presses ⌘X and then ⌘C on different files, the cut buffer is replaced. Paste always clears the buffer.

**Key Components:**
- `ClipboardManager` — singleton managing the internal cut/paste buffer.
- Context menu on file items with `.contextMenu { }`.
- Keyboard shortcuts via `.keyboardShortcut()` on `Commands`.

**ClipboardManager Implementation:**

```swift
import Foundation
import Combine

enum ClipboardOperation {
    case cut
    case copy
}

@Observable
final class ClipboardManager {
    static let shared = ClipboardManager()

    private(set) var sourceURLs: [URL] = []
    private(set) var operation: ClipboardOperation?

    /// True when there are items ready to paste
    var canPaste: Bool {
        !sourceURLs.isEmpty && operation != nil
    }

    /// Returns true if the given URL is in the cut buffer (for dimming in UI)
    func isCut(_ url: URL) -> Bool {
        operation == .cut && sourceURLs.contains(url)
    }

    func cut(_ urls: [URL]) {
        sourceURLs = urls
        operation = .cut
    }

    func copy(_ urls: [URL]) {
        sourceURLs = urls
        operation = .copy
    }

    func clear() {
        sourceURLs = []
        operation = nil
    }

    /// Execute the paste into the destination directory.
    /// Returns the list of new URLs after the operation.
    func paste(to destination: URL) async throws -> [URL] {
        guard let op = operation else { return [] }
        let fm = FileManager.default
        var results: [URL] = []

        for source in sourceURLs {
            let destURL = destination.appendingPathComponent(source.lastPathComponent)
            let finalURL = uniqueURL(for: destURL) // handle name collisions

            switch op {
            case .cut:
                try fm.moveItem(at: source, to: finalURL)
            case .copy:
                try fm.copyItem(at: source, to: finalURL)
            }
            results.append(finalURL)
        }

        clear() // always clear after paste
        return results
    }

    /// Generate a unique filename if a collision exists:
    /// "file.txt" → "file 2.txt" → "file 3.txt"
    private func uniqueURL(for url: URL) -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return url }

        let stem = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        let parent = url.deletingLastPathComponent()
        var counter = 2

        while true {
            let newName = ext.isEmpty ? "\(stem) \(counter)" : "\(stem) \(counter).\(ext)"
            let candidate = parent.appendingPathComponent(newName)
            if !fm.fileExists(atPath: candidate.path) {
                return candidate
            }
            counter += 1
        }
    }
}
```

**UI Integration — Dimming Cut Items:**
```swift
// Inside file row view
FileRowView(item: item)
    .opacity(clipboardManager.isCut(item.url) ? 0.45 : 1.0)
```

**Commands (menu bar + keyboard shortcuts):**
```swift
struct ExplorerCommands: Commands {
    @Environment(ClipboardManager.self) var clipboard
    @Environment(NavigationViewModel.self) var navigation

    var body: some Commands {
        CommandGroup(after: .pasteboard) {
            Button("Cut") {
                clipboard.cut(selectedURLs)
            }
            .keyboardShortcut("x", modifiers: .command)

            Button("Paste") {
                Task {
                    try await clipboard.paste(to: navigation.currentURL)
                }
            }
            .keyboardShortcut("v", modifiers: .command)
            .disabled(!clipboard.canPaste)
        }
    }
}
```

**Error Handling:**
- Permission denied → alert dialog with "The operation couldn't be completed. You don't have permission to move 'filename'."
- Cross-volume move → automatically falls back to copy + delete (FileManager handles this).
- Undo support → store the reverse operation in an `UndoManager` so ⌘Z can undo the move.

---

### 4.3 Favorites Sidebar

**User Perspective:**
The left sidebar shows two sections: **System Locations** (Desktop, Documents, Downloads, Applications — auto-populated) and **Favorites** (user-managed). Users add favorites by:
1. Dragging a folder from the content area onto the sidebar.
2. Right-clicking a folder → "Add to Favorites".
3. Using the menu: File → Add to Favorites (⌘D).

Removing: right-click a favorite → "Remove from Favorites". Favorites are reorderable via drag-and-drop within the sidebar.

**SwiftUI Components:**
- `NavigationSplitView` with a `sidebar` column.
- `List` with `Section` for "System" and "Favorites".
- `.onDrop(of:)` modifier to accept folder drops.
- `.contextMenu { }` for remove action.
- `.onMove` modifier for reordering.

**Data Model:**

```swift
struct FavoriteItem: Codable, Identifiable, Hashable {
    let id: UUID
    let url: URL
    let bookmarkData: Data // security-scoped bookmark
    var customName: String? // user can rename the pin

    var displayName: String {
        customName ?? url.lastPathComponent
    }
}

@Observable
final class FavoritesViewModel {
    var systemLocations: [FavoriteItem] = [] // auto-populated, non-removable
    var userFavorites: [FavoriteItem] = []    // user-managed, persisted

    private let storageURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Explorer", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("favorites.json")
    }()

    init() {
        loadSystemLocations()
        loadFavorites()
    }

    func addFavorite(url: URL) {
        guard !userFavorites.contains(where: { $0.url == url }) else { return }
        guard let bookmark = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else { return }
        let item = FavoriteItem(id: UUID(), url: url, bookmarkData: bookmark)
        userFavorites.append(item)
        saveFavorites()
    }

    func removeFavorite(_ item: FavoriteItem) {
        userFavorites.removeAll { $0.id == item.id }
        saveFavorites()
    }

    func moveFavorite(from source: IndexSet, to destination: Int) {
        userFavorites.move(fromOffsets: source, toOffset: destination)
        saveFavorites()
    }

    private func loadFavorites() {
        guard let data = try? Data(contentsOf: storageURL),
              let items = try? JSONDecoder().decode([FavoriteItem].self, from: data) else { return }
        userFavorites = items
    }

    private func saveFavorites() {
        guard let data = try? JSONEncoder().encode(userFavorites) else { return }
        try? data.write(to: storageURL, options: .atomic)
    }

    private func loadSystemLocations() {
        let fm = FileManager.default
        let pairs: [(String, FileManager.SearchPathDirectory)] = [
            ("Desktop", .desktopDirectory),
            ("Documents", .documentDirectory),
            ("Downloads", .downloadsDirectory),
        ]
        systemLocations = pairs.compactMap { name, dir in
            guard let url = fm.urls(for: dir, in: .userDomainMask).first else { return nil }
            return FavoriteItem(id: UUID(), url: url, bookmarkData: Data(), customName: name)
        }
        // Add hard-coded paths
        let extra: [(String, String)] = [
            ("Applications", "/Applications"),
            ("Home", NSHomeDirectory()),
        ]
        systemLocations += extra.map { name, path in
            FavoriteItem(id: UUID(), url: URL(fileURLWithPath: path), bookmarkData: Data(), customName: name)
        }
    }
}
```

---

### 4.4 Multiple View Modes

**Supported Modes:**

| Mode        | Description                                                    | Implementation       |
| ----------- | -------------------------------------------------------------- | -------------------- |
| **List**    | Detailed rows with columns: Name, Date Modified, Size, Kind   | `Table` (SwiftUI)    |
| **Icon**    | Grid of icons with filenames below                             | `LazyVGrid`          |
| **Column**  | Miller columns, each column shows a directory level            | Custom `HSplitView`  |

**User Perspective:**
Toggle buttons in the toolbar (SF Symbols: `list.bullet`, `square.grid.2x2`, `rectangle.split.3x1`). Keyboard shortcuts: ⌘1 (List), ⌘2 (Icon), ⌘3 (Column). View mode is persisted per window.

**State:**
```swift
enum ViewMode: String, CaseIterable, Codable {
    case list
    case icon
    case column
}
```

**List View (SwiftUI `Table`):**
```swift
Table(directoryVM.sortedItems, selection: $selectedItems) {
    TableColumn("Name", value: \.name) { item in
        FileNameCell(item: item)
    }
    .width(min: 200, ideal: 300)

    TableColumn("Date Modified", value: \.dateModified) { item in
        Text(item.dateModified, style: .date)
    }
    .width(min: 120, ideal: 160)

    TableColumn("Size") { item in
        Text(item.isDirectory ? "--" : ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file))
    }
    .width(min: 80, ideal: 100)

    TableColumn("Kind", value: \.kindDescription)
        .width(min: 100, ideal: 140)
}
```

**Icon View (LazyVGrid):**
```swift
let columns = [GridItem(.adaptive(minimum: 90, maximum: 120))]

ScrollView {
    LazyVGrid(columns: columns, spacing: 16) {
        ForEach(directoryVM.sortedItems) { item in
            IconCell(item: item)
        }
    }
    .padding()
}
```

**Column View (Custom Miller Columns):**
```swift
struct ColumnBrowserView: View {
    @State private var columnPaths: [URL] // each element = one column's directory

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 0) {
                ForEach(Array(columnPaths.enumerated()), id: \.offset) { index, path in
                    ColumnListView(
                        directoryURL: path,
                        onSelect: { url in
                            navigateColumn(at: index, to: url)
                        }
                    )
                    .frame(width: 220)
                    Divider()
                }
            }
        }
    }
}
```

**AppKit Fallback for 100k+ Items:**
For the List view, if a directory exceeds a threshold (e.g., 10,000 items), we swap the SwiftUI `Table` for an `NSTableView` wrapped in `NSViewRepresentable`. This provides cell-level virtualization that SwiftUI's `Table` cannot match. See §5 for details.

---

### 4.5 Sorting

**User Perspective:**
In List view, clicking a column header sorts by that column. Clicking the same header again toggles ascending/descending. A small arrow indicator shows current sort direction. In Icon and Column views, sorting is controlled via a dropdown menu in the toolbar.

**State:**
```swift
enum SortKey: String, CaseIterable, Codable {
    case name
    case dateModified
    case size
    case kind
}

// Inside DirectoryViewModel
@Observable
final class DirectoryViewModel {
    var items: [FileItem] = []
    var sortKey: SortKey = .name
    var sortAscending: Bool = true

    var sortedItems: [FileItem] {
        items.sorted { a, b in
            let result: Bool
            switch sortKey {
            case .name:
                result = a.name.localizedStandardCompare(b.name) == .orderedAscending
            case .dateModified:
                result = a.dateModified < b.dateModified
            case .size:
                result = a.size < b.size
            case .kind:
                result = a.kindDescription.localizedStandardCompare(b.kindDescription) == .orderedAscending
            }
            return sortAscending ? result : !result
        }
    }

    func toggleSort(by key: SortKey) {
        if sortKey == key {
            sortAscending.toggle()
        } else {
            sortKey = key
            sortAscending = true
        }
    }
}
```

**Keyboard Shortcuts for Sorting:**
Sorting is accessible through the View menu rather than direct shortcuts to avoid conflicts.

**Folders-First Option:**
A toggle in View menu: "Keep Folders on Top" (default: on). When enabled, directories always sort before files regardless of sort key.

---

### 4.6 Performance Optimized (100k+ Files)

See §5 for the full performance strategy. Key summary:

- **Async enumeration** — `FileManager.enumerator` runs on a background actor, streaming items in batches of 500 via `AsyncStream`.
- **Virtualized rendering** — `NSTableView` (via `NSViewRepresentable`) for List view; `LazyVGrid` for Icon view. Only visible rows are rendered.
- **Incremental loading** — The UI displays items as they arrive. A progress indicator shows "Loading... (45,000 of ~100,000)".
- **Minimal metadata** — Only fetch `name`, `size`, `dateModified`, `isDirectory`, and `contentType` resource keys in the initial scan. Thumbnails are loaded lazily on-demand when a row becomes visible.
- **Sorted insertion** — Items are inserted into a pre-sorted array (binary search for insert position) so re-sorting the full array is avoided during loading.
- **Debounced search/filter** — Typing in the filter bar debounces at 150ms to avoid re-filtering on every keystroke.
- **Background sort** — For 100k+ items, sorting runs on a background thread with the result dispatched back to main.
- **Caching** — Directory contents are cached in a `NSCache` keyed by URL. Cache is invalidated by FSEvents file watcher.

---

### 4.7 Finder-Like Look and Feel

**Approach:**
- Use `.background(.regularMaterial)` (vibrancy) on the sidebar.
- Use `NavigationSplitView` for the standard three-column layout Finder uses.
- Use system SF Symbols for toolbar icons.
- Support both light and dark mode (automatic with SwiftUI).
- Standard macOS window chrome — title bar, traffic lights, full-screen support.
- Window title shows current folder name; subtitle shows item count.
- Use `.windowToolbarStyle(.unified)` for the compact toolbar style.
- File icons from `NSWorkspace.shared.icon(forFile:)` for pixel-perfect system icons.
- Translucent sidebar matching the system appearance via `.listStyle(.sidebar)`.

**Detail Touches:**
- Quick Look preview (spacebar) via `QLPreviewPanel`.
- Double-click folder → navigate into it; double-click file → open with default app.
- Rename in place (press Enter on selected file → inline text field, like Finder).
- Breadcrumb path bar in the toolbar showing clickable path segments.
- Status bar at the bottom: "42 items, 1.2 GB available".

---

## 5. Performance Strategy

### 5.1 Directory Enumeration

```swift
actor FileSystemService {
    func enumerateDirectory(
        at url: URL,
        keys: [URLResourceKey] = [.nameKey, .fileSizeKey, .contentModificationDateKey,
                                   .isDirectoryKey, .contentTypeKey]
    ) -> AsyncStream<[FileItem]> {
        AsyncStream { continuation in
            Task.detached(priority: .userInitiated) {
                let fm = FileManager.default
                var batch: [FileItem] = []
                batch.reserveCapacity(500)

                guard let enumerator = fm.enumerator(
                    at: url,
                    includingPropertiesForKeys: keys,
                    options: [.skipsSubdirectoryDescendants, .skipsHiddenFiles]
                ) else {
                    continuation.finish()
                    return
                }

                for case let fileURL as URL in enumerator {
                    if Task.isCancelled { break }

                    guard let values = try? fileURL.resourceValues(forKeys: Set(keys)) else { continue }

                    let item = FileItem(
                        url: fileURL,
                        name: values.name ?? fileURL.lastPathComponent,
                        size: Int64(values.fileSize ?? 0),
                        dateModified: values.contentModificationDate ?? .distantPast,
                        isDirectory: values.isDirectory ?? false,
                        contentType: values.contentType
                    )
                    batch.append(item)

                    if batch.count >= 500 {
                        continuation.yield(batch)
                        batch.removeAll(keepingCapacity: true)
                    }
                }

                if !batch.isEmpty {
                    continuation.yield(batch)
                }
                continuation.finish()
            }
        }
    }
}
```

### 5.2 Consuming the Stream in the ViewModel

```swift
@Observable
final class DirectoryViewModel {
    var items: [FileItem] = []
    var isLoading: Bool = false
    var loadedCount: Int = 0
    private var loadTask: Task<Void, Never>?
    private let fileSystem = FileSystemService()

    func loadDirectory(at url: URL) {
        loadTask?.cancel()
        items = []
        loadedCount = 0
        isLoading = true

        loadTask = Task { @MainActor in
            for await batch in await fileSystem.enumerateDirectory(at: url) {
                items.append(contentsOf: batch)
                loadedCount = items.count
            }
            isLoading = false
        }
    }
}
```

### 5.3 Virtualized NSTableView (AppKit Bridge)

For directories exceeding ~10k files, the List view delegates to a wrapped `NSTableView`:

```swift
struct VirtualizedTableView: NSViewRepresentable {
    let items: [FileItem]
    let sortKey: SortKey
    let sortAscending: Bool
    @Binding var selection: Set<FileItem.ID>

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let tableView = NSTableView()
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.style = .fullWidth
        tableView.allowsMultipleSelection = true

        // Add columns
        for col in ["Name", "Date Modified", "Size", "Kind"] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(col))
            column.title = col
            column.sortDescriptorPrototype = NSSortDescriptor(key: col, ascending: true)
            tableView.addTableColumn(column)
        }

        tableView.dataSource = context.coordinator
        tableView.delegate = context.coordinator
        scrollView.documentView = tableView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.items = items
        (nsView.documentView as? NSTableView)?.reloadData()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(items: items, selection: $selection)
    }

    class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var items: [FileItem]
        @Binding var selection: Set<FileItem.ID>

        init(items: [FileItem], selection: Binding<Set<FileItem.ID>>) {
            self.items = items
            self._selection = selection
        }

        func numberOfRows(in tableView: NSTableView) -> Int { items.count }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            let item = items[row]
            let cell = NSTextField(labelWithString: "")
            switch tableColumn?.identifier.rawValue {
            case "Name": cell.stringValue = item.name
            case "Date Modified": cell.stringValue = item.dateModified.formatted()
            case "Size": cell.stringValue = item.isDirectory ? "--" : ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file)
            case "Kind": cell.stringValue = item.kindDescription
            default: break
            }
            return cell
        }
    }
}
```

### 5.4 Thumbnail & Icon Loading

```
┌────────────────────────────────────┐
│  Visible rows (from scroll offset) │
│  ┌─────┐ ┌─────┐ ┌─────┐          │
│  │ Row │ │ Row │ │ Row │  ← only these request icons
│  └─────┘ └─────┘ └─────┘          │
│                                    │
│  ... 99,970 off-screen rows ...    │
│  (no icon/thumbnail work)          │
└────────────────────────────────────┘
         │
         ▼
  Icon request → NSWorkspace.icon(forFile:)  [sync, fast, cached by system]
  Thumbnail request → QLThumbnailGenerator   [async, only in Icon view]
         │
         ▼
  NSCache<URL, NSImage> (max 2000 entries)
```

### 5.5 Directory Watching (Live Updates)

```swift
final class DirectoryWatcher {
    private var source: DispatchSourceFileSystemObject?
    private let fd: Int32

    init(url: URL, onChange: @escaping () -> Void) {
        fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }

        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete, .attrib],
            queue: .global(qos: .utility)
        )
        source?.setEventHandler { onChange() }
        source?.setCancelHandler { [fd] in close(fd) }
        source?.resume()
    }

    deinit {
        source?.cancel()
    }
}
```

When a change is detected, the `DirectoryViewModel` performs a differential reload — comparing the new file list against the cached one and applying inserts/deletes rather than reloading everything.

---

## 6. File System Operations

### 6.1 Operations Table

| Operation     | API                                  | Shortcut | Notes                                     |
| ------------- | ------------------------------------ | -------- | ----------------------------------------- |
| Cut           | Internal buffer (ClipboardManager)   | ⌘X       | Marks files; no FS change until paste     |
| Copy          | Internal buffer (ClipboardManager)   | ⌘C       | Also puts file URLs on NSPasteboard       |
| Paste (move)  | `FileManager.moveItem(at:to:)`       | ⌘V       | Cross-volume = copy + delete              |
| Paste (copy)  | `FileManager.copyItem(at:to:)`       | ⌘V       | Used when source was ⌘C                   |
| Delete        | `FileManager.trashItem(at:...)`      | ⌘⌫       | Moves to Trash (recoverable)              |
| Perm. Delete  | `FileManager.removeItem(at:)`        | ⌥⌘⌫     | Confirmation dialog required              |
| Rename        | `FileManager.moveItem(at:to:)`       | Enter    | Inline text field, same directory          |
| New Folder    | `FileManager.createDirectory(...)`   | ⇧⌘N     | Creates "untitled folder", starts rename   |
| Open          | `NSWorkspace.shared.open(url)`       | ⌘O       | Opens file with default app               |
| Get Info      | Custom sheet view                    | ⌘I       | Shows size, permissions, dates             |

### 6.2 Undo/Redo

Each file operation pushes an action onto the window's `UndoManager`:

```swift
struct FileAction {
    let type: FileActionType   // .move, .copy, .delete, .rename
    let sources: [URL]
    let destinations: [URL]
}

// After a move:
undoManager?.registerUndo(withTarget: self) { target in
    Task {
        // Reverse the move
        for (src, dest) in zip(action.destinations, action.sources) {
            try FileManager.default.moveItem(at: src, to: dest)
        }
        target.reload()
    }
}
undoManager?.setActionName("Move \(action.sources.count) Items")
```

### 6.3 Conflict Resolution

When pasting and a file with the same name exists at the destination:

```
┌─────────────────────────────────────────────┐
│  "report.pdf" already exists at this        │
│  location. What would you like to do?       │
│                                             │
│  [Keep Both]   [Replace]   [Skip]   [Stop]  │
│                                             │
│  ☐ Apply to all remaining conflicts         │
└─────────────────────────────────────────────┘
```

- **Keep Both**: Auto-rename with " 2" suffix.
- **Replace**: Overwrite (trash old file first for undo safety).
- **Skip**: Leave the source file in place.
- **Stop**: Cancel remaining items in the paste batch.

---

## 7. Persistence

### 7.1 What Is Persisted

| Data              | Storage                                | Format     |
| ----------------- | -------------------------------------- | ---------- |
| Favorites list    | `~/Library/Application Support/Explorer/favorites.json` | JSON |
| Preferences       | `UserDefaults` (standard suite)        | Plist      |
| Window state      | `NSWindow` restoration (automatic)     | System     |
| Recent locations  | `UserDefaults` array                   | Plist      |
| Security bookmarks| Inside `favorites.json`                | Base64     |

### 7.2 Preferences Model

```swift
final class PreferencesManager {
    @AppStorage("defaultViewMode") var defaultViewMode: ViewMode = .list
    @AppStorage("showHiddenFiles") var showHiddenFiles: Bool = false
    @AppStorage("foldersOnTop") var foldersOnTop: Bool = true
    @AppStorage("defaultSortKey") var defaultSortKey: SortKey = .name
    @AppStorage("defaultSortAscending") var defaultSortAscending: Bool = true
    @AppStorage("iconSize") var iconSize: Double = 64.0
    @AppStorage("sidebarWidth") var sidebarWidth: Double = 200.0
}
```

### 7.3 Security-Scoped Bookmarks

When a user adds a favorite or grants access to a folder via `NSOpenPanel`, we persist a security-scoped bookmark:

```swift
// Save
let bookmarkData = try url.bookmarkData(
    options: .withSecurityScope,
    includingResourceValuesForKeys: nil,
    relativeTo: nil
)

// Restore
var isStale = false
let url = try URL(
    resolvingBookmarkData: bookmarkData,
    options: .withSecurityScope,
    relativeTo: nil,
    bookmarkDataIsStale: &isStale
)
guard url.startAccessingSecurityScopedResource() else { throw AccessError.denied }
defer { url.stopAccessingSecurityScopedResource() }
```

---

## 8. Project Structure

```
Explorer/
├── Explorer.xcodeproj
├── Explorer/
│   ├── ExplorerApp.swift                 # @main, WindowGroup, Commands
│   ├── Assets.xcassets/                  # App icon, accent color
│   ├── Info.plist                        # Sandbox entitlements ref
│   ├── Explorer.entitlements             # App Sandbox config
│   │
│   ├── Models/
│   │   ├── FileItem.swift                # Core file data struct
│   │   ├── FavoriteItem.swift            # Favorite/pin model
│   │   ├── SortKey.swift                 # Enum for sort columns
│   │   └── ViewMode.swift                # Enum for view modes
│   │
│   ├── ViewModels/
│   │   ├── NavigationViewModel.swift     # Path, history, up/back/fwd
│   │   ├── DirectoryViewModel.swift      # File list, sort, filter, load
│   │   ├── FavoritesViewModel.swift      # Sidebar favorites management
│   │   └── SelectionViewModel.swift      # Multi-select state
│   │
│   ├── Services/
│   │   ├── FileSystemService.swift       # Actor: enumerate, move, copy, delete
│   │   ├── ClipboardManager.swift        # Cut/copy/paste buffer
│   │   ├── DirectoryWatcher.swift        # FSEvents / DispatchSource watcher
│   │   ├── ThumbnailService.swift        # QLThumbnailGenerator cache
│   │   └── PersistenceService.swift      # JSON read/write for favorites
│   │
│   ├── Views/
│   │   ├── MainWindow/
│   │   │   ├── ContentView.swift         # NavigationSplitView root
│   │   │   ├── ToolbarView.swift         # Up, back, fwd, view toggle, path
│   │   │   └── StatusBarView.swift       # Item count, disk space
│   │   │
│   │   ├── Sidebar/
│   │   │   ├── SidebarView.swift         # System + user favorites list
│   │   │   └── SidebarItemView.swift     # Individual sidebar row
│   │   │
│   │   ├── FileList/
│   │   │   ├── FileListSwitcher.swift    # Routes to List/Icon/Column view
│   │   │   ├── ListView.swift            # SwiftUI Table view
│   │   │   ├── IconView.swift            # LazyVGrid icon view
│   │   │   ├── ColumnView.swift          # Miller column browser
│   │   │   └── VirtualizedTableView.swift# NSTableView bridge for perf
│   │   │
│   │   ├── Cells/
│   │   │   ├── FileNameCell.swift        # Icon + name + inline rename
│   │   │   ├── IconCell.swift            # Thumbnail + name for grid
│   │   │   └── ColumnItemCell.swift      # Row in a Miller column
│   │   │
│   │   ├── Dialogs/
│   │   │   ├── ConflictDialog.swift      # Replace/Keep Both/Skip
│   │   │   ├── GetInfoSheet.swift        # File info panel
│   │   │   └── PreferencesView.swift     # Settings window
│   │   │
│   │   └── Shared/
│   │       ├── PathBarView.swift         # Breadcrumb clickable path
│   │       ├── SearchField.swift         # Filter/search bar
│   │       └── ContextMenuModifier.swift # Reusable right-click menu
│   │
│   └── Utilities/
│       ├── URL+Extensions.swift          # URL helpers (parent, unique name)
│       ├── FileItem+Comparable.swift     # Sorting comparators
│       ├── ByteCountFormatter+.swift     # Size formatting helpers
│       └── NSImage+Thumbnail.swift       # Image scaling utilities
│
├── ExplorerTests/
│   ├── ClipboardManagerTests.swift
│   ├── NavigationViewModelTests.swift
│   ├── DirectoryViewModelTests.swift
│   ├── FavoritesViewModelTests.swift
│   └── FileSystemServiceTests.swift
│
└── ExplorerUITests/
    ├── NavigationUITests.swift
    └── CutPasteUITests.swift
```

---

## 9. Build & Distribution

### 9.1 Build Settings

| Setting                     | Value                                |
| --------------------------- | ------------------------------------ |
| Deployment Target           | macOS 14.0                           |
| Swift Language Version      | 5.10                                 |
| Build System                | New Build System (default)           |
| Code Signing                | Developer ID Application             |
| Hardened Runtime             | Yes (required for notarization)      |
| App Sandbox                 | Yes                                  |
| File Access: User Selected  | Read/Write                           |
| File Access: Downloads      | Read/Write (convenience)             |

### 9.2 Entitlements

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>
    <key>com.apple.security.files.downloads.read-write</key>
    <true/>
    <key>com.apple.security.files.bookmarks.app-scope</key>
    <true/>
</dict>
</plist>
```

### 9.3 Build & Notarize Commands

```bash
# Build release archive
xcodebuild archive \
  -project Explorer.xcodeproj \
  -scheme Explorer \
  -configuration Release \
  -archivePath build/Explorer.xcarchive

# Export the app
xcodebuild -exportArchive \
  -archivePath build/Explorer.xcarchive \
  -exportPath build/Export \
  -exportOptionsPlist ExportOptions.plist

# Notarize
xcrun notarytool submit build/Export/Explorer.app.zip \
  --apple-id "$APPLE_ID" \
  --team-id "$TEAM_ID" \
  --password "$APP_PASSWORD" \
  --wait

# Staple
xcrun stapler staple build/Export/Explorer.app
```

---

## 10. Pros & Cons

### Pros

| Advantage                          | Detail                                                                |
| ---------------------------------- | --------------------------------------------------------------------- |
| **Native look & feel**             | SwiftUI automatically matches macOS appearance, dark mode, vibrancy   |
| **Small binary size**              | No Electron/web runtime; ~5-10 MB app bundle                         |
| **Low memory usage**               | Native views, no browser engine; ~30-50 MB typical                    |
| **System integration**             | Full access to Quick Look, Spotlight, Services menu, NSPasteboard     |
| **Modern Swift concurrency**       | async/await, actors make file I/O safe and clean                      |
| **Observation framework**          | `@Observable` gives fine-grained reactivity, fewer unnecessary redraws |
| **Single codebase, single lang**   | All Swift, no JS/HTML/CSS layer                                       |
| **App Store eligible**             | Can be sandboxed and distributed via Mac App Store                    |
| **Fast startup**                   | Native app launches in <0.5s                                          |

### Cons

| Disadvantage                          | Detail                                                             | Mitigation                                             |
| ------------------------------------- | ------------------------------------------------------------------ | ------------------------------------------------------ |
| **SwiftUI table perf at 100k+ rows** | SwiftUI `Table` can struggle with extreme row counts               | Fall back to `NSTableView` via `NSViewRepresentable`   |
| **macOS 14+ requirement**            | Cuts off users on Monterey/Ventura                                 | Could lower to macOS 13 with some feature trade-offs   |
| **SwiftUI API gaps**                 | Some things (key events, drag images) need AppKit bridges          | Use `NSViewRepresentable` / `NSHostingView` as needed  |
| **macOS only**                       | No cross-platform story; can't run on Windows/Linux                | Intentional: native quality > cross-platform reach     |
| **Sandbox restrictions**             | File access requires user grant; can't freely access `/`           | Security-scoped bookmarks + "grant full disk access"   |
| **Complex drag-and-drop**            | SwiftUI drag-and-drop API is still maturing                        | Use AppKit `NSDraggingDestination` for sidebar drops   |
| **Limited table customization**      | SwiftUI `Table` doesn't support column reordering/resizing well    | AppKit `NSTableView` bridge for advanced needs         |
| **Testing**                          | SwiftUI view testing is limited; mostly UI tests                   | Strong ViewModel unit tests + XCUITest for flows       |

---

## 11. ASCII Mockup

```
┌──────────────────────────────────────────────────────────────────────────────┐
│ ● ● ●                        Explorer — Documents                          │
├──────────────────────────────────────────────────────────────────────────────┤
│ TOOLBAR                                                                     │
│ [←][→][↑]  │ 🏠 > Users > ehamai > Documents       │ [≡][⊞][⫏] │ 🔍 Filter│
│  Back Fwd Up│        Breadcrumb Path Bar             │ List Icon Col│ Search  │
├─────────────┼────────────────────────────────────────────────────────────────┤
│ SIDEBAR     │ CONTENT AREA (List View shown)                                │
│             │                                                               │
│ ▾ System    │  Name ▲           Date Modified     Size       Kind           │
│   🖥 Desktop│  ─────────────────────────────────────────────────────────     │
│   📁 Docs   │  📁 Projects     2024-12-01 10:30   --         Folder         │
│   📥 Downlds│  📁 Archive      2024-11-15 09:00   --         Folder         │
│   📱 Apps   │  📄 readme.md    2024-12-10 14:22   4 KB       Markdown       │
│   🏠 Home   │  📄 report.pdf   2024-12-09 11:45   2.1 MB     PDF Document  │
│             │  📄 notes.txt    2024-12-08 16:30   512 B      Plain Text    │
│ ▾ Favorites │  📄 budget.xlsx  2024-12-07 09:15   156 KB     Spreadsheet   │
│   📁 Work   │  🖼 photo.jpg    2024-12-06 20:00   3.4 MB     JPEG Image    │
│   📁 Music  │  📄 script.sh    2024-12-05 08:45   1.2 KB     Shell Script  │
│   📁 dev    │  ░░░░░░░░░░░░░░░░░░░░ (dimmed = cut) ░░░░░░░░░░░░░░░░░░░    │
│             │                                                               │
│ ─────────── │                                                               │
│ [+ Add Fav] │                                                               │
│             │                                                               │
├─────────────┴────────────────────────────────────────────────────────────────┤
│ STATUS BAR                                                                   │
│  8 items  •  3 selected  •  42.5 GB available                               │
└──────────────────────────────────────────────────────────────────────────────┘


ICON VIEW (alternate):
┌──────────────────────────────────────────────────────────────────┐
│                                                                  │
│   ┌──────┐  ┌──────┐  ┌──────┐  ┌──────┐  ┌──────┐             │
│   │ 📁   │  │ 📁   │  │ 📄   │  │ 📄   │  │ 📄   │             │
│   │      │  │      │  │      │  │      │  │      │             │
│   │Projec│  │Archiv│  │readme│  │report│  │notes │             │
│   └──────┘  └──────┘  └──────┘  └──────┘  └──────┘             │
│                                                                  │
│   ┌──────┐  ┌──────┐  ┌──────┐                                  │
│   │ 📄   │  │ 🖼   │  │ 📄   │                                  │
│   │      │  │      │  │      │                                  │
│   │budget│  │photo │  │script│                                  │
│   └──────┘  └──────┘  └──────┘                                  │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘


COLUMN VIEW (alternate):
┌───────────────┬───────────────┬───────────────┬──────────────────┐
│  Users        │  ehamai       │  Documents    │  ▌ Preview ▌     │
│ ─────────     │ ─────────     │ ─────────     │                  │
│  admin        │ ▸ Desktop     │ ▸ Projects  ◀ │  report.pdf      │
│ ▸ ehamai    ◀ │ ▸ Documents ◀ │ ▸ Archive     │  ───────────     │
│  guest        │ ▸ Downloads   │  readme.md    │  PDF Document    │
│               │ ▸ Music       │  report.pdf   │  2.1 MB          │
│               │ ▸ Pictures    │  notes.txt    │  Modified:       │
│               │   .zshrc      │  budget.xlsx  │  Dec 9, 2024     │
│               │               │  photo.jpg    │                  │
│               │               │  script.sh    │  [Quick Look]    │
└───────────────┴───────────────┴───────────────┴──────────────────┘


CONTEXT MENU (right-click on file):
┌──────────────────┐
│  Open             │
│  Open With ▸      │
│  ─────────────── │
│  Cut        ⌘X   │
│  Copy       ⌘C   │
│  Paste      ⌘V   │
│  ─────────────── │
│  Rename     ↩    │
│  Move to Trash ⌘⌫│
│  ─────────────── │
│  Add to Favorites │
│  Get Info    ⌘I   │
│  Quick Look  ␣    │
└──────────────────┘
```

---

## Appendix: Complete Keyboard Shortcuts Reference

| Action                 | Shortcut       |
| ---------------------- | -------------- |
| Go Up                  | ⌘↑             |
| Go Back                | ⌘[             |
| Go Forward             | ⌘]             |
| Open item              | ⌘O / ⌘↓       |
| Cut                    | ⌘X             |
| Copy                   | ⌘C             |
| Paste                  | ⌘V             |
| Select All             | ⌘A             |
| Rename                 | Enter          |
| Move to Trash          | ⌘⌫             |
| Delete permanently     | ⌥⌘⌫           |
| New Folder             | ⇧⌘N           |
| Get Info               | ⌘I             |
| Quick Look             | Space          |
| Toggle Hidden Files    | ⇧⌘.           |
| List View              | ⌘1             |
| Icon View              | ⌘2             |
| Column View            | ⌘3             |
| Add to Favorites       | ⌘D             |
| Find / Filter          | ⌘F             |
| Preferences            | ⌘,             |
| New Window             | ⌘N             |
| Close Window           | ⌘W             |
| Undo                   | ⌘Z             |
| Redo                   | ⇧⌘Z           |

---

*End of Plan A — SwiftUI Native Implementation*
