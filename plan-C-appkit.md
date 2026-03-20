# Plan C: macOS File Explorer — Swift + AppKit

## 1. Executive Summary

This plan describes a high-performance macOS file explorer built entirely with **Swift and AppKit** — Apple's mature, battle-tested UI framework. AppKit is the same technology underpinning Finder, Xcode, and every professional macOS application. For a file explorer that must handle directories with 100,000+ items without stuttering, AppKit is the unambiguous best choice: `NSTableView` and `NSCollectionView` provide true cell recycling and lazy loading out of the box, `NSOutlineView` delivers virtualized tree rendering, and the data-source pattern gives the developer full control over when and how data is fetched, sorted, and displayed.

Unlike SwiftUI (which still lacks mature table virtualization on macOS) or cross-platform frameworks (which impose abstraction overhead), AppKit lets us build directly on top of the same primitives the OS uses. We get pixel-perfect native rendering, full `NSVisualEffectView` vibrancy, source-list sidebar styling, dark mode for free, and zero runtime translation layers. The tradeoff is more boilerplate and manual state management — but for a performance-critical app like a file explorer, that control is the point.

The app implements every user-requested feature: an always-visible **Up button** in the toolbar, **Cut/Paste file moving** (Cmd+X / Cmd+V with custom pasteboard management), a **drag-and-drop Favorites sidebar**, **three view modes** (List, Icon/Grid, Column), **full column-header sorting**, **100k+ file performance**, and a **Finder-like native aesthetic**. The architecture follows a clean MVC + Coordinator pattern, with a central `FileSystemManager` mediating all file operations and a `ClipboardManager` handling the custom cut/paste state that macOS's pasteboard API doesn't natively provide.

---

## 2. Technology Stack

| Component              | Technology                              | Notes                                        |
|------------------------|-----------------------------------------|----------------------------------------------|
| Language               | Swift 5.9+                              | Strict concurrency when ready                |
| UI Framework           | AppKit                                  | No SwiftUI dependency                        |
| File System            | `FileManager`, `NSFileCoordinator`      | Coordinated file access                      |
| File Monitoring        | `DispatchSource.makeFileSystemObjectSource` / `FSEvents` | Live directory watching           |
| Pasteboard             | `NSPasteboard` + custom cut state       | Standard pasteboard + internal cut flag      |
| Persistence            | `UserDefaults`, `Codable` JSON          | Favorites, preferences, window state         |
| Security               | Security-Scoped Bookmarks               | Persist sandbox-safe folder access           |
| Thumbnails             | `QLThumbnailGenerator` (QuickLook)      | Async thumbnail generation                   |
| Icons                  | `NSWorkspace.shared.icon(forFile:)`     | System file icons                            |
| Concurrency            | GCD (`DispatchQueue`, `DispatchWorkItem`) | Background enumeration                     |
| Min macOS Version      | macOS 13.0 (Ventura)                    | Broad compatibility, modern APIs             |
| Build System           | Xcode 15+, Swift Package Manager        | No CocoaPods/Carthage needed                 |
| Distribution           | Direct (Developer ID) or Mac App Store  | Notarization required for both               |

---

## 3. Architecture

### Pattern: MVC + Coordinator

AppKit naturally aligns with MVC. We layer a lightweight Coordinator on top to manage navigation between directories and view mode switching, keeping view controllers focused on presentation.

### Key Classes

| Class                        | Role                                                        |
|------------------------------|-------------------------------------------------------------|
| `AppDelegate`                | App lifecycle, main menu bar setup                          |
| `MainWindowController`       | `NSWindowController` — owns the window, toolbar, split view |
| `NavigationCoordinator`      | Manages directory navigation stack, back/forward/up         |
| `SidebarViewController`      | `NSOutlineView`-based favorites/places sidebar              |
| `ContentViewController`      | Container that swaps between List/Grid/Column child VCs     |
| `ListViewController`         | `NSTableView` with data source — the workhorse view         |
| `GridViewController`         | `NSCollectionView` with flow layout                         |
| `ColumnViewController`       | Wraps `NSBrowser` for Miller columns                        |
| `PathBarViewController`      | Breadcrumb path bar below toolbar                           |
| `StatusBarViewController`    | Item count, selection info, disk space                      |
| `FileSystemManager`          | All file operations: enumerate, move, copy, delete, rename  |
| `ClipboardManager`           | Custom cut/copy/paste state machine                         |
| `FavoritesManager`           | Load/save/add/remove favorites, security-scoped bookmarks   |
| `ThumbnailCache`             | `NSCache`-backed async thumbnail loader                     |
| `FileItem`                   | Model: URL, name, size, dateModified, kind, isDirectory     |
| `SortDescriptor`             | Current sort field + ascending/descending                   |
| `PreferencesManager`         | UserDefaults wrapper for all settings                       |

### Data Flow (ASCII)

```
┌─────────────────────────────────────────────────────────────────────┐
│                        MainWindowController                         │
│  ┌─────────────┐  ┌──────────────────────────────────────────────┐  │
│  │  NSToolbar   │  │              NSSplitView                    │  │
│  │ [←][→][↑]   │  │  ┌────────────┐  ┌───────────────────────┐  │  │
│  │ [ViewMode]   │  │  │  Sidebar   │  │  ContentViewController│  │  │
│  │ [Search]     │  │  │  (Source   │  │  ┌─────────────────┐  │  │  │
│  └─────────────┘  │  │   List)    │  │  │ ListVC / GridVC │  │  │  │
│  ┌─────────────┐  │  │            │  │  │  / ColumnVC     │  │  │  │
│  │  PathBar     │  │  │  Favorites │  │  └─────────────────┘  │  │  │
│  │ / > Users >  │  │  │  Volumes  │  │  ┌─────────────────┐  │  │  │
│  │   ehamai     │  │  │  Network  │  │  │   StatusBar     │  │  │  │
│  └─────────────┘  │  └────────────┘  └───────────────────────┘  │  │
│                    └──────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘

  User Action                    Data Flow
  ───────────                    ─────────
  Click folder     ──►  NavigationCoordinator.navigate(to: url)
                         │
                         ├──► FileSystemManager.enumerate(url)
                         │     │  (background DispatchQueue)
                         │     └──► returns [FileItem]
                         │
                         ├──► ContentViewController.reload(items:)
                         │     │
                         │     ├──► ListVC.reloadData()      (NSTableView)
                         │     ├──► GridVC.reloadData()       (NSCollectionView)
                         │     └──► ColumnVC.reloadColumn()   (NSBrowser)
                         │
                         ├──► PathBarViewController.update(url)
                         └──► StatusBarViewController.update(count:)
```

---

## 4. Core Features Implementation

### 4.1 "Up" Button — Parent Directory Navigation

**User Perspective:** An always-visible toolbar button (with a ↑ arrow icon) that navigates to the parent folder. Disabled only at the root volume level. Keyboard shortcut: **Cmd+↑** (matches Finder convention).

