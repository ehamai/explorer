# Windows File Explorer for macOS — Swift + SwiftUI Implementation Plan

## Table of Contents

1. [Technology Stack](#1-technology-stack)
2. [Architecture](#2-architecture)
3. [Key Components / Views](#3-key-components--views)
4. [File System Interaction](#4-file-system-interaction)
5. [Build System](#5-build-system)
6. [Estimated Complexity](#6-estimated-complexity)
7. [Pros and Cons](#7-pros-and-cons)
8. [Apple Silicon Optimization](#8-apple-silicon-optimization)
9. [Timeline Estimate](#9-timeline-estimate)
10. [Risks and Challenges](#10-risks-and-challenges)

---

## 1. Technology Stack

### Core

| Layer | Technology | Purpose |
|---|---|---|
| Language | Swift 5.10+ / Swift 6 | Primary language; strict concurrency when ready |
| UI Framework | SwiftUI (macOS 14+ / Sonoma minimum) | Declarative views, state management, layout |
| AppKit Interop | `NSViewRepresentable` / `NSViewControllerRepresentable` | Tree views (`NSOutlineView`), custom drag-drop, context menus, column-sortable tables |
| File System | `Foundation.FileManager`, `NSURL`, `NSFileCoordinator` | File enumeration, metadata, operations |
| Spotlight Search | `NSMetadataQuery` (Core Services) | Fast indexed search across volumes |
| Thumbnails | QuickLookThumbnailing (`QLThumbnailGenerator`) | File thumbnails/icons in icon & tile views |
| Preview | QuickLook (`QLPreviewPanel` / `QLPreviewView`) | Preview pane rendering for any file type |
| Concurrency | Swift Concurrency (`async/await`, `TaskGroup`, actors) | Background file enumeration, search, copy ops |
| Persistence | `UserDefaults`, `Codable` + JSON files, SwiftData (optional) | Favorites, recent paths, user preferences |
| Undo | `UndoManager` | Undo/redo file operations |
| Security | App Sandbox entitlements + Security-Scoped Bookmarks | File access beyond sandbox container |

### Optional / Supporting

| Library | Purpose |
|---|---|
| `UniformTypeIdentifiers` | Modern UTI-based file type identification |
| `Combine` | Reactive bindings where SwiftUI `@Observable` is insufficient |
| `OSLog` | Structured logging |
| `ServiceManagement` | (If ever needing a helper for privileged operations) |

### Why **not** a third-party dependency?

The plan deliberately avoids third-party packages. Every feature can be built with Apple's frameworks. This eliminates supply-chain risk, keeps the binary small, and avoids version-rot. If we later want a richer tree view or virtual-scroll list we can evaluate packages like `SwiftCollections` (Apple's own) or write a thin wrapper around `NSOutlineView`.

---

## 2. Architecture

### Pattern: MVVM + Coordinator (Navigation)

```
┌─────────────────────────────────────────────────────────┐
│                        App Shell                        │
│  ┌───────────────┐  ┌────────────────────────────────┐  │
│  │  Sidebar VM   │  │         Tab Bar                │  │
│  │  (tree data)  │  │  ┌──────────┐  ┌──────────┐   │  │
│  │               │  │  │  Tab 1   │  │  Tab 2   │   │  │
│  └───────┬───────┘  │  └────┬─────┘  └────┬─────┘   │  │
│          │          │       │              │          │  │
│          ▼          │       ▼              ▼          │  │
│  ┌───────────────┐  │  ┌────────────────────────┐    │  │
│  │  SidebarView  │  │  │  BrowserView           │    │  │
│  │  (NavigationPane)│  │  ┌──────────────────┐  │    │  │
│  │               │  │  │  │  Toolbar / Ribbon │  │    │  │
│  │  • Quick Acc. │  │  │  ├──────────────────┤  │    │  │
│  │  • Favorites  │  │  │  │  Address Bar      │  │    │  │
│  │  • Volumes    │  │  │  ├──────────────────┤  │    │  │
│  │  • Folder Tree│  │  │  │  Content Area     │  │    │  │
│  │               │  │  │  │  (List/Icon/Tile) │  │    │  │
│  │               │  │  │  ├──────────────────┤  │    │  │
│  │               │  │  │  │  Preview Pane     │  │    │  │
│  │               │  │  │  ├──────────────────┤  │    │  │
│  │               │  │  │  │  Status Bar       │  │    │  │
│  └───────────────┘  │  │  └──────────────────┘  │    │  │
│                     │  └────────────────────────┘    │  │
│                     └────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

### Module Breakdown

```
Explorer/
├── App/
│   ├── ExplorerApp.swift              // @main, WindowGroup, commands
│   └── AppState.swift                 // Global state: tabs, preferences
│
├── Models/
│   ├── FileItem.swift                 // Represents a file/folder node
│   ├── Volume.swift                   // Mounted volume info
│   ├── BreadcrumbSegment.swift        // Address bar path segment
│   ├── SidebarNode.swift              // Sidebar tree node (enum: section/folder/volume)
│   └── ViewMode.swift                 // .details, .icons, .tiles enum
│
├── ViewModels/
│   ├── SidebarViewModel.swift         // Folder tree, favorites, volumes
│   ├── BrowserViewModel.swift         // Current directory state, navigation history
│   ├── FileListViewModel.swift        // Content area data, sorting, selection
│   ├── SearchViewModel.swift          // Search queries, results
│   ├── PreviewViewModel.swift         // Preview pane data
│   └── FileOperationsViewModel.swift  // Copy/Move/Delete/Rename with progress
│
├── Views/
│   ├── Shell/
│   │   ├── MainWindow.swift           // Top-level window layout (sidebar + content)
│   │   ├── TabBar.swift               // Browser tabs
│   │   └── StatusBar.swift            // Bottom bar (item count, selection, disk info)
│   │
│   ├── Sidebar/
│   │   ├── SidebarView.swift          // NavigationSplitView sidebar content
│   │   ├── FolderTreeView.swift       // Recursive disclosure group / NSOutlineView
│   │   └── QuickAccessSection.swift   // Favorites / pinned folders
│   │
│   ├── Browser/
│   │   ├── BrowserView.swift          // Container: toolbar + address + content + preview
│   │   ├── AddressBar.swift           // Breadcrumb path bar
│   │   ├── ToolbarView.swift          // Ribbon-like toolbar with segmented buttons
│   │   ├── ContentArea.swift          // Switches between detail/icon/tile sub-views
│   │   ├── DetailsView.swift          // Table with sortable columns
│   │   ├── IconsView.swift            // Grid of file icons/thumbnails
│   │   ├── TilesView.swift            // Larger tiles with metadata
│   │   └── PreviewPane.swift          // QLPreviewView wrapper
│   │
│   ├── Dialogs/
│   │   ├── PropertiesDialog.swift     // File/folder properties inspector
│   │   ├── ConflictDialog.swift       // Copy/move conflict resolution
│   │   └── ProgressSheet.swift        // File operation progress
│   │
│   └── Shared/
│       ├── FileIconView.swift         // Thumbnail / icon rendering
│       ├── ContextMenuBuilder.swift   // Right-click menu construction
│       └── SearchBar.swift            // Search field
│
├── Services/
│   ├── FileSystemService.swift        // FileManager wrapper, enumeration, watchers
│   ├── FileOperationService.swift     // Copy, move, delete, rename (async, cancelable)
│   ├── SearchService.swift            // NSMetadataQuery wrapper
│   ├── ThumbnailService.swift         // QLThumbnailGenerator caching layer
│   ├── BookmarkService.swift          // Security-scoped bookmark management
│   └── VolumeService.swift            // NSWorkspace volume notifications
│
├── Utilities/
│   ├── FileSize+Formatter.swift       // Human-readable sizes
│   ├── Date+Formatter.swift           // Consistent date formatting
│   ├── URL+Extensions.swift           // Convenience for path operations
│   └── KeyboardShortcuts.swift        // Central shortcut definitions
│
└── Resources/
    ├── Assets.xcassets                // App icon, custom icons
    ├── Localizable.strings            // Localization
    └── Explorer.entitlements          // Sandbox + bookmark entitlements
```

### Data Flow

```
User Action
    │
    ▼
View (SwiftUI) ──sends action──▶ ViewModel (@Observable)
                                       │
                                       ├── updates @Published state
                                       │   (view re-renders automatically)
                                       │
                                       └── calls Service layer (async)
                                               │
                                               ▼
                                        FileManager / NSMetadataQuery / etc.
```

- **`@Observable`** (Swift 5.9 macro) is preferred over `ObservableObject` for new code — finer-grained invalidation.
- ViewModels are owned per-tab (each tab has its own `BrowserViewModel`).
- `SidebarViewModel` is shared across tabs (one sidebar for the window).
- Services are injected via SwiftUI `@Environment` or passed at init.

---

## 3. Key Components / Views

### 3.1 App Shell & Window

**Implementation:**
```swift
@main
struct ExplorerApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            MainWindow()
                .environment(appState)
        }
        .commands {
            ExplorerCommands() // File, Edit, View, Go menus
        }
    }
}
```

- Use `NavigationSplitView` for the sidebar ↔ content split.
- Window minimum size: ~800×500; default ~1100×700.
- Support `Settings` scene for preferences window.

### 3.2 Navigation Pane (Sidebar)

**Sections** (top to bottom, matching Windows Explorer):
1. **Quick Access / Favorites** — User-pinned folders (persisted via `UserDefaults` + security-scoped bookmarks).
2. **This Mac** — Equivalent of "This PC." Lists Home, Desktop, Documents, Downloads, Applications, and mounted volumes.
3. **Network** — `NSWorkspace` network volume enumeration (optional/advanced).
4. **Folder Tree** — Expandable tree rooted at the currently selected location.

**Implementation approach:**
- For the tree view, use SwiftUI `List` with `DisclosureGroup` for simple cases.
- **Preferred:** Wrap `NSOutlineView` in `NSViewRepresentable` for performance with deep trees (thousands of folders). `NSOutlineView` supports lazy child loading, drag-drop reordering for favorites, and is battle-tested.
- Folder expansion loads children lazily (`FileManager.contentsOfDirectory`) on a background task.
- Watch for file system changes with `DispatchSource.makeFileSystemObjectSource` or `FSEvents` (`FSEventStreamCreate`) to live-update the tree.

### 3.3 Tab Bar

**Implementation:**
- Model: `AppState` holds `[TabState]` where each `TabState` contains a `BrowserViewModel`.
- View: Custom `TabBarView` using `HStack` of tab buttons with close (×) buttons, a "+" button, and drag-to-reorder.
- macOS 15+ offers native `TabView` improvements; for macOS 14 compatibility, build custom.
- Middle-click a folder → opens in new tab (like Windows 11).
- Keyboard: ⌘T new tab, ⌘W close tab, ⌘⇧] / ⌘⇧[ switch tabs.

### 3.4 Address / Breadcrumb Bar

**Design:** Looks like Windows Explorer's address bar — each path component is a clickable button, with `>` chevron separators that reveal sibling folders in a dropdown.

```
[ ← ] [ → ] [ ↑ ]   [ 🏠 ] [ Users ] ▸ [ ehamai ] ▸ [ Documents ] ▸ [ Projects ]
```

**Implementation:**
- Parse `URL.pathComponents` into `[BreadcrumbSegment]`.
- Each segment is a `Button` with `.plain` style. Clicking navigates there.
- Chevron `▸` buttons show a `Menu` (or popover) listing sibling directories of that segment.
- Clicking the whitespace area (or double-clicking) converts to an editable `TextField` for direct path entry (exactly like Windows).
- Back / Forward / Up buttons use `BrowserViewModel.navigationHistory` (stack-based).

### 3.5 Toolbar / Ribbon

**Design:** A horizontal strip below the address bar, styled to evoke the Windows ribbon but adapted for macOS conventions.

**Sections (grouped with dividers):**

| Group | Actions |
|---|---|
| Clipboard | Cut, Copy, Paste, Copy Path |
| Organize | Move To, Rename, Delete, New Folder, New File |
| View | View mode picker (Details / Icons / Tiles), Sort By, Group By |
| Selection | Select All, Select None, Invert Selection |
| Layout | Toggle Preview Pane, Toggle Sidebar, Split View |

**Implementation:**
- Use SwiftUI `.toolbar` with `ToolbarItemGroup` for native integration.
- For a more ribbon-like look, use a custom `HStack` below the title bar with icon buttons + labels, grouped with `Divider()`.
- Actions dispatch to `FileOperationsViewModel`.
- Buttons dim/enable based on selection state.

### 3.6 Content Area (Main Panel)

#### 3.6.1 Details View (List with Columns)

The most important view mode — replicates Windows' columnar details view.

| Column | Source | Sortable |
|---|---|---|
| Name | `URL.lastPathComponent` | ✓ |
| Date Modified | `URLResourceValues.contentModificationDate` | ✓ |
| Type | `URLResourceValues.contentType` (UTType) | ✓ |
| Size | `URLResourceValues.totalFileAllocatedSize` | ✓ |

**Implementation:**
- **SwiftUI `Table`** (macOS 13+): Supports sortable columns, multi-selection, and is purpose-built.
  ```swift
  Table(viewModel.items, selection: $viewModel.selection, sortOrder: $viewModel.sortOrder) {
      TableColumn("Name", value: \.name) { item in FileNameCell(item: item) }
      TableColumn("Date Modified", value: \.dateModified) { item in Text(item.formattedDate) }
      TableColumn("Size", value: \.size) { item in Text(item.formattedSize) }
      TableColumn("Type", value: \.typeDescription) { item in Text(item.typeDescription) }
  }
  ```
- Folders sort before files (like Windows).
- Double-click a folder → navigate into it; double-click a file → `NSWorkspace.shared.open(url)`.
- Multi-select with ⌘-click and ⇧-click.
- Inline rename: triggered by pressing Enter on a selected item or slow double-click → show `TextField` overlay.

#### 3.6.2 Icons View

- Use `LazyVGrid` with adaptive columns.
- Each cell: thumbnail (via `ThumbnailService`) + filename label below.
- Icon sizes: Small (32pt), Medium (64pt), Large (96pt), Extra Large (128pt) — slider or segmented control.
- Selecting adjusts overlay/highlight.

#### 3.6.3 Tiles View

- Like Icons but horizontal orientation: icon on left, name + metadata text on right.
- `LazyVGrid` with fixed-width columns or a `List` with custom row layout.

### 3.7 Preview Pane

- Toggle via toolbar button or ⌥P shortcut.
- Wraps `QLPreviewView` (AppKit) in `NSViewRepresentable`.
- Shows preview for the selected file; shows folder info (item count, size) for directories.
- Positioned as a trailing column in an `HSplitView`.

### 3.8 Status Bar

A thin bar at the bottom of each tab:
```
[ 142 items | 3 selected | 2.4 GB free on "Macintosh HD" ]
```
- `HStack` with `Text` elements, `Spacer`, and a view-mode segmented picker (optional).
- Data sourced from `FileListViewModel` (item count, selection count) and `VolumeService` (free space).

### 3.9 Context Menus

**Implementation:**
- Use `.contextMenu { }` modifier on list rows / grid items.
- Context menu items adapt based on selection:
  - File: Open, Open With ▸, Get Info, Rename, Copy, Move to Trash, Copy Path, Compress, Share ▸
  - Folder: Same + "Open in New Tab," "Open in Terminal"
  - Empty area: New Folder, New File, Paste, View options, Sort By ▸
- "Open With" submenu uses `NSWorkspace.urlsForApplications(toOpen:)` to list apps.

### 3.10 Search

- Search field in the toolbar (SwiftUI `.searchable` or custom `NSSearchField`).
- Two modes:
  1. **Filter mode** — instant, client-side filtering of the current directory listing.
  2. **Deep search** — uses `NSMetadataQuery` (Spotlight) to search recursively from the current folder.
- Results displayed in the content area with path breadcrumbs showing where each result lives.
- Search tokens/suggestions like Windows (e.g., `kind:folder`, `date:today`).

### 3.11 Drag and Drop

- SwiftUI's `.draggable(item)` and `.dropDestination(for:)` modifiers.
- Drag files out of the app → provide `NSItemProvider` with file URLs.
- Drag files into a folder row → move/copy (hold ⌥ for copy, default is move within same volume).
- Drag from Finder/Desktop into the app.
- Spring-loaded folders: hovering over a folder during drag auto-expands it after ~0.8s.
- For full fidelity, may need `NSView`-level drag session via AppKit interop (e.g., for custom drag images, multi-item drags).

### 3.12 Keyboard Shortcuts

| Shortcut | Action |
|---|---|
| ⌘C / ⌘V / ⌘X | Copy / Paste / Cut (move) |
| ⌘⌫ | Move to Trash |
| ⌘⇧N | New Folder |
| Enter | Rename (macOS convention) |
| ⌘O | Open |
| ⌘I | Get Info / Properties |
| ⌘A | Select All |
| ⌘F | Focus search |
| ⌘T | New tab |
| ⌘W | Close tab |
| ⌘[ / ⌘] | Back / Forward |
| ⌘↑ | Go to parent directory |
| Space | Quick Look preview |
| ⌘1/2/3 | Switch view mode |
| ⌘⇧. | Toggle hidden files |
| ⌘⌥P | Toggle preview pane |

Implementation: Combine `.keyboardShortcut()` on buttons + `.onKeyPress()` for custom handling + `commands { }` in the scene for menu bar shortcuts.

### 3.13 Properties Dialog

- A `.sheet` or standalone `.window` showing:
  - File icon (large), name (editable), kind, size (with "calculating..." spinner for folders)
  - Location, creation date, modification date
  - Permissions grid (Read/Write/Execute for Owner/Group/Others) — maps to `FileAttributeKey.posixPermissions`
  - "Open With" picker
  - Tags (macOS extended attribute `com.apple.metadata:_kMDItemUserTags`)
- Folder size calculated async with recursive enumeration using `FileManager.enumerator(at:)`.

### 3.14 Dual/Split Pane

- Toolbar button or ⌘⇧E to split the content area horizontally.
- Implementation: `HSplitView` containing two independent `BrowserView` instances.
- Each pane has its own `BrowserViewModel` (independent navigation, selection, view mode).
- Drag between panes triggers copy/move.

---

## 4. File System Interaction

### 4.1 Core File Enumeration

```swift
actor FileSystemService {
    func contentsOfDirectory(at url: URL) async throws -> [FileItem] {
        let resourceKeys: Set<URLResourceKey> = [
            .nameKey, .isDirectoryKey, .fileSizeKey, .totalFileAllocatedSizeKey,
            .contentModificationDateKey, .creationDateKey, .contentTypeKey,
            .isHiddenKey, .isPackageKey, .effectiveIconKey, .tagNamesKey
        ]
        
        let contents = try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: Array(resourceKeys),
            options: showHidden ? [] : [.skipsHiddenFiles]
        )
        
        return try contents.map { url in
            let values = try url.resourceValues(forKeys: resourceKeys)
            return FileItem(url: url, resourceValues: values)
        }
    }
}
```

- Fetch resource values in batch (single `contentsOfDirectory` call) — much faster than per-file stat.
- For very large directories (>10,000 items), paginate or use `FileManager.enumerator` with a limit.

### 4.2 File System Watching

**Two options, both viable:**

1. **`DispatchSource.makeFileSystemObjectSource`** — Per-directory watch. Low overhead, but only monitors one directory at a time. Best for watching the currently displayed directory.

2. **FSEvents API** — Monitors subtrees efficiently. Better for the sidebar tree and deep search results. Requires C interop (`FSEventStreamCreate`).

**Recommended hybrid:** Use FSEvents for the sidebar tree (watching `/Users/...` subtree) and DispatchSource for the active directory in the content area. Debounce updates (coalesce events within ~200ms) to avoid UI flicker.

### 4.3 File Operations

```swift
actor FileOperationService {
    func copy(items: [URL], to destination: URL, progress: @escaping (Double) -> Void) async throws {
        for (index, item) in items.enumerated() {
            let dest = destination.appendingPathComponent(item.lastPathComponent)
            
            // Handle conflicts
            if FileManager.default.fileExists(atPath: dest.path) {
                // Ask user: replace, skip, keep both
                throw FileConflict(source: item, destination: dest)
            }
            
            try FileManager.default.copyItem(at: item, to: dest)
            progress(Double(index + 1) / Double(items.count))
        }
    }
    
    func moveToTrash(items: [URL]) async throws -> [URL] {
        var trashedURLs: [URL] = []
        for item in items {
            var resultURL: NSURL?
            try FileManager.default.trashItem(at: item, resultingItemURL: &resultURL)
            if let url = resultURL as URL? { trashedURLs.append(url) }
        }
        return trashedURLs  // For undo support
    }
}
```

- All file operations run on background tasks with cancellation support.
- Progress sheet (`ProgressSheet`) with cancel button for multi-file operations.
- `UndoManager` integration: register undo after move/delete/rename.
- For large copies, use `Progress` object and KVO to track byte-level progress (via `NSFileManager` methods or custom byte-stream copy).

### 4.4 Sandbox & Security

**Option A: Non-sandboxed (Recommended for this app)**
- Distribute outside the Mac App Store (Developer ID signed + notarized).
- Full file system access without security-scoped bookmarks.
- No entitlements headaches; behaves like a native file manager.
- Can still be notarized for Gatekeeper approval.

**Option B: Sandboxed (Required for Mac App Store)**
- Entitlements needed:
  ```xml
  <key>com.apple.security.app-sandbox</key> <true/>
  <key>com.apple.security.files.user-selected.read-write</key> <true/>
  <key>com.apple.security.files.bookmarks.app-scope</key> <true/>
  <key>com.apple.security.files.bookmarks.document-scope</key> <true/>
  ```
- Every user-navigated folder must go through `NSOpenPanel` or gain access via parent bookmark.
- Persist access with security-scoped bookmarks (`URL.bookmarkData(options: .withSecurityScope)`).
- Sidebar favorites and recently visited directories stored as bookmarks.
- **This is extremely painful for a file explorer.** Every directory the user clicks into that wasn't a child of an already-bookmarked path requires new permission granting. Apple has historically rejected file manager apps from the App Store for requesting `com.apple.security.temporary-exception.files.absolute-path.read-write` on `/`.

**Recommendation:** Build non-sandboxed, distribute via direct download / Homebrew. Keep the architecture bookmark-aware so sandboxing *could* be added later.

### 4.5 Permissions & Symlinks

- Detect and resolve symlinks with `URL.resolvingSymlinksInPath()`.
- Display symlink targets in the properties dialog.
- Handle permission errors gracefully (show lock icon overlay, gray out inaccessible directories).
- Respect `.hidden` extended attribute and `.` prefix convention.

---

## 5. Build System

### 5.1 Xcode Project Setup

```
Explorer.xcodeproj
├── Targets
│   ├── Explorer (macOS App)                   — Main app target
│   ├── ExplorerCore (Swift Package / Framework) — Models + Services (testable)
│   └── ExplorerTests (Unit Test Bundle)        — XCTest for core logic
│
├── Build Settings
│   ├── MACOSX_DEPLOYMENT_TARGET = 14.0         — macOS Sonoma minimum
│   ├── ARCHS = arm64                           — Apple Silicon native (Universal optional)
│   ├── SWIFT_VERSION = 5.10
│   ├── SWIFT_STRICT_CONCURRENCY = complete     — Prepare for Swift 6
│   └── CODE_SIGN_IDENTITY = Developer ID Application
│
├── Schemes
│   ├── Explorer (Debug)    — App with assertions, sanitizers
│   ├── Explorer (Release)  — Optimized, stripped
│   └── ExplorerTests       — Test scheme
│
└── Signing
    ├── Team: (Developer Team ID)
    ├── Provisioning: Automatic
    └── Hardened Runtime: YES (required for notarization)
```

### 5.2 Swift Package Manager (Alternative to Framework target)

Could structure the non-UI core as a local Swift package:

```
Explorer/
├── Package.swift  (or local package within Xcode workspace)
├── Sources/
│   ├── ExplorerCore/       — Models, Services, ViewModels
│   └── ExplorerUI/         — SwiftUI Views (depends on ExplorerCore)
└── Tests/
    └── ExplorerCoreTests/  — Unit tests for services & view models
```

**Benefits:** Faster incremental builds, clear module boundaries, testable without UI.

### 5.3 CI/CD

- **Xcode Cloud** or **GitHub Actions** with `macos-14` runner (Apple Silicon).
- Pipeline: Build → Test → Archive → Notarize → Upload to distribution (GitHub Releases / Sparkle feed).
- Use `xcodebuild` for headless builds:
  ```bash
  xcodebuild -scheme Explorer -configuration Release -arch arm64 build
  ```

### 5.4 Code Signing & Notarization

```bash
# Archive
xcodebuild archive -scheme Explorer -archivePath build/Explorer.xcarchive

# Export
xcodebuild -exportArchive -archivePath build/Explorer.xcarchive \
    -exportOptionsPlist ExportOptions.plist -exportPath build/

# Notarize
xcrun notarytool submit build/Explorer.dmg --apple-id "..." --team-id "..." --password "..."
xcrun stapler staple build/Explorer.dmg
```

### 5.5 Dependencies Management

- **Zero third-party dependencies** at launch.
- If later needed, add via SPM `Package.swift` dependencies (e.g., `Sparkle` for auto-updates).

---

## 6. Estimated Complexity

| Feature | Complexity | Notes |
|---|---|---|
| App shell / window management | Low | `WindowGroup` + `NavigationSplitView` |
| Sidebar: Quick Access / Favorites | Low | `List` + persistence |
| Sidebar: Folder tree (lazy) | **High** | `NSOutlineView` interop, lazy loading, FS watching |
| Tab support | Medium | Custom tab bar, per-tab state management |
| Address bar with breadcrumbs | Medium | Custom view with edit-mode toggle, sibling menus |
| Toolbar / ribbon | Low-Medium | Standard toolbar items + custom grouping |
| Details view (sortable table) | Medium | SwiftUI `Table`, custom cells, inline rename |
| Icons view | Low-Medium | `LazyVGrid` + thumbnail loading |
| Tiles view | Low | Variant of icons view |
| Search (filter) | Low | Client-side string matching |
| Search (deep / Spotlight) | Medium | `NSMetadataQuery` wrapper, result aggregation |
| Preview pane | Medium | `QLPreviewView` AppKit interop |
| Context menus | Medium | Dynamic menu building, "Open With" enumeration |
| Drag and drop | **High** | Full-fidelity DnD with spring-loading, cross-app |
| File operations (copy/move/del) | Medium | Async with progress, conflict resolution |
| Undo/redo | Medium | `UndoManager` integration for file ops |
| Keyboard shortcuts | Low | Declarative `.keyboardShortcut()` |
| Properties dialog | Medium | Permission display, async folder size |
| Dual/split pane | Medium | `HSplitView` + independent ViewModels |
| File system watching | Medium-High | FSEvents + DispatchSource, debouncing |
| Thumbnail caching | Medium | `QLThumbnailGenerator` + `NSCache` |
| Hidden files toggle | Low | Resource key filter |
| **Total project** | **High** | Full-featured file manager is a substantial app |

---

## 7. Pros and Cons

### Pros

| # | Advantage | Detail |
|---|---|---|
| 1 | **Native performance** | SwiftUI/AppKit compile to native ARM64. Instant launch (~0.3s), low memory (~30-60MB), smooth 120fps scrolling on ProMotion displays. No runtime overhead (no V8, no Dart VM, no WebView). |
| 2 | **System integration** | Direct access to macOS APIs: Spotlight search, Quick Look previews, Services menu, Notification Center, Share extensions, Finder Sync extensions. No bridging layer. |
| 3 | **Small binary** | Estimated ~5-10MB app bundle (vs 150-300MB for Electron). System frameworks are shared. |
| 4 | **Look and feel** | SwiftUI controls automatically get the correct macOS styling, vibrancy, dark mode, accent colors, accessibility, and animation curves. The app *belongs* on macOS. |
| 5 | **Apple Silicon native** | No Rosetta overhead. Can target `arm64` exclusively for maximum optimization. Leverages AMX/NEON for any image processing (thumbnails). |
| 6 | **Sandboxing possible** | Can be distributed on Mac App Store (with caveats). |
| 7 | **Concurrency model** | Swift structured concurrency (`async/await`, actors) is ideal for file system operations. Type-safe, no callback hell. |
| 8 | **Testing** | `XCTest` + Swift Testing framework for unit tests. `ViewInspector` for SwiftUI view tests (optional). |
| 9 | **Longevity** | Apple's primary UI framework. Will receive continued investment. Not at risk of deprecation. |
| 10 | **Accessibility** | Built-in VoiceOver, keyboard navigation, Dynamic Type from SwiftUI. Much less effort than web-based approaches. |

### Cons

| # | Disadvantage | Detail |
|---|---|---|
| 1 | **macOS only** | Zero code reuse on Windows/Linux. If cross-platform is ever desired, this is the wrong choice. However, the prompt specifies macOS on Apple Silicon, so this is acceptable. |
| 2 | **SwiftUI maturity gaps** | `Table` has limited customization (no column resize dragging in some versions). `NSOutlineView` interop required for the tree view. Some AppKit bridging is inevitable for a power-user app. |
| 3 | **Replicating Windows aesthetics is harder** | SwiftUI defaults to macOS styling. Making things *look like Windows Explorer* (ribbon, address bar, etc.) requires custom views that fight the platform conventions. Users may expect macOS conventions instead. |
| 4 | **No hot reload (in the Electron sense)** | SwiftUI Previews exist but are sometimes unreliable for complex views. Iteration is slower than web-dev hot reload. |
| 5 | **Smaller developer pool** | Swift/SwiftUI expertise is less common than JavaScript/TypeScript. Harder to hire or find OSS contributors. |
| 6 | **Sandbox friction** | If App Store distribution is needed, sandboxing a file explorer is extremely painful (see Section 4.4). |
| 7 | **Deployment target limits API availability** | Targeting macOS 14+ is fine, but some newer SwiftUI features (e.g., improved `Table`, `Inspector`) require macOS 15+. Must decide on the floor. |
| 8 | **File system edge cases** | APFS firmlinks, network volumes (SMB/NFS/AFP), encrypted volumes, Time Machine snapshots, and `.app` bundles (which are directories) all require special handling. |

---

## 8. Apple Silicon Optimization

### 8.1 ARM64-Specific Considerations

| Area | Detail |
|---|---|
| **Build target** | Set `ARCHS = arm64` for Apple Silicon-only. Add `x86_64` for Universal Binary if Intel support is needed. Apple Silicon Macs can run Intel binaries via Rosetta 2, but native is ~20-40% faster. |
| **Memory efficiency** | Apple Silicon has unified memory (CPU/GPU share RAM). SwiftUI's Metal-backed rendering leverages this — no CPU→GPU texture copies for thumbnails. Keep large thumbnail caches GPU-resident. |
| **ProMotion display** | M-series MacBook Pros have 120Hz ProMotion displays. SwiftUI animations automatically run at the display refresh rate. Ensure scroll performance stays above 120fps by using `LazyVStack`/`LazyVGrid` and avoiding heavyweight `.onAppear` in cells. |
| **Efficiency cores** | Apple Silicon has P-cores (performance) and E-cores (efficiency). File enumeration and thumbnail generation can be QoS-tagged `.utility` or `.background` to run on E-cores, preserving P-cores for UI rendering. Swift concurrency respects QoS. |
| **NEON / AMX** | Not directly relevant unless doing custom image processing. `QLThumbnailGenerator` already uses hardware acceleration internally. If building a custom thumbnail pipeline, use `vImage` (Accelerate framework) which auto-vectorizes to NEON. |
| **Unified SSD bandwidth** | Apple Silicon Macs have extremely fast SSD access (2-7 GB/s). Directory enumeration and file metadata reads are I/O-bound but fast. This makes the app feel instant compared to HDD-era Windows. Can afford to re-scan directories rather than caching aggressively. |
| **Secure Enclave** | Not directly used, but if adding authentication features (e.g., encrypted favorites), `LAContext` + Keychain with Secure Enclave keys is available. |

### 8.2 Build Optimization Flags

```
// Release build settings
SWIFT_OPTIMIZATION_LEVEL = -O          // Whole module optimization
LLVM_LTO = YES                         // Link-Time Optimization (thin LTO)
GCC_OPTIMIZATION_LEVEL = s             // Optimize for size (binary stays small)
DEAD_CODE_STRIPPING = YES
STRIP_SWIFT_SYMBOLS = YES
```

- LTO on Apple Silicon LLVM backend produces well-optimized ARM64 code.
- Profile with Instruments (Time Profiler, Allocations) on actual Apple Silicon hardware — simulator is x86_64 translated.

---

## 9. Timeline Estimate

### Phase 0: Foundation (Weeks 1-2)

**Goal:** Skeleton app that launches, shows a window, navigates directories.

- [ ] Xcode project setup, module structure, entitlements
- [ ] `FileItem` model, `FileSystemService` with `contentsOfDirectory`
- [ ] `NavigationSplitView` shell: sidebar placeholder + content area
- [ ] Basic `DetailsView` with SwiftUI `Table` (Name, Size, Date, Type columns)
- [ ] Column sorting
- [ ] Double-click folder to navigate, double-click file to open
- [ ] Back / Forward navigation (`BrowserViewModel` with history stack)
- [ ] Basic address bar (static breadcrumbs, no dropdowns yet)

**Deliverable:** A functional directory browser with table view and basic navigation.

### Phase 1: Core Features (Weeks 3-5)

**Goal:** Feature parity with a basic file manager.

- [ ] Sidebar: Quick Access section with hardcoded system folders
- [ ] Sidebar: Mounted volumes (`NSWorkspace` notification-based)
- [ ] Sidebar: Expandable folder tree (NSOutlineView interop)
- [ ] Icons view (`LazyVGrid` + `QLThumbnailGenerator`)
- [ ] Tiles view
- [ ] View mode switching (toolbar segmented control)
- [ ] Status bar (item count, selection count, free space)
- [ ] Toolbar with common actions (New Folder, Delete, Rename)
- [ ] Context menus (right-click on files, folders, empty space)
- [ ] Keyboard shortcuts (⌘C, ⌘V, ⌘⌫, ⌘⇧N, Enter-to-rename, etc.)
- [ ] File operations: Copy, Move, Delete (Trash), Rename
- [ ] Hidden files toggle (⌘⇧.)

**Deliverable:** A usable file manager for daily tasks.

### Phase 2: Advanced Features (Weeks 6-8)

**Goal:** Feature-rich, approaching Windows Explorer completeness.

- [ ] Tab support (custom tab bar, per-tab state)
- [ ] Address bar: clickable breadcrumb segments with sibling dropdowns
- [ ] Address bar: edit mode (click to type path)
- [ ] Search: in-directory filter (instant)
- [ ] Search: Spotlight-based deep search (`NSMetadataQuery`)
- [ ] Drag and drop: within app (move between folders)
- [ ] Drag and drop: to/from Finder and other apps
- [ ] File operation progress sheet with cancel
- [ ] Conflict resolution dialog (Replace, Skip, Keep Both)
- [ ] Undo/Redo for file operations
- [ ] Properties dialog (file info, permissions)
- [ ] Preview pane (QLPreviewView)
- [ ] File system watching (live updates when files change externally)

**Deliverable:** Feature-complete file explorer.

### Phase 3: Polish & Distribution (Weeks 9-11)

**Goal:** Production quality.

- [ ] Dual/split pane view
- [ ] Favorites management (drag to pin, reorder, remove)
- [ ] "Open With" submenu population
- [ ] Preferences window (default view mode, show extensions, etc.)
- [ ] Dark mode + accent color testing
- [ ] VoiceOver / accessibility audit
- [ ] Performance profiling (Instruments: large directories, rapid navigation)
- [ ] Thumbnail caching (`NSCache` + optional disk cache)
- [ ] Spring-loaded folder expansion during drag
- [ ] Menu bar menus (File, Edit, View, Go, Window, Help)
- [ ] About dialog, credits
- [ ] App icon design
- [ ] Code signing, notarization, DMG creation
- [ ] README, screenshots, license

**Deliverable:** Shippable v1.0.

### Phase 4: Post-Launch (Ongoing)

- [ ] Auto-update (Sparkle framework integration)
- [ ] Localization (at minimum: English, Spanish, Chinese, Japanese, German)
- [ ] Network volume browsing (SMB, NFS)
- [ ] Finder Sync Extension (custom badges, context menu items in Finder)
- [ ] Compressed archive handling (ZIP, TAR, etc.)
- [ ] Batch rename tool
- [ ] Custom themes / appearance settings
- [ ] Keyboard-driven command palette (like VS Code's ⌘⇧P)

### Summary Timeline

| Phase | Duration | Cumulative |
|---|---|---|
| Phase 0: Foundation | 2 weeks | 2 weeks |
| Phase 1: Core Features | 3 weeks | 5 weeks |
| Phase 2: Advanced Features | 3 weeks | 8 weeks |
| Phase 3: Polish & Distribution | 3 weeks | 11 weeks |

**Total to v1.0: ~11 weeks** (1 experienced developer, full-time).

With 2 developers working in parallel (one on UI, one on services/file-ops), compress to ~7 weeks.

---

## 10. Risks and Challenges

### 10.1 Technical Risks

| Risk | Severity | Mitigation |
|---|---|---|
| **SwiftUI `Table` limitations** | Medium | SwiftUI's `Table` may not support column resize handles, reorderable columns, or pixel-perfect Windows-style rendering. Mitigation: Fall back to `NSTableView` via `NSViewRepresentable` if needed. Test early. |
| **Tree view performance** | High | Deep folder trees (e.g., `node_modules`) can have 100K+ nodes. `NSOutlineView` with lazy loading handles this well; pure SwiftUI `DisclosureGroup` will not. Plan for AppKit interop from day one. |
| **Drag-and-drop fidelity** | High | SwiftUI's drag-and-drop is still maturing. Multi-item drags, custom drag previews, and spring-loaded folders may require `NSView`-level implementation. Budget extra time. |
| **File system edge cases** | Medium | APFS firmlinks (e.g., `/System/Volumes/Data` appearing under `/`), `.app` bundles (directories shown as files), aliases vs symlinks, network volumes with latency. Must handle each explicitly. |
| **Sandbox rejection** | Medium | If App Store distribution is desired, Apple may reject a file manager for requesting broad file access. Mitigation: Plan for direct distribution; don't depend on App Store. |
| **Inline rename** | Low-Medium | Renaming a file in-place within a `Table` row requires overlaying a `TextField` on the cell and managing focus carefully. SwiftUI doesn't natively support inline editing in `Table`. |

### 10.2 Design Risks

| Risk | Severity | Mitigation |
|---|---|---|
| **Windows vs macOS UX tension** | Medium | Replicating Windows Explorer *exactly* will feel alien on macOS. Users expect macOS conventions (⌘-based shortcuts, traffic light window buttons, single menu bar). Solution: Replicate *features and layout* but adapt *interactions* to macOS norms. |
| **Ribbon doesn't fit macOS** | Low | Windows-style ribbon toolbars are non-standard on macOS. Use a macOS-native toolbar with grouped items that *achieves the same functionality* without looking out of place. |
| **Address bar behavior** | Medium | Windows' address bar switches between breadcrumb and text-edit modes. This is doable but requires careful focus management and animation. |

### 10.3 Schedule Risks

| Risk | Severity | Mitigation |
|---|---|---|
| **Scope creep** | High | A "full Windows Explorer clone" is an enormous surface area. Mitigation: Strictly prioritize Phase 0-2 features. Ship v1.0 without network volumes, batch rename, etc. |
| **SwiftUI bugs** | Medium | SwiftUI on macOS has known bugs (especially around focus, keyboard handling, and `Table`). May need workarounds. Budget 15-20% time for platform bug investigation. |
| **Testing on multiple macOS versions** | Low | Differences between macOS 14 and macOS 15 SwiftUI behavior. Test on both. |

### 10.4 Comparison vs Alternative Approaches

| Factor | Swift+SwiftUI | Electron | Tauri | Flutter |
|---|---|---|---|---|
| Binary size | ~5-10 MB | ~150-300 MB | ~10-20 MB | ~20-40 MB |
| RAM usage | ~30-60 MB | ~200-500 MB | ~80-150 MB | ~80-120 MB |
| Startup time | <0.5s | 2-4s | 1-2s | 1-2s |
| macOS API access | Native (full) | Via Node addons | Via Rust plugins | Via platform channels |
| Look & feel | Native macOS | Web (custom-styled) | Web (custom-styled) | Custom rendering |
| Cross-platform | ❌ macOS only | ✅ Win/Mac/Linux | ✅ Win/Mac/Linux | ✅ Win/Mac/Linux |
| Development speed | Medium | Fast (web devs) | Medium | Medium |
| Tree view perf | Excellent | Poor without virtualization | Poor without virtualization | Good (custom) |
| File system access | Direct, fast | Via Node.js fs | Via Rust backend | Via platform plugins |

**Bottom line for this project:** If the target is macOS-only on Apple Silicon, Swift+SwiftUI is the objectively superior choice. It produces the smallest, fastest, most integrated app with the lowest resource usage. The only reason to choose a cross-platform stack would be if Windows/Linux support is planned.

---

## Appendix A: Key API Quick Reference

```swift
// Directory listing
FileManager.default.contentsOfDirectory(at:includingPropertiesForKeys:options:)

// File operations
FileManager.default.copyItem(at:to:)
FileManager.default.moveItem(at:to:)
FileManager.default.trashItem(at:resultingItemURL:)
FileManager.default.removeItem(at:)
FileManager.default.createDirectory(at:withIntermediateDirectories:attributes:)

// Resource values (metadata)
URL.resourceValues(forKeys:)  // .fileSizeKey, .contentModificationDateKey, etc.

// Thumbnails
QLThumbnailGenerator.shared.generateBestRepresentation(for:completion:)

// Quick Look preview
QLPreviewView(frame:style:)  // AppKit, wrap in NSViewRepresentable

// Spotlight search
NSMetadataQuery()  // .searchScopes, .predicate, .start()

// Volume notifications
NSWorkspace.shared.notificationCenter  // .didMount, .didUnmount, .didRename

// Open files
NSWorkspace.shared.open(URL)
NSWorkspace.shared.open([URL], withApplicationAt:configuration:)
NSWorkspace.shared.urlsForApplications(toOpen:)

// File system events
FSEventStreamCreate(...)  // C API, use a Swift wrapper
DispatchSource.makeFileSystemObjectSource(fileDescriptor:eventMask:queue:)

// Security-scoped bookmarks
URL.bookmarkData(options: .withSecurityScope, ...)
URL(resolvingBookmarkData:options: .withSecurityScope, ...)
url.startAccessingSecurityScopedResource()
url.stopAccessingSecurityScopedResource()
```

---

## Appendix B: File Item Model

```swift
import Foundation
import UniformTypeIdentifiers

@Observable
final class FileItem: Identifiable, Hashable {
    let id: URL  // URL is unique per file
    let url: URL
    let name: String
    let isDirectory: Bool
    let isPackage: Bool      // .app bundles, etc.
    let isHidden: Bool
    let isSymlink: Bool
    let size: Int64?         // nil for directories (until calculated)
    let dateModified: Date?
    let dateCreated: Date?
    let contentType: UTType?
    let tags: [String]
    
    var isExpanded: Bool = false  // For tree view
    var children: [FileItem]?    // Lazy-loaded for directories
    
    var formattedSize: String { /* ByteCountFormatter */ }
    var formattedDate: String { /* DateFormatter, relative style */ }
    var typeDescription: String { contentType?.localizedDescription ?? "Unknown" }
    var icon: NSImage { NSWorkspace.shared.icon(forFile: url.path) }
    
    // Hashable: hash by URL
    func hash(into hasher: inout Hasher) { hasher.combine(url) }
    static func == (lhs: FileItem, rhs: FileItem) -> Bool { lhs.url == rhs.url }
}
```