**AppKit Classes:**
- `NSToolbar` with `NSToolbarItem` for the Up button
- `NSToolbarItem.Identifier.upButton` (custom identifier)
- System symbol image: `NSImage(systemSymbolName: "chevron.up", accessibilityDescription: "Up")`

**Implementation:**

```swift
// MARK: - NSToolbarDelegate (in MainWindowController)

extension MainWindowController: NSToolbarDelegate {

    static let upButtonIdentifier = NSToolbarItem.Identifier("UpButton")
    static let backForwardIdentifier = NSToolbarItem.Identifier("BackForward")
    static let viewModeIdentifier = NSToolbarItem.Identifier("ViewMode")
    static let searchIdentifier = NSToolbarItem.Identifier("Search")
    static let pathBarIdentifier = NSToolbarItem.Identifier("PathBar")

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [
            Self.backForwardIdentifier,
            Self.upButtonIdentifier,
            Self.pathBarIdentifier,
            .flexibleSpace,
            Self.viewModeIdentifier,
            Self.searchIdentifier
        ]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return toolbarAllowedItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar,
                 itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {

        switch itemIdentifier {
        case Self.upButtonIdentifier:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            let button = NSButton(
                image: NSImage(systemSymbolName: "chevron.up",
                               accessibilityDescription: "Go to parent folder")!,
                target: self,
                action: #selector(navigateUp(_:))
            )
            button.bezelStyle = .texturedRounded
            item.view = button
            item.label = "Up"
            item.toolTip = "Go to enclosing folder (⌘↑)"
            return item

        case Self.viewModeIdentifier:
            let group = NSToolbarItemGroup(
                itemIdentifier: itemIdentifier,
                images: [
                    NSImage(systemSymbolName: "list.bullet", accessibilityDescription: "List")!,
                    NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "Grid")!,
                    NSImage(systemSymbolName: "rectangle.grid.1x2", accessibilityDescription: "Columns")!
                ],
                selectionMode: .selectOne,
                labels: ["List", "Icons", "Columns"],
                target: self,
                action: #selector(changeViewMode(_:))
            )
            group.selectedIndex = 0
            return group

        // ... other items
        default:
            return nil
        }
    }

    @objc func navigateUp(_ sender: Any?) {
        coordinator.navigateToParent()
    }
}
```

**Navigation Coordinator:**

```swift
class NavigationCoordinator {
    private var currentURL: URL
    private var backStack: [URL] = []
    private var forwardStack: [URL] = []

    var canGoUp: Bool {
        // Can go up if we're not at a volume root
        return currentURL.pathComponents.count > 1
    }

    func navigateToParent() {
        guard canGoUp else { return }
        let parent = currentURL.deletingLastPathComponent()
        navigate(to: parent)
    }

    func navigate(to url: URL) {
        backStack.append(currentURL)
        forwardStack.removeAll()
        currentURL = url
        delegate?.coordinatorDidNavigate(to: url)
    }

    func goBack() {
        guard let previous = backStack.popLast() else { return }
        forwardStack.append(currentURL)
        currentURL = previous
        delegate?.coordinatorDidNavigate(to: currentURL)
    }

    func goForward() {
        guard let next = forwardStack.popLast() else { return }
        backStack.append(currentURL)
        currentURL = next
        delegate?.coordinatorDidNavigate(to: currentURL)
    }
}
```

**Keyboard shortcut:** `Cmd+↑` is bound via the main menu's "Go" menu item with `keyEquivalent: String(Character(UnicodeScalar(NSUpArrowFunctionKey)!))` and `keyEquivalentModifierMask: .command`.

---

### 4.2 Cut/Paste to Move Files

**User Perspective:** Select files → Cmd+X (or right-click → Cut). Navigate to destination → Cmd+V (or right-click → Paste). Files are **moved**, not copied. Visual feedback: cut files appear dimmed (50% opacity) in the source directory until the paste completes. If the user copies (Cmd+C) after cutting, the cut state is cleared and replaced with a copy operation.

**Why This Needs Custom Logic:** macOS's `NSPasteboard` supports file URLs via `NSPasteboard.PasteboardType.fileURL`, but there is no native "cut" state for files — the pasteboard only knows about copy. We must maintain an internal `ClipboardManager` that tracks whether the current clipboard operation is a cut or copy.

**Key Classes:**
- `ClipboardManager` — singleton managing cut/copy/paste state
- `NSPasteboard.general` — for file URLs on the system pasteboard
- `FileSystemManager` — performs the actual `FileManager.default.moveItem` / `copyItem`

**ClipboardManager Implementation:**

```swift
enum ClipboardOperation {
    case none
    case copy
    case cut
}

class ClipboardManager {
    static let shared = ClipboardManager()

    private(set) var operation: ClipboardOperation = .none
    private(set) var sourceURLs: [URL] = []

    // Posted when cut state changes so views can dim cut items
    static let clipboardDidChange = Notification.Name("ClipboardDidChange")

    func cut(urls: [URL]) {
        sourceURLs = urls
        operation = .cut
        writeURLsToPasteboard(urls)
        NotificationCenter.default.post(name: Self.clipboardDidChange, object: self)
    }

    func copy(urls: [URL]) {
        sourceURLs = urls
        operation = .copy
        writeURLsToPasteboard(urls)
        NotificationCenter.default.post(name: Self.clipboardDidChange, object: self)
    }

    func paste(to destinationDirectory: URL,
               completion: @escaping (Result<[URL], Error>) -> Void) {
        guard !sourceURLs.isEmpty else {
            completion(.failure(ClipboardError.nothingToPaste))
            return
        }

        let op = operation
        let urls = sourceURLs

        // Clear cut state immediately (one-shot operation)
        if op == .cut {
            clearCut()
        }

        DispatchQueue.global(qos: .userInitiated).async {
            var resultURLs: [URL] = []
            var firstError: Error?

            for sourceURL in urls {
                let destURL = destinationDirectory
                    .appendingPathComponent(sourceURL.lastPathComponent)

                do {
                    let finalURL = try self.uniqueDestination(destURL)
                    switch op {
                    case .cut:
                        try FileManager.default.moveItem(at: sourceURL, to: finalURL)
                    case .copy:
                        try FileManager.default.copyItem(at: sourceURL, to: finalURL)
                    case .none:
                        break
                    }
                    resultURLs.append(finalURL)
                } catch {
                    if firstError == nil { firstError = error }
                }
            }

            DispatchQueue.main.async {
                if let error = firstError {
                    completion(.failure(error))
                } else {
                    completion(.success(resultURLs))
                }
            }
        }
    }

    func isCut(url: URL) -> Bool {
        return operation == .cut && sourceURLs.contains(url)
    }

    func clearCut() {
        operation = .none
        sourceURLs = []
        NotificationCenter.default.post(name: Self.clipboardDidChange, object: self)
    }

    // MARK: - Private

    private func writeURLsToPasteboard(_ urls: [URL]) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(urls as [NSPasteboardWriting])
    }

    /// If a file with the same name exists, append " (2)", " (3)", etc.
    private func uniqueDestination(_ url: URL) throws -> URL {
        var candidate = url
        var counter = 2
        let fm = FileManager.default
        let ext = url.pathExtension
        let baseName = url.deletingPathExtension().lastPathComponent
        let parent = url.deletingLastPathComponent()

        while fm.fileExists(atPath: candidate.path) {
            let newName = ext.isEmpty
                ? "\(baseName) (\(counter))"
                : "\(baseName) (\(counter)).\(ext)"
            candidate = parent.appendingPathComponent(newName)
            counter += 1
        }
        return candidate
    }
}
```

**Context Menu (Right-Click):**

```swift
// In ListViewController / GridViewController
override func menuForEvent(_ event: NSEvent) -> NSMenu? {  // or via delegate
    let menu = NSMenu()

    let cutItem = NSMenuItem(title: "Cut", action: #selector(cutFiles(_:)),
                             keyEquivalent: "x")
    let copyItem = NSMenuItem(title: "Copy", action: #selector(copyFiles(_:)),
                              keyEquivalent: "c")
    let pasteItem = NSMenuItem(title: "Paste", action: #selector(pasteFiles(_:)),
                               keyEquivalent: "v")

    pasteItem.isEnabled = ClipboardManager.shared.operation != .none

    menu.addItem(cutItem)
    menu.addItem(copyItem)
    menu.addItem(pasteItem)
    menu.addItem(.separator())
    menu.addItem(NSMenuItem(title: "Delete", action: #selector(deleteFiles(_:)),
                            keyEquivalent: "\u{8}")) // backspace
    menu.addItem(NSMenuItem(title: "Rename…", action: #selector(renameFile(_:)),
                            keyEquivalent: "\r")) // Enter key

    return menu
}
```

**Visual Dimming for Cut Files:**

```swift
// In NSTableViewDelegate
func tableView(_ tableView: NSTableView,
               viewFor tableColumn: NSTableColumn?,
               row: Int) -> NSView? {
    let item = sortedItems[row]
    let cellView = tableView.makeView(withIdentifier: cellID,
                                       owner: self) as! FileTableCellView

    cellView.configure(with: item)

    // Dim cut files
    cellView.alphaValue = ClipboardManager.shared.isCut(url: item.url) ? 0.45 : 1.0

    return cellView
}
```

**Keyboard shortcuts (via main menu + First Responder chain):**
| Action | Shortcut | Menu |
|--------|----------|------|
| Cut    | ⌘X       | Edit → Cut |
| Copy   | ⌘C       | Edit → Copy |
| Paste  | ⌘V       | Edit → Paste |

The `cut:`, `copy:`, `paste:` selectors are wired through the responder chain. The content view controllers implement these methods to call `ClipboardManager`.

---

### 4.3 Favorites Sidebar

**User Perspective:** A left-side panel (source list style) showing two sections: **"Favorites"** (user-pinned folders) and **"Locations"** (volumes/drives). Users can drag any folder from the content area into Favorites to pin it. Right-click a favorite → "Remove from Sidebar" to unpin. Favorites are persisted across app launches.

**AppKit Classes:**
- `NSOutlineView` with source list style (`style = .sourceList`)
- `NSVisualEffectView` as the sidebar background (automatic vibrancy)
- `NSSplitViewController` / `NSSplitView` for sidebar + content split
- `NSOutlineViewDataSource` for drag-and-drop support
- `NSOutlineViewDelegate` for cell configuration

**Data Model:**

```swift
struct FavoriteItem: Codable, Equatable {
    let name: String
    let bookmarkData: Data  // Security-scoped bookmark
    var resolvedURL: URL? {
        var isStale = false
        return try? URL(resolvingBookmarkData: bookmarkData,
                        options: .withSecurityScope,
                        bookmarkDataIsStale: &isStale)
    }
}

enum SidebarSection: String, CaseIterable {
    case favorites = "Favorites"
    case locations = "Locations"
}

class SidebarItem {
    let title: String
    let icon: NSImage?
    let url: URL?
    let isHeader: Bool
    var children: [SidebarItem]

    // Header items
    static func header(_ section: SidebarSection) -> SidebarItem { ... }
    // Leaf items
    static func favorite(_ fav: FavoriteItem) -> SidebarItem { ... }
    static func volume(_ url: URL) -> SidebarItem { ... }
}
```

**FavoritesManager:**

```swift
class FavoritesManager {
    static let shared = FavoritesManager()
    private let storageURL: URL  // ~/Library/Application Support/Explorer/favorites.json

    private(set) var favorites: [FavoriteItem] = []

    func addFavorite(url: URL) throws {
        let bookmarkData = try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        let item = FavoriteItem(name: url.lastPathComponent,
                                bookmarkData: bookmarkData)
        favorites.append(item)
        save()
    }

    func removeFavorite(at index: Int) {
        favorites.remove(at: index)
        save()
    }

    func moveFavorite(from: Int, to: Int) {
        let item = favorites.remove(at: from)
        favorites.insert(item, at: to)
        save()
    }

    private func save() {
        let data = try? JSONEncoder().encode(favorites)
        try? data?.write(to: storageURL)
    }

    func load() {
        guard let data = try? Data(contentsOf: storageURL),
              let items = try? JSONDecoder().decode([FavoriteItem].self, from: data)
        else { return }
        favorites = items
    }
}
```

**Drag-and-Drop to Add Favorites:**

```swift
// SidebarViewController: NSOutlineViewDataSource
func outlineView(_ outlineView: NSOutlineView,
                 validateDrop info: NSDraggingInfo,
                 proposedItem item: Any?,
                 proposedChildIndex index: Int) -> NSDragOperation {
    // Accept folder drops onto the Favorites section
    guard let urls = info.draggingPasteboard.readObjects(
        forClasses: [NSURL.self],
        options: [.urlReadingFileURLsOnly: true]
    ) as? [URL] else {
        return []
    }

    let allFolders = urls.allSatisfy { url in
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }

    return allFolders ? .link : []
}

func outlineView(_ outlineView: NSOutlineView,
                 acceptDrop info: NSDraggingInfo,
                 item: Any?,
                 childIndex index: Int) -> Bool {
    guard let urls = info.draggingPasteboard.readObjects(
        forClasses: [NSURL.self],
        options: [.urlReadingFileURLsOnly: true]
    ) as? [URL] else {
        return false
    }

    for url in urls {
        try? FavoritesManager.shared.addFavorite(url: url)
    }
    outlineView.reloadData()
    return true
}
```

**Right-Click to Remove:**

```swift
@objc func removeFavorite(_ sender: NSMenuItem) {
    let row = outlineView.clickedRow
    guard row >= 0,
          let item = outlineView.item(atRow: row) as? SidebarItem,
          let index = findFavoriteIndex(for: item) else { return }

    FavoritesManager.shared.removeFavorite(at: index)
    outlineView.reloadData()
}
```

---

### 4.4 Multiple View Modes

**Three view modes:** List, Icon/Grid, Column. Switched via toolbar segmented control or View menu (⌘1, ⌘2, ⌘3).

#### 4.4.1 List View — `ListViewController`

The primary view. Uses `NSTableView` with the **data source pattern** (not bindings/array controller).

**Columns:** Name, Date Modified, Size, Kind

```swift
class ListViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    @IBOutlet weak var tableView: NSTableView!  // or programmatic
    @IBOutlet weak var scrollView: NSScrollView!

    var items: [FileItem] = []
    var sortedItems: [FileItem] = []  // items after sort applied
    var sortDescriptor: SortDescriptor = .init(field: .name, ascending: true)

    // MARK: - NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int {
        return sortedItems.count
    }

    // MARK: - NSTableViewDelegate (view-based)

    func tableView(_ tableView: NSTableView,
                   viewFor tableColumn: NSTableColumn?,
                   row: Int) -> NSView? {
        let item = sortedItems[row]

        guard let column = tableColumn else { return nil }

        let cellView: NSTableCellView

        switch column.identifier {
        case .nameColumn:
            let cell = tableView.makeView(
                withIdentifier: .nameCellID, owner: self
            ) as? FileNameCellView ?? FileNameCellView()
            cell.textField?.stringValue = item.name
            cell.imageView?.image = item.icon
            cellView = cell

        case .dateColumn:
            let cell = tableView.makeView(
                withIdentifier: .dateCellID, owner: self
            ) as? NSTableCellView ?? NSTableCellView()
            cell.textField?.stringValue = item.formattedDateModified
            cellView = cell

        case .sizeColumn:
            let cell = tableView.makeView(
                withIdentifier: .sizeCellID, owner: self
            ) as? NSTableCellView ?? NSTableCellView()
            cell.textField?.stringValue = item.isDirectory ? "--" : item.formattedSize
            cellView = cell

        case .kindColumn:
            let cell = tableView.makeView(
                withIdentifier: .kindCellID, owner: self
            ) as? NSTableCellView ?? NSTableCellView()
            cell.textField?.stringValue = item.kind
            cellView = cell

        default:
            return nil
        }

        return cellView
    }
}
```

#### 4.4.2 Icon/Grid View — `GridViewController`

Uses `NSCollectionView` with `NSCollectionViewFlowLayout`.

```swift
class GridViewController: NSViewController,
                           NSCollectionViewDataSource,
                           NSCollectionViewDelegate {
    var collectionView: NSCollectionView!
    var items: [FileItem] = []

    func setupCollectionView() {
        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = NSSize(width: 100, height: 100)
        layout.minimumInteritemSpacing = 10
        layout.minimumLineSpacing = 10
        layout.sectionInset = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)

        collectionView.collectionViewLayout = layout
        collectionView.register(
            FileGridItem.self,
            forItemWithIdentifier: .fileGridItemID
        )
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = true
    }

    // MARK: - NSCollectionViewDataSource

    func collectionView(_ collectionView: NSCollectionView,
                        numberOfItemsInSection section: Int) -> Int {
        return items.count
    }

    func collectionView(_ collectionView: NSCollectionView,
                        itemForRepresentedObjectAt indexPath: IndexPath
    ) -> NSCollectionViewItem {
        let item = collectionView.makeItem(
            withIdentifier: .fileGridItemID, for: indexPath
        ) as! FileGridItem
        item.configure(with: items[indexPath.item])
        return item
    }
}
```

#### 4.4.3 Column View — `ColumnViewController`

Wraps `NSBrowser` (the same control Finder's column view uses).

```swift
class ColumnViewController: NSViewController, NSBrowserDelegate {
    var browser: NSBrowser!
    private var columnItems: [[FileItem]] = []  // items per column

    func setupBrowser() {
        browser = NSBrowser()
        browser.delegate = self
        browser.setCellClass(NSBrowserCell.self)
        browser.allowsMultipleSelection = true
        browser.separatesColumns = true
    }

    func browser(_ browser: NSBrowser, numberOfRowsInColumn column: Int) -> Int {
        return columnItems[safe: column]?.count ?? 0
    }

    func browser(_ browser: NSBrowser,
                 willDisplayCell cell: Any,
                 atRow row: Int,
                 column: Int) {
        guard let browserCell = cell as? NSBrowserCell,
              let item = columnItems[safe: column]?[safe: row] else { return }
        browserCell.stringValue = item.name
        browserCell.image = item.icon
        browserCell.isLeaf = !item.isDirectory
    }
}
```

**View Mode Switching in ContentViewController:**

```swift
class ContentViewController: NSViewController {
    enum ViewMode: Int {
        case list = 0
        case grid = 1
        case column = 2
    }

    var currentMode: ViewMode = .list {
        didSet { switchToMode(currentMode) }
    }

    private lazy var listVC = ListViewController()
    private lazy var gridVC = GridViewController()
    private lazy var columnVC = ColumnViewController()

    private var activeChild: NSViewController?

    func switchToMode(_ mode: ViewMode) {
        activeChild?.view.removeFromSuperview()
        activeChild?.removeFromParent()

        let newChild: NSViewController
        switch mode {
        case .list:   newChild = listVC
        case .grid:   newChild = gridVC
        case .column: newChild = columnVC
        }

        addChild(newChild)
        newChild.view.frame = view.bounds
        newChild.view.autoresizingMask = [.width, .height]
        view.addSubview(newChild.view)
        activeChild = newChild

        // Pass current items to the new child
        reloadActiveView()
    }
}
```

---

### 4.5 Sorting

**User Perspective:** Click any column header in List view to sort by that column. Click again to toggle ascending/descending. A small arrow indicator shows current sort direction. Sorting also applies in Grid and Column views (though no visible column headers).

**Implementation:**

```swift
enum SortField: String, CaseIterable {
    case name, dateModified, size, kind
}

struct SortDescriptor {
    var field: SortField
    var ascending: Bool

    var comparator: (FileItem, FileItem) -> Bool {
        let result: (FileItem, FileItem) -> Bool
        switch field {
        case .name:
            result = { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .dateModified:
            result = { $0.dateModified < $1.dateModified }
        case .size:
            result = { $0.size < $1.size }
        case .kind:
            result = { $0.kind.localizedStandardCompare($1.kind) == .orderedAscending }
        }
        return ascending ? result : { a, b in result(b, a) }
    }
}
```

**Column Header Click Handling:**

```swift
// NSTableViewDelegate
func tableView(_ tableView: NSTableView,
               didClick tableColumn: NSTableColumn) {
    let field: SortField
    switch tableColumn.identifier {
    case .nameColumn: field = .name
    case .dateColumn: field = .dateModified
    case .sizeColumn: field = .size
    case .kindColumn: field = .kind
    default: return
    }

    // Toggle direction if same column, otherwise ascending
    if sortDescriptor.field == field {
        sortDescriptor.ascending.toggle()
    } else {
        sortDescriptor = SortDescriptor(field: field, ascending: true)
    }

    // Update sort indicator
    for col in tableView.tableColumns {
        tableView.setIndicatorImage(nil, in: col)
    }
    let indicatorImage = sortDescriptor.ascending
        ? NSImage(systemSymbolName: "chevron.up", accessibilityDescription: nil)
        : NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)
    tableView.setIndicatorImage(indicatorImage, in: tableColumn)

    // Sort items and reload
    applySortAndReload()
}

func applySortAndReload() {
    // Directories first, then sort within each group
    let dirs = items.filter { $0.isDirectory }.sorted(by: sortDescriptor.comparator)
    let files = items.filter { !$0.isDirectory }.sorted(by: sortDescriptor.comparator)
    sortedItems = dirs + files

    tableView.reloadData()
}
```

**Keyboard shortcut in View menu:**
| Shortcut | Action              |
|----------|---------------------|
| (none)   | View → Sort By → Name / Date / Size / Kind (radio group) |

---

### 4.6 Performance Optimization (100k+ Files)

**User Perspective:** Opening a directory with 100,000+ files should not freeze the UI. Items appear progressively. Scrolling is butter-smooth at 60fps. Memory usage stays bounded.

**Key strategies detailed below in Section 5.**

**Data Model — Lightweight `FileItem`:**

```swift
struct FileItem {
    let url: URL
    let name: String
    let dateModified: Date
    let size: Int64
    let kind: String
    let isDirectory: Bool
    let isHidden: Bool

    // Lazy-loaded, cached separately
    // icon and thumbnail are NOT stored here
}
```

This struct is ~120 bytes. 100k items ≈ 12 MB — very manageable.

---

### 4.7 Finder-Like Look and Feel

**NSVisualEffectView for Vibrancy:**

```swift
// In SidebarViewController.loadView()
let visualEffectView = NSVisualEffectView()
visualEffectView.material = .sidebar  // or .headerView, .contentBackground
visualEffectView.blendingMode = .behindWindow
visualEffectView.state = .followsWindowActiveState
view = visualEffectView
```

**Source List Style:**

```swift
outlineView.style = .sourceList
// This automatically gives:
// - Rounded selection highlights
// - Proper text colors for vibrancy
// - System-standard row heights
// - Header row styling for group items
```

**Window Configuration:**

```swift
class MainWindowController: NSWindowController {
    override func windowDidLoad() {
        super.windowDidLoad()

        window?.titleVisibility = .hidden
        window?.titlebarAppearsTransparent = false
        window?.toolbarStyle = .unified  // Modern unified toolbar

        // Full-size content for sidebar vibrancy
        window?.styleMask.insert(.fullSizeContentView)

        // Minimum window size
        window?.minSize = NSSize(width: 700, height: 450)
    }
}
```

**Dark Mode:** Fully automatic with AppKit. No special code needed — system colors (`NSColor.controlBackgroundColor`, `NSColor.textColor`, etc.) adapt automatically. The `NSVisualEffectView` materials also adapt.

**NSSplitViewController for Sidebar:**

```swift
class MainSplitViewController: NSSplitViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarVC)
        sidebarItem.minimumThickness = 150
        sidebarItem.maximumThickness = 300
        sidebarItem.canCollapse = true
        sidebarItem.holdingPriority = .defaultLow + 1

        let contentItem = NSSplitViewItem(viewController: contentVC)
        contentItem.minimumThickness = 400

        addSplitViewItem(sidebarItem)
        addSplitViewItem(contentItem)
    }
}
```

---

## 5. Performance Strategy

### Why AppKit Is Fastest for This Use Case

| Aspect | AppKit Advantage |
|--------|-----------------|
| **Cell Recycling** | `NSTableView.makeView(withIdentifier:owner:)` reuses cell views. Only visible rows have live views. 100k rows → ~30 views in memory. |
| **Data Source Pattern** | `numberOfRows` + `viewFor row:` = pull model. The table asks for data only when it needs it. No large array of view objects. |
| **No Diffing Overhead** | Unlike SwiftUI's diffing engine, AppKit calls `reloadData()` and recreates only visible cells. No O(n) identity comparison. |
| **Core Animation Layers** | `NSTableView` can be layer-backed (`wantsLayer = true`) for GPU-accelerated scrolling. |
| **NSCollectionView Prefetching** | `NSCollectionViewPrefetching` protocol for pre-loading thumbnails before cells scroll into view. |

### Background Enumeration

```swift
class FileSystemManager {
    private let enumerationQueue = DispatchQueue(
        label: "com.explorer.enumeration",
        qos: .userInitiated
    )
    private var currentWork: DispatchWorkItem?

    func enumerate(directory url: URL,
                   showHidden: Bool = false,
                   progress: @escaping ([FileItem]) -> Void,
                   completion: @escaping ([FileItem]) -> Void) {
        // Cancel any in-flight enumeration
        currentWork?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            let keys: [URLResourceKey] = [
                .nameKey, .fileSizeKey, .contentModificationDateKey,
                .localizedTypeDescriptionKey, .isDirectoryKey, .isHiddenKey
            ]

            let options: FileManager.DirectoryEnumerationOptions =
                showHidden ? [] : [.skipsHiddenFiles]

            guard let enumerator = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: keys,
                options: options.union([.skipsSubdirectoryDescendants])
            ) else {
                DispatchQueue.main.async { completion([]) }
                return
            }

            var items: [FileItem] = []
            var batch: [FileItem] = []
            let batchSize = 500

            for case let fileURL as URL in enumerator {
                // Check for cancellation
                if (self?.currentWork?.isCancelled ?? true) { return }

                guard let values = try? fileURL.resourceValues(forKeys: Set(keys)) else {
                    continue
                }

                let item = FileItem(
                    url: fileURL,
                    name: values.name ?? fileURL.lastPathComponent,
                    dateModified: values.contentModificationDate ?? Date.distantPast,
                    size: Int64(values.fileSize ?? 0),
                    kind: values.localizedTypeDescription ?? "Unknown",
                    isDirectory: values.isDirectory ?? false,
                    isHidden: values.isHidden ?? false
                )

                items.append(item)
                batch.append(item)

                // Progressive loading: deliver batches to UI
                if batch.count >= batchSize {
                    let snapshot = items  // value type, safe to capture
                    DispatchQueue.main.async { progress(snapshot) }
                    batch.removeAll(keepingCapacity: true)
                }
            }

            let finalItems = items
            DispatchQueue.main.async { completion(finalItems) }
        }

        currentWork = workItem
        enumerationQueue.async(execute: workItem)
    }
}
```

### Thumbnail Caching

```swift
class ThumbnailCache {
    static let shared = ThumbnailCache()

    private let cache = NSCache<NSURL, NSImage>()
    private let thumbnailQueue = DispatchQueue(
        label: "com.explorer.thumbnails",
        qos: .utility,
        attributes: .concurrent
    )

    init() {
        cache.countLimit = 5000  // Keep at most 5k thumbnails
        cache.totalCostLimit = 100 * 1024 * 1024  // 100 MB
    }

    func thumbnail(for url: URL,
                   size: CGSize,
                   completion: @escaping (NSImage?) -> Void) {
        if let cached = cache.object(forKey: url as NSURL) {
            completion(cached)
            return
        }

        thumbnailQueue.async {
            let request = QLThumbnailGenerator.Request(
                fileAt: url,
                size: size,
                scale: NSScreen.main?.backingScaleFactor ?? 2.0,
                representationTypes: .thumbnail
            )

            QLThumbnailGenerator.shared.generateBestRepresentation(
                for: request
            ) { [weak self] representation, error in
                let image = representation?.nsImage
                if let image = image {
                    self?.cache.setObject(image, forKey: url as NSURL,
                                          cost: Int(size.width * size.height * 4))
                }
                DispatchQueue.main.async { completion(image) }
            }
        }
    }

    func invalidate(url: URL) {
        cache.removeObject(forKey: url as NSURL)
    }
}
```

### NSCollectionView Prefetching

```swift
extension GridViewController: NSCollectionViewPrefetching {
    func collectionView(_ collectionView: NSCollectionView,
                        prefetchItemsAt indexPaths: [IndexPath]) {
        for indexPath in indexPaths {
            let item = items[indexPath.item]
            ThumbnailCache.shared.thumbnail(for: item.url,
                                             size: CGSize(width: 64, height: 64)) { _ in }
        }
    }

    func collectionView(_ collectionView: NSCollectionView,
                        cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
        // Cancel thumbnail generation for scrolled-past items (if using Operation-based approach)
    }
}
```

### Additional Performance Measures

| Technique | Detail |
|-----------|--------|
| **Cancellable enumeration** | `DispatchWorkItem.cancel()` aborts directory reads when user navigates away |
| **String sorting** | `localizedStandardCompare` for Finder-like ordering (numeric-aware) |
| **Icon reuse** | `NSWorkspace.shared.icon(forFile:)` is fast and internally cached by the system |
| **Batch `reloadData()`** | When receiving progressive batches, coalesce reloads with a 100ms debounce timer |
| **Avoid `reloadData()` for single changes** | Use `insertRows(at:)` / `removeRows(at:)` for file system events |
| **Memory** | `FileItem` is a struct (value type). No ARC overhead per item. |
| **No KVO / Bindings** | Direct data source avoids KVO observation overhead on 100k objects |

---

## 6. File System Operations

### Operation Matrix

| Operation | Shortcut | Method | Notes |
|-----------|----------|--------|-------|
| Cut       | ⌘X       | `ClipboardManager.cut(urls:)` | Stores URLs + sets cut flag |
| Copy      | ⌘C       | `ClipboardManager.copy(urls:)` | Stores URLs, clears cut flag |
| Paste     | ⌘V       | `ClipboardManager.paste(to:)` | Moves (if cut) or copies (if copy) |
| Delete    | ⌘⌫       | `FileManager.trashItem(at:)` | Move to Trash (recoverable) |
| Perm. Delete | ⌥⌘⌫  | `FileManager.removeItem(at:)` | With confirmation alert |
| Rename    | Enter    | Inline `NSTextField` editing | `NSTableView` cell editing |
| New Folder | ⇧⌘N    | `FileManager.createDirectory` | Creates "untitled folder" |
| Open      | ⌘O       | `NSWorkspace.shared.open(url)` | Opens file in default app |
| Show Info  | ⌘I      | Custom inspector panel | File metadata |

### File Coordination

For safe file operations, especially when files might be open in other apps:

```swift
func moveItem(from source: URL, to destination: URL) throws {
    let coordinator = NSFileCoordinator()
    var coordinatorError: NSError?

    coordinator.coordinate(
        writingItemAt: source, options: .forMoving,
        writingItemAt: destination, options: .forReplacing,
        error: &coordinatorError
    ) { newSource, newDestination in
        do {
            try FileManager.default.moveItem(at: newSource, to: newDestination)
        } catch {
            // Handle error
        }
    }

    if let error = coordinatorError {
        throw error
    }
}
```

### Directory Monitoring

```swift
class DirectoryMonitor {
    private var source: DispatchSourceFileSystemObject?
    private let fileDescriptor: Int32

    init(url: URL) {
        fileDescriptor = open(url.path, O_EVTONLY)
    }

    func startMonitoring(onChange: @escaping () -> Void) {
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .delete, .rename, .attrib],
            queue: DispatchQueue.main
        )

        source.setEventHandler {
            onChange()  // Trigger re-enumeration
        }

        source.setCancelHandler { [weak self] in
            if let fd = self?.fileDescriptor { close(fd) }
        }

        source.resume()
        self.source = source
    }

    func stopMonitoring() {
        source?.cancel()
        source = nil
    }

    deinit {
        stopMonitoring()
    }
}
```

---

## 7. Persistence

### What Is Persisted

| Data | Storage | Format |
|------|---------|--------|
| Favorites list | `~/Library/Application Support/Explorer/favorites.json` | JSON array of `FavoriteItem` with security-scoped bookmark data |
| Window frame | `UserDefaults` | `NSWindow.setFrameAutosaveName("MainWindow")` — automatic |
| Sidebar width | `NSSplitView` autosave | `splitView.autosaveName = "MainSplit"` — automatic |
| Last viewed directory | `UserDefaults` | URL string |
| View mode preference | `UserDefaults` | Int (0=list, 1=grid, 2=column) |
| Sort preference | `UserDefaults` | Encoded `SortDescriptor` |
| Show hidden files | `UserDefaults` | Bool |

### Security-Scoped Bookmarks

Essential for sandbox compliance. When the user adds a favorite, we create a security-scoped bookmark so the app can access that location in future launches without re-prompting:

```swift
// Creating a bookmark (when adding a favorite)
let bookmarkData = try url.bookmarkData(
    options: .withSecurityScope,
    includingResourceValuesForKeys: nil,
    relativeTo: nil
)

// Resolving a bookmark (on app launch)
var isStale = false
let resolvedURL = try URL(
    resolvingBookmarkData: bookmarkData,
    options: .withSecurityScope,
    bookmarkDataIsStale: &isStale
)

// Must call startAccessingSecurityScopedResource
guard resolvedURL.startAccessingSecurityScopedResource() else {
    throw BookmarkError.accessDenied
}
// ... use the URL ...
// resolvedURL.stopAccessingSecurityScopedResource()  // when done
```

### Preferences Manager

```swift
class PreferencesManager {
    static let shared = PreferencesManager()

    private let defaults = UserDefaults.standard

    var viewMode: ContentViewController.ViewMode {
        get { ContentViewController.ViewMode(rawValue: defaults.integer(forKey: "viewMode")) ?? .list }
        set { defaults.set(newValue.rawValue, forKey: "viewMode") }
    }

    var showHiddenFiles: Bool {
        get { defaults.bool(forKey: "showHiddenFiles") }
        set { defaults.set(newValue, forKey: "showHiddenFiles") }
    }

    var lastDirectory: URL? {
        get { defaults.url(forKey: "lastDirectory") }
        set { defaults.set(newValue, forKey: "lastDirectory") }
    }

    var sortField: SortField {
        get { SortField(rawValue: defaults.string(forKey: "sortField") ?? "") ?? .name }
        set { defaults.set(newValue.rawValue, forKey: "sortField") }
    }

    var sortAscending: Bool {
        get { defaults.object(forKey: "sortAscending") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "sortAscending") }
    }
}
```

---

## 8. Project Structure

```
Explorer/
├── Explorer.xcodeproj/
├── Explorer/
│   ├── App/
│   │   ├── AppDelegate.swift              # NSApplicationDelegate, main menu
│   │   ├── main.swift                     # (if not using @main)
│   │   └── Info.plist
│   │
│   ├── WindowControllers/
│   │   └── MainWindowController.swift     # NSWindowController, toolbar delegate
│   │
│   ├── ViewControllers/
│   │   ├── MainSplitViewController.swift  # NSSplitViewController root
│   │   ├── SidebarViewController.swift    # NSOutlineView source list
│   │   ├── ContentViewController.swift    # Container, switches view modes
│   │   ├── ListViewController.swift       # NSTableView data source
│   │   ├── GridViewController.swift       # NSCollectionView data source
│   │   ├── ColumnViewController.swift     # NSBrowser delegate
│   │   ├── PathBarViewController.swift    # Breadcrumb path bar
│   │   └── StatusBarViewController.swift  # Item count, selection info
│   │
│   ├── Views/
│   │   ├── FileTableCellView.swift        # Custom NSTableCellView for list rows
│   │   ├── FileGridItem.swift             # NSCollectionViewItem for grid cells
│   │   ├── PathBarButton.swift            # Clickable breadcrumb segment
│   │   └── SidebarRowView.swift           # Custom NSTableRowView for sidebar
│   │
│   ├── Models/
│   │   ├── FileItem.swift                 # Core file data model (struct)
│   │   ├── SidebarItem.swift              # Sidebar data model
│   │   ├── FavoriteItem.swift             # Codable favorite with bookmark data
│   │   └── SortDescriptor.swift           # Sort field + direction
│   │
│   ├── Managers/
│   │   ├── FileSystemManager.swift        # Enumerate, move, copy, delete, rename
│   │   ├── ClipboardManager.swift         # Cut/copy/paste state machine
│   │   ├── FavoritesManager.swift         # Load/save/add/remove favorites
│   │   ├── ThumbnailCache.swift           # NSCache + QLThumbnailGenerator
│   │   ├── DirectoryMonitor.swift         # DispatchSource file system watcher
│   │   ├── PreferencesManager.swift       # UserDefaults wrapper
│   │   └── NavigationCoordinator.swift    # Back/forward/up navigation stack
│   │
│   ├── Extensions/
│   │   ├── URL+Extensions.swift           # Convenience properties
│   │   ├── NSImage+Extensions.swift       # Resizing, template helpers
│   │   ├── FileManager+Extensions.swift   # Safe move/copy wrappers
│   │   ├── ByteCountFormatter+Ext.swift   # Human-readable file sizes
│   │   └── NSUserInterfaceItemIdentifier+Ext.swift  # Column/cell identifiers
│   │
│   ├── Resources/
│   │   ├── Assets.xcassets/               # App icon, accent color
│   │   ├── MainMenu.xib                   # (or programmatic menu)
│   │   └── MainWindow.xib                 # (or programmatic window)
│   │
│   └── Explorer.entitlements              # Sandbox entitlements
│
├── ExplorerTests/
│   ├── FileSystemManagerTests.swift
│   ├── ClipboardManagerTests.swift
│   ├── FavoritesManagerTests.swift
│   ├── SortDescriptorTests.swift
│   └── NavigationCoordinatorTests.swift
│
└── README.md
```

---

## 9. Build & Distribution

### Xcode Project Setup

1. **Create project:** Xcode → New Project → macOS → App → Interface: XIB (or None for fully programmatic), Language: Swift
2. **Deployment target:** macOS 13.0
3. **Signing:** Automatic signing with Apple Developer team
4. **Sandbox:** Enable App Sandbox in Entitlements:
   ```xml
   <key>com.apple.security.app-sandbox</key>
   <true/>
   <key>com.apple.security.files.user-selected.read-write</key>
   <true/>
   <key>com.apple.security.files.bookmarks.app-scope</key>
   <true/>
   ```

### Build Commands

```bash
# Debug build
xcodebuild -project Explorer.xcodeproj \
    -scheme Explorer \
    -configuration Debug \
    build

# Release build
xcodebuild -project Explorer.xcodeproj \
    -scheme Explorer \
    -configuration Release \
    -archivePath build/Explorer.xcarchive \
    archive

# Export for distribution
xcodebuild -exportArchive \
    -archivePath build/Explorer.xcarchive \
    -exportPath build/release \
    -exportOptionsPlist ExportOptions.plist
```

### Notarization

```bash
# Submit for notarization
xcrun notarytool submit build/release/Explorer.app.zip \
    --apple-id "developer@email.com" \
    --team-id "TEAMID" \
    --password "@keychain:AC_PASSWORD" \
    --wait

# Staple the ticket
xcrun stapler staple build/release/Explorer.app
```

### Distribution Options

| Channel | Requirements |
|---------|-------------|
| **Direct (Developer ID)** | Developer ID certificate, notarization, optional DMG/pkg |
| **Mac App Store** | App Store Connect, sandbox compliance, review |
| **TestFlight** | App Store Connect, beta build upload |

---

## 10. Pros & Cons

### Pros

| Advantage | Detail |
|-----------|--------|
| ✅ **Best performance** | NSTableView cell recycling is the gold standard. Handles 100k+ items trivially. |
| ✅ **True native fidelity** | Identical to Finder: vibrancy, source lists, column views, dark mode — all automatic. |
| ✅ **Mature ecosystem** | 20+ years of AppKit. Every edge case is handled. Every control exists. |
| ✅ **NSBrowser** | The only way to get Finder-style column view. SwiftUI has no equivalent. |
| ✅ **Full control** | Direct access to cell lifecycle, scroll position, layer-backed optimization. |
| ✅ **No abstraction overhead** | No SwiftUI diffing, no cross-platform translation, no Electron/web overhead. |
| ✅ **System integration** | Drag-and-drop, Services menu, Quick Look, Spotlight — all via native APIs. |
| ✅ **Accessibility** | NSTableView, NSOutlineView have built-in VoiceOver support. |

### Cons

| Disadvantage | Detail |
|--------------|--------|
| ❌ **Verbose boilerplate** | Delegate/data source pattern requires more code than SwiftUI's declarative approach. |
| ❌ **Manual state management** | No `@State`, `@Binding`, `@Published`. All UI updates are imperative. |
| ❌ **XIB/Storyboard optional complexity** | Interface Builder adds visual design but complicates code review and merging. (Mitigated by going fully programmatic.) |
| ❌ **macOS only** | Cannot reuse any UI code for iOS/iPadOS (though the model/manager layer can be shared). |
| ❌ **Steeper learning curve** | AppKit has historical baggage (`NSCell` vs view-based tables, `NSResponder` chain). Modern developers may be less familiar. |
| ❌ **Less community momentum** | Fewer tutorials, Stack Overflow answers, and blog posts compared to SwiftUI. |
| ❌ **No live previews** | Unlike SwiftUI Previews, AppKit requires building and running to see UI changes. |

### Comparison with Alternatives

| Criteria | AppKit (This Plan) | SwiftUI | Electron/Tauri |
|----------|-------------------|---------|----------------|
| 100k file scroll perf | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐ |
| Native look & feel | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐ |
| Development speed | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ |
| Column view | ⭐⭐⭐⭐⭐ | ❌ | ❌ |
| Code conciseness | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ |
| Cross-platform | ❌ | iOS only | ⭐⭐⭐⭐⭐ |
| Binary size | ~5 MB | ~5 MB | ~30-80 MB |
| Memory usage | Lowest | Low | High |

---

## 11. ASCII Mockup

```
┌──────────────────────────────────────────────────────────────────────────────┐
│ ● ● ●                        Explorer                                       │
├──────────────────────────────────────────────────────────────────────────────┤
│ TOOLBAR                                                                      │
│  [◀ Back] [▶ Fwd] [↑ Up]  │  / Users / ehamai / Documents            │ [≡ List ▪ Grid ⊞ Col]  [🔍 Search ]│
├────────────────────┬─────────────────────────────────────────────────────────┤
│ SIDEBAR            │  CONTENT AREA (List View shown)                         │
│ ═══════════════    │                                                         │
│                    │  Name ▲            Date Modified      Size      Kind     │
│ ▼ FAVORITES        │  ─────────────────────────────────────────────────────── │
│   📁 Documents     │  📁 Applications   2024-12-01 09:15   --        Folder   │
│   📁 Projects      │  📁 Desktop        2025-01-15 14:22   --        Folder   │
│   📁 Downloads     │  📁 Documents      2025-01-14 10:33   --        Folder   │
│   📁 Work          │  📁 Downloads      2025-01-15 16:45   --        Folder   │
│                    │  📄 notes.txt      2025-01-10 08:00   4 KB      Text     │
│ ▼ LOCATIONS        │  📄 photo.jpg      2025-01-12 11:30   2.1 MB    JPEG     │
│   💻 Macintosh HD  │  📄 report.pdf     2025-01-13 09:15   156 KB    PDF      │
│   💿 External SSD  │  📄 script.py      2025-01-14 17:00   8 KB      Python   │
│   ☁️  iCloud Drive  │  📄 video.mp4      2025-01-11 20:00   1.2 GB    Movie    │
│                    │                                                         │
│                    │  ... (scrollable, virtualized — only visible rows        │
│                    │       have live views in memory)                         │
│                    │                                                         │
├────────────────────┴─────────────────────────────────────────────────────────┤
│ STATUS BAR                                                                   │
│  9 items  │  2 selected  │  "report.pdf" — 156 KB  │  45.2 GB available      │
└──────────────────────────────────────────────────────────────────────────────┘


GRID VIEW (when ⊞ selected):
┌────────────────────────────────────────────────────────────────┐
│                                                                │
│   ┌──────┐   ┌──────┐   ┌──────┐   ┌──────┐   ┌──────┐      │
│   │ 📁   │   │ 📁   │   │ 📁   │   │ 📁   │   │ 📄   │      │
│   │      │   │      │   │      │   │      │   │      │      │
│   │ Apps │   │Dsktp │   │ Docs │   │Dwnld │   │notes │      │
│   └──────┘   └──────┘   └──────┘   └──────┘   └──────┘      │
│                                                                │
│   ┌──────┐   ┌──────┐   ┌──────┐   ┌──────┐                  │
│   │ 🖼️   │   │ 📄   │   │ 🐍   │   │ 🎬   │                  │
│   │      │   │      │   │      │   │      │                  │
│   │photo │   │reprt │   │scrpt │   │video │                  │
│   └──────┘   └──────┘   └──────┘   └──────┘                  │
│                                                                │
└────────────────────────────────────────────────────────────────┘


COLUMN VIEW (when ⊞ Col selected):
┌────────────────────────────────────────────────────────────────┐
│  Users       │  ehamai      │  Documents    │  (preview)      │
│  ──────────  │  ──────────  │  ────────── │                 │
│  admin       │▶ Applications│  project.md  │  project.md     │
│▶ ehamai      │▶ Desktop     │▶ Archive     │  ───────────    │
│  guest       │▶ Documents   │  readme.txt  │  Markdown File  │
│  shared      │▶ Downloads   │  spec.pdf    │  4 KB           │
│              │  .zshrc      │              │  Modified: ...  │
│              │  .gitconfig  │              │                 │
└────────────────────────────────────────────────────────────────┘


CONTEXT MENU (right-click on file):
┌──────────────────┐
│  Open             │
│  Open With ▶      │
│  ─────────────── │
│  Cut         ⌘X  │
│  Copy        ⌘C  │
│  Paste       ⌘V  │
│  ─────────────── │
│  Rename…     ↵   │
│  Move to Trash ⌘⌫│
│  ─────────────── │
│  Get Info    ⌘I  │
│  Quick Look  ␣   │
│  ─────────────── │
│  Add to Favorites │
└──────────────────┘
```

---

## Appendix: Complete Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| ⌘↑ | Go to parent folder (Up) |
| ⌘[ or ⌘← | Go back |
| ⌘] or ⌘→ | Go forward |
| ⌘O | Open selected item |
| ⌘↓ | Open folder / Open file |
| ⌘X | Cut |
| ⌘C | Copy |
| ⌘V | Paste |
| ⌘⌫ | Move to Trash |
| ⌥⌘⌫ | Delete permanently |
| ↵ (Enter) | Rename |
| ⇧⌘N | New Folder |
| ⌘1 | List view |
| ⌘2 | Icon/Grid view |
| ⌘3 | Column view |
| ⌘. | Toggle hidden files |
| ⌘I | Get Info |
| Space | Quick Look preview |
| ⌘F | Search / Filter |
| ⌘, | Preferences |
| ⌘T | New tab |
| ⌘W | Close tab/window |
| ⌘A | Select all |
| ⌘⇧. | Toggle hidden files |

---

*This plan provides a complete blueprint for building a high-performance, native macOS file explorer using Swift and AppKit. The architecture prioritizes scroll performance (100k+ items), native fidelity (vibrancy, dark mode, source lists), and user-requested features (Cut/Paste move, Up button, Favorites sidebar, multiple view modes). A developer familiar with AppKit could implement the core feature set in approximately 4–6 weeks.*
