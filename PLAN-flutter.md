# Flutter macOS File Explorer — Implementation Plan

> A Windows File Explorer clone for macOS on Apple Silicon, built with Flutter.

---

## 1. Technology Stack

### Core Framework
| Component | Choice | Rationale |
|---|---|---|
| **Framework** | Flutter 3.27+ (stable) | Mature desktop support, single codebase, custom rendering |
| **Language** | Dart 3.x | AOT compilation, null safety, strong async/isolate support |
| **UI Library** | `fluent_ui` ^4.9 | Microsoft Fluent Design System — closest to Windows Explorer look-and-feel |
| **State Mgmt** | `flutter_riverpod` ^2.6 | Compile-safe, tree-independent, testable providers |
| **Rendering** | Impeller (Metal backend) | Pre-compiled shaders, no runtime jank, native Apple Silicon GPU |

### Key Packages

```yaml
dependencies:
  # UI & Design
  fluent_ui: ^4.9.1                  # Windows Fluent Design widgets (NavigationView, TreeView, CommandBar, TabView, etc.)
  flutter_acrylic: ^1.1.4            # Mica/Acrylic translucent window effects
  window_manager: ^0.4.3             # Window chrome control (title bar, min/max/close, frameless)
  desktop_drop: ^0.5.0               # Drag-and-drop from Finder / desktop
  super_drag_and_drop: ^0.8.0        # Cross-widget drag-and-drop within the app
  context_menus: ^2.0.0              # Right-click context menus (fallback: fluent_ui built-in)
  flutter_svg: ^2.0.0                # SVG icon rendering for file-type icons

  # File System
  path: ^1.9.0                       # Cross-platform path manipulation
  path_provider: ^2.1.0              # Standard directories (Documents, Downloads, etc.)
  file_picker: ^8.0.0                # Native open/save dialogs
  watcher: ^1.1.0                    # File system change notifications
  mime: ^2.0.0                       # MIME type detection for file icons
  filesize: ^2.0.1                   # Human-readable file sizes

  # State & Architecture
  flutter_riverpod: ^2.6.1           # State management
  riverpod_annotation: ^2.6.1        # Code-gen providers
  freezed_annotation: ^2.4.6         # Immutable model classes
  go_router: ^14.0.0                 # Declarative routing (tab ↔ path mapping)

  # Utilities
  collection: ^1.18.0               # Sorted lists, equality, grouping
  intl: ^0.19.0                     # Date/number formatting
  shared_preferences: ^2.3.0        # Persisted user settings (view mode, sidebar width, etc.)
  url_launcher: ^6.3.0              # Open files with default app via macOS

dev_dependencies:
  build_runner: ^2.4.0
  freezed: ^2.5.0
  riverpod_generator: ^2.6.1
  flutter_test: sdk
  mockito: ^5.4.0
  integration_test: sdk
```

### Platform Channels (Swift ↔ Dart)

A **single `MethodChannel('com.explorer.native')`** with categorized methods:

| Channel Method | Purpose | Why Dart Can't Do It |
|---|---|---|
| `getVolumes` | List mounted volumes (`/Volumes/*`) with metadata | `NSFileManager` volume enumeration + icons |
| `getFileMetadata` | Extended attributes, Spotlight metadata, Finder tags | `MDItemRef`, `NSURL` resource values |
| `getFileIcon` | System icon for any file/UTI at arbitrary size | `NSWorkspace.icon(forFile:)` |
| `moveToTrash` | Move files to Trash (not permanent delete) | `NSFileManager.trashItem(at:)` |
| `revealInFinder` | Show file in native Finder | `NSWorkspace.activateFileViewerSelecting` |
| `openWith` | Open file with specific app | `NSWorkspace.open(_:withApplicationAt:)` |
| `spotlight` | Full-text search via Spotlight index | `NSMetadataQuery` |
| `getQuickLookPreview` | Thumbnail / preview of file | `QLThumbnailGenerator` |
| `setFileTags` | Read/write Finder color tags | `NSURL.setResourceValues` |
| `requestPermissions` | Request Full Disk Access / folder access | Security-scoped bookmarks |
| `fsWatch` | Native `FSEvents` stream for directory changes | More efficient than `dart:io` watch on macOS |

---

## 2. Architecture

### Pattern: Feature-First Clean Architecture with Riverpod

```
lib/
├── main.dart                          # App entry, ProviderScope, window setup
├── app.dart                           # FluentApp widget, theme, router
│
├── core/                              # Shared infrastructure
│   ├── platform/
│   │   ├── native_channel.dart        # Single MethodChannel wrapper
│   │   ├── native_channel_impl.dart   # Swift method dispatch
│   │   └── permissions.dart           # macOS entitlements / TCC checks
│   ├── filesystem/
│   │   ├── fs_entity.dart             # Unified model: file, folder, volume, alias
│   │   ├── fs_service.dart            # Abstract FS operations (list, copy, move, delete…)
│   │   ├── fs_service_impl.dart       # dart:io + platform channel implementation
│   │   ├── fs_watcher.dart            # Directory change stream (FSEvents via channel)
│   │   └── clipboard.dart             # Cut/Copy/Paste buffer (paths + operation type)
│   ├── models/
│   │   ├── tab_state.dart             # Per-tab navigation state
│   │   ├── view_mode.dart             # Enum: details, icons, tiles, list
│   │   ├── sort_config.dart           # Column + direction
│   │   └── selection.dart             # Multi-select model
│   ├── theme/
│   │   ├── explorer_theme.dart        # Fluent theme overrides to match Win Explorer
│   │   └── icon_mapping.dart          # File extension → icon mapping
│   └── utils/
│       ├── debounce.dart
│       ├── file_size_fmt.dart
│       └── keyboard_shortcuts.dart    # Intent/Action bindings
│
├── features/
│   ├── shell/                         # App chrome: title bar, tab bar, status bar
│   │   ├── shell_page.dart            # Top-level scaffold
│   │   ├── tab_bar_widget.dart        # Windows 11-style tabs
│   │   ├── address_bar.dart           # Breadcrumb path bar
│   │   ├── toolbar.dart               # Ribbon / CommandBar
│   │   └── status_bar.dart            # Item count, selection info
│   │
│   ├── navigation/                    # Left sidebar
│   │   ├── navigation_pane.dart       # Quick Access, This Mac, tree view
│   │   ├── folder_tree.dart           # Lazy-loaded TreeView
│   │   └── favorites_provider.dart    # Pinned folders
│   │
│   ├── browser/                       # Main content area
│   │   ├── browser_view.dart          # Switches between view modes
│   │   ├── details_view.dart          # Sortable column table (DataTable2 or custom)
│   │   ├── icons_view.dart            # Grid of icon+name tiles
│   │   ├── tiles_view.dart            # Larger tiles with metadata
│   │   ├── list_view.dart             # Compact single-column list
│   │   ├── file_item_widget.dart      # Individual file/folder row or tile
│   │   └── column_header.dart         # Sortable, resizable column header
│   │
│   ├── preview/                       # Preview pane (right sidebar toggle)
│   │   ├── preview_pane.dart          # Container with toggle button
│   │   ├── image_preview.dart         # Inline image rendering
│   │   ├── text_preview.dart          # First N lines of text files
│   │   └── quicklook_preview.dart     # Native QuickLook via platform channel
│   │
│   ├── search/                        # Search UI + Spotlight integration
│   │   ├── search_bar.dart            # Expandable search input
│   │   ├── search_results.dart        # Results list (reuses browser views)
│   │   └── search_provider.dart       # Spotlight query + dart:io fallback
│   │
│   ├── operations/                    # File operations
│   │   ├── file_operations.dart       # Copy, move, delete, rename orchestration
│   │   ├── progress_dialog.dart       # Transfer progress with cancel
│   │   ├── conflict_dialog.dart       # "File already exists" resolution
│   │   └── new_folder_dialog.dart     # Create new folder inline
│   │
│   ├── properties/                    # File/folder properties dialog
│   │   ├── properties_dialog.dart     # Multi-tab dialog
│   │   ├── general_tab.dart           # Name, size, dates, location
│   │   └── permissions_tab.dart       # POSIX permissions display
│   │
│   └── context_menu/                  # Right-click menus
│       ├── context_menu_builder.dart   # Builds menu based on selection
│       └── menu_actions.dart           # Maps menu items → operations
│
├── providers/                         # Global Riverpod providers
│   ├── fs_provider.dart               # FsService provider
│   ├── directory_provider.dart        # Current directory listing (per tab)
│   ├── selection_provider.dart        # Selected items
│   ├── clipboard_provider.dart        # Cut/Copy state
│   ├── settings_provider.dart         # User preferences
│   ├── tab_provider.dart              # Tab list + active tab
│   └── navigation_provider.dart       # Breadcrumb history stack
│
macos/                                 # Native macOS runner
├── Runner/
│   ├── AppDelegate.swift              # Platform channel registration
│   ├── NativeChannel.swift            # Swift implementation of all channel methods
│   ├── FileSystemBridge.swift         # NSFileManager / NSURL wrappers
│   ├── SpotlightBridge.swift          # NSMetadataQuery wrapper
│   ├── QuickLookBridge.swift          # QLThumbnailGenerator wrapper
│   └── Info.plist                     # Entitlements, sandbox config
│   └── Runner.entitlements            # com.apple.security.files.user-selected (+ bookmarks)
```

### Data Flow (per tab)

```
User navigates to /Users/john/Documents
       │
       ▼
AddressBar updates breadcrumb ──► NavigationProvider.push(path)
       │
       ▼
DirectoryProvider(tabId).watch(path)
       │
       ├──► dart:io Directory(path).list()   →  List<FsEntity>
       ├──► NativeChannel.getFileIcon()      →  Icon data per file
       └──► FsWatcher.watch(path)            →  Stream<FsEvent> (auto-refresh)
       │
       ▼
BrowserView rebuilds with sorted/filtered List<FsEntity>
       │
       ▼
StatusBar shows "${items.length} items, ${selected.length} selected"
```

### State Architecture (Riverpod)

```dart
// Per-tab state — each tab has independent navigation + selection
@riverpod
class TabState extends _$TabState {
  @override
  ExplorerTab build(String tabId) => ExplorerTab.initial();
}

// Directory listing — auto-disposes when tab closes
@riverpod
Future<List<FsEntity>> directoryListing(ref, {required String path}) async {
  final fsService = ref.watch(fsServiceProvider);
  final entities = await fsService.listDirectory(path);
  // Auto-refresh on FS changes
  final watcher = ref.watch(fsWatcherProvider(path));
  ref.listen(watcher, (_, __) => ref.invalidateSelf());
  return entities;
}

// Selection — multi-select with Shift/Cmd click support
@riverpod
class Selection extends _$Selection {
  @override
  SelectionState build(String tabId) => SelectionState.empty();

  void select(FsEntity entity, {bool extend = false, bool range = false}) { ... }
  void selectAll(List<FsEntity> entities) { ... }
  void clear() { ... }
}
```

---

## 3. Key Components / Views — Build Guide

### 3.1 Shell / App Chrome

#### TabBar (Windows 11 style)
- Use `fluent_ui` `TabView` widget — it already implements Windows 11 tab UX (draggable, closeable, "+" button).
- Each tab holds a `TabState` (current path, history stack, view mode, selection).
- Middle-click to close, Ctrl+T to add, Ctrl+W to close.

#### Address Bar / Breadcrumb
- **Custom widget** built from a `Row` of `Button` segments.
- Each segment = one path component. Clicking navigates to that ancestor.
- A small "▸" dropdown on each segment lists sibling folders (like Windows).
- Clicking the whitespace area converts breadcrumb → editable `TextBox` (type-to-navigate).
- `fluent_ui` `BreadcrumbBar` can serve as starting point but needs heavy customization.

#### Toolbar / CommandBar
- `fluent_ui` `CommandBar` with `CommandBarButton` items.
- Groups: **Clipboard** (Cut, Copy, Paste) | **Organize** (Move to, Copy to, Delete, Rename) | **New** (New Folder, New File) | **View** (Icons, Details, Tiles, Preview pane toggle) | **Selection** (Select all, Select none, Invert).
- Overflow menu for less-common actions.
- Buttons enable/disable based on `selectionProvider` state.

#### Status Bar
- Simple `Container` at bottom: left-aligned item count, right-aligned selection count + total size.
- Toggle visibility in View menu.

### 3.2 Navigation Pane (Left Sidebar)

- `fluent_ui` `NavigationPane` in `open` mode provides the sidebar frame.
- **Quick Access / Favorites** section: `ListView` of pinned `ListTile`s with drag-to-reorder. Persisted via `shared_preferences`.
- **This Mac** section: calls `NativeChannel.getVolumes()` to list mounted disks/volumes. Each volume is a `TreeViewItem`.
- **Folder Tree**: Lazy `TreeView` — children loaded on expand via `Directory(path).list()`. Only directories shown. Highlights current path. Expand state cached in memory.
- **Resizable pane divider**: `GestureDetector` on the divider edge; drag to resize sidebar width (persisted).

### 3.3 Browser / Content Area

#### Details View (Table)
- Custom `ScrollableWidget` with a sticky `ColumnHeader` row and a `ListView.builder` body.
- Columns: Name, Date Modified, Type, Size (default). User can reorder & resize columns.
- `ColumnHeader` widget: click to sort (toggles asc/desc), drag edge to resize, right-click to show/hide columns.
- Each row is a `FileItemWidget` — shows icon, name (editable on F2), metadata cells.
- Row selection: click = select, Ctrl+click = toggle, Shift+click = range.
- Alternating row colors for readability.

#### Icons View (Grid)
- `GridView.builder` with `SliverGridDelegateWithMaxCrossAxisExtent`.
- Each cell: large icon (48–96px via `NativeChannel.getFileIcon`) + filename below.
- Slider in toolbar controls icon size.

#### Tiles View
- Similar to Icons but horizontal layout: icon on left, name + type + size on right.
- `GridView` with wider aspect ratio cells.

### 3.4 Preview Pane

- Toggled via toolbar button. Appears as right sidebar (resizable).
- Content depends on selected file type:
  - **Images**: `Image.file()` with fit.
  - **Text/Code**: First 100 lines via `File.readAsString()`, displayed in `SelectableText` with monospace font.
  - **PDF/Documents**: `NativeChannel.getQuickLookPreview()` → renders thumbnail image.
  - **No selection / Folder**: Shows folder info (item count, total size).

### 3.5 Context Menus

- `GestureDetector` with `onSecondaryTapDown` on file items and empty space.
- `fluent_ui` `showMenu()` or custom `Flyout` widget.
- **File context menu**: Open, Open With ▸, Cut, Copy, Delete, Rename, Properties, Copy Path, Reveal in Finder.
- **Background context menu**: New Folder, New File, Paste, View options, Sort by, Properties.
- **Navigation pane context menu**: Pin to Quick Access, Remove from Quick Access, Properties.

### 3.6 Drag and Drop

- **Internal DnD** (within app): `Draggable` + `DragTarget` on file items and folder nodes.
  - Drag to folder = move. Drag + Option key = copy.
  - Visual feedback: insertion indicator, folder highlight on hover.
- **External DnD** (from/to Finder): `desktop_drop` package for drops into the app.
  - Register `DropTarget` on the browser view.
  - For dragging out: requires platform channel to create `NSPasteboardItem` (Medium complexity).

### 3.7 Search

- `AutoSuggestBox` in the toolbar area (fluent_ui widget).
- Typing triggers debounced search:
  1. **Fast path**: `dart:io` directory listing with name filter (current folder + optional recursive).
  2. **Deep path**: `NativeChannel.spotlight(query, scope)` → `NSMetadataQuery` for indexed full-text search.
- Results displayed in the browser view with breadcrumb showing "Search Results in /path".
- Highlight matching text in file names.

### 3.8 Properties Dialog

- `fluent_ui` `ContentDialog` with tab navigation.
- **General tab**: icon, name (editable), type, location, size (async computed for folders), created/modified dates, attributes.
- **Permissions tab**: POSIX owner/group/other read/write/execute checkboxes (display; editing requires elevated privileges).
- Multi-select properties: shows "Multiple items", aggregate size.

### 3.9 Keyboard Shortcuts

Implement via Flutter's `Shortcuts` + `Actions` widget tree:

| Shortcut | Action |
|---|---|
| `Cmd+C` | Copy |
| `Cmd+V` | Paste |
| `Cmd+X` | Cut |
| `Delete` / `Cmd+Backspace` | Move to Trash |
| `Enter` | Open / Rename (context-dependent) |
| `Space` | Quick Look preview (macOS convention) |
| `Cmd+Shift+N` | New Folder |
| `Cmd+A` | Select All |
| `Cmd+T` | New Tab |
| `Cmd+W` | Close Tab |
| `Cmd+F` | Focus Search |
| `Cmd+[` / `Cmd+]` | Back / Forward |
| `Cmd+↑` | Go to parent folder |
| `F2` | Rename |
| `Arrow keys` | Navigate items |
| `Cmd+1/2/3/4` | Switch view mode |

---

## 4. File System Interaction

### Layer 1: dart:io (Direct)
```dart
// Listing
final dir = Directory(path);
final entities = await dir.list().toList();  // List<FileSystemEntity>

// Metadata
final stat = await entity.stat();  // size, modified, accessed, type

// CRUD
await File(src).copy(dest);
await File(path).delete();
await entity.rename(newPath);  // move or rename
await Directory(path).create();

// Watching
final stream = dir.watch(recursive: false);  // FileSystemEvent stream
```

**Limitations of dart:io on macOS:**
- No volume enumeration
- No file icons / thumbnails
- No Trash (only permanent delete)
- No extended attributes or Finder tags
- No Spotlight search
- No security-scoped bookmarks for sandboxed access
- `FileSystemEntity.stat()` doesn't include creation date on macOS (use platform channel)

### Layer 2: Platform Channels (Swift Bridge)

```swift
// macos/Runner/NativeChannel.swift
import Cocoa
import QuickLookThumbnailing

class NativeChannel {
    static let channel = FlutterMethodChannel(
        name: "com.explorer.native",
        binaryMessenger: registrar.messenger
    )

    static func register(with registrar: FlutterPluginRegistrar) {
        channel.setMethodCallHandler { call, result in
            switch call.method {
            case "getVolumes":
                let volumes = FileManager.default.mountedVolumeURLs(
                    includingResourceValuesForKeys: [.volumeNameKey, .volumeTotalCapacityKey],
                    options: [.skipHiddenVolumes]
                )
                // Map to dictionaries and return
                result(volumes.map { ... })

            case "moveToTrash":
                let url = URL(fileURLWithPath: call.arguments as! String)
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                result(true)

            case "getFileIcon":
                let path = call.arguments as! String
                let image = NSWorkspace.shared.icon(forFile: path)
                let tiff = image.tiffRepresentation
                let png = NSBitmapImageRep(data: tiff!)!.representation(using: .png, properties: [:])
                result(FlutterStandardTypedData(bytes: png!))

            case "spotlight":
                // Launch NSMetadataQuery, stream results back via EventChannel
                ...

            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }
}
```

### Layer 3: Async Operations with Progress

For long-running operations (copy large files, recursive folder operations):

```dart
class FileOperationService {
  /// Copy with progress reporting via Isolate
  Stream<OperationProgress> copyWithProgress(String src, String dest) async* {
    // Use Isolate for heavy I/O to keep UI thread free
    final receivePort = ReceivePort();
    await Isolate.spawn(_copyWorker, _CopyParams(src, dest, receivePort.sendPort));
    await for (final progress in receivePort) {
      if (progress is OperationProgress) yield progress;
      if (progress is OperationComplete) break;
    }
  }
}
```

### Sandbox Considerations

For **Mac App Store distribution**, the app must be sandboxed:
- Use `com.apple.security.files.user-selected.read-write` entitlement.
- Persist access via **security-scoped bookmarks** (Swift platform channel).
- Without App Store: can use `com.apple.security.app-sandbox = false` for full disk access (simpler but not Store-eligible).

**Recommendation**: Start unsandboxed for development velocity. Add sandboxing as a late-stage hardening step if App Store distribution is desired.

---

## 5. Build System

### Project Setup

```bash
flutter create --platforms=macos --org com.explorer explorer_app
cd explorer_app
flutter config --enable-macos-desktop
```

### macOS Runner Configuration

**`macos/Runner.xcodeproj` settings:**
- Deployment target: **macOS 13.0** (Ventura) — required for modern SwiftUI interop and QLThumbnailGenerator
- Architecture: `arm64` (Apple Silicon native) + optional `x86_64` for universal binary
- Swift version: 5.9+
- Enable Hardened Runtime

**`macos/Runner/Info.plist` additions:**
```xml
<key>NSDesktopFolderUsageDescription</key>
<string>Explorer needs access to browse your files.</string>
<key>NSDocumentsFolderUsageDescription</key>
<string>Explorer needs access to browse your Documents.</string>
<key>NSDownloadsFolderUsageDescription</key>
<string>Explorer needs access to browse your Downloads.</string>
<key>FLTEnableImpeller</key>
<true/>
```

**`macos/Runner/Runner.entitlements`:**
```xml
<key>com.apple.security.app-sandbox</key>
<false/>  <!-- true for App Store -->
<key>com.apple.security.files.user-selected.read-write</key>
<true/>
<key>com.apple.security.network.client</key>
<true/>  <!-- for potential network drive access -->
```

### Universal Binary Build

```bash
# ARM64 only (recommended for Apple Silicon targeting)
flutter build macos --release

# Universal binary (arm64 + x86_64) — requires Rosetta-compatible deps
flutter build macos --release
# Then in Xcode: set ARCHS = "arm64 x86_64" in build settings
# Or use lipo to combine:
lipo -create build/arm64/Explorer.app build/x86_64/Explorer.app -output Explorer.app
```

### Code Signing & Notarization

```bash
# 1. Sign with Developer ID
codesign --deep --force --verify --verbose \
  --sign "Developer ID Application: Your Name (TEAM_ID)" \
  --options runtime \
  --entitlements macos/Runner/Runner.entitlements \
  build/macos/Build/Products/Release/Explorer.app

# 2. Create DMG or ZIP for notarization
hdiutil create -volname Explorer -srcfolder build/macos/Build/Products/Release/Explorer.app \
  -ov -format UDZO Explorer.dmg

# 3. Submit for notarization
xcrun notarytool submit Explorer.dmg \
  --apple-id "you@email.com" \
  --team-id TEAM_ID \
  --password "@keychain:AC_PASSWORD" \
  --wait

# 4. Staple
xcrun stapler staple Explorer.dmg
```

### CI/CD (GitHub Actions)

```yaml
# .github/workflows/build.yml
jobs:
  build-macos:
    runs-on: macos-14  # M1 runner for Apple Silicon native
    steps:
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.27.x'
          channel: stable
      - run: flutter pub get
      - run: flutter analyze
      - run: flutter test
      - run: flutter build macos --release
      - run: # codesign + notarize steps
```

---

## 6. Feature Complexity Estimates

| # | Feature | Complexity | Effort (dev-days) | Notes |
|---|---|---|---|---|
| 1 | Project scaffolding + fluent_ui theme | Low | 2 | Boilerplate + theme tuning |
| 2 | Navigation pane (sidebar) with tree view | Medium | 5 | Lazy loading, expand/collapse state, volume listing |
| 3 | Quick Access / Favorites | Low | 2 | CRUD list + persistence |
| 4 | Address bar / breadcrumb | Medium | 4 | Segment click, dropdown siblings, edit mode toggle |
| 5 | Details view (table with sortable columns) | High | 7 | Custom table: sort, resize, reorder columns, virtual scroll |
| 6 | Icons view (grid) | Low | 2 | GridView.builder + icon loading |
| 7 | Tiles view | Low | 2 | Variant of icons view |
| 8 | View mode switching | Low | 1 | State toggle, smooth transition |
| 9 | Toolbar / CommandBar | Medium | 3 | Action mapping, enable/disable logic, overflow |
| 10 | Status bar | Low | 1 | Reactive text |
| 11 | Tab support | Medium | 5 | Independent state per tab, tab reorder, keyboard shortcuts |
| 12 | File operations (copy, move, delete, rename) | High | 6 | Isolate-based, progress, conflict resolution, undo |
| 13 | Trash integration | Medium | 2 | Platform channel (moveToTrash) |
| 14 | Context menus | Medium | 4 | Dynamic menu building, action dispatch |
| 15 | Drag and drop (internal) | High | 5 | Multi-item drag, hover-to-open folders, visual feedback |
| 16 | Drag and drop (external / Finder) | High | 4 | Platform channel for NSPasteboard |
| 17 | Search (basic name filter) | Low | 2 | String matching on listing |
| 18 | Search (Spotlight integration) | High | 5 | NSMetadataQuery bridge, result streaming |
| 19 | Preview pane | Medium | 5 | Type detection, image/text/QuickLook rendering |
| 20 | File icons (native) | Medium | 3 | Platform channel + caching (LRU with icon data) |
| 21 | Keyboard shortcuts | Medium | 3 | Shortcuts/Actions tree, focus management |
| 22 | Properties dialog | Medium | 3 | Multi-tab dialog, async size calculation |
| 23 | Dual / Split pane | Medium | 4 | Two independent browser instances side-by-side |
| 24 | File system watching (live refresh) | Medium | 3 | FSEvents bridge, debounced UI refresh |
| 25 | Permissions / entitlements / sandbox | High | 4 | Security-scoped bookmarks, TCC prompts |
| 26 | Performance (large directories 10k+ files) | High | 5 | Virtual scrolling, pagination, Isolate listing |
| 27 | Code signing + notarization | Medium | 2 | One-time setup + CI automation |
| | **TOTAL** | | **~92 dev-days** | ~4.5 months solo / ~2 months with 2–3 devs |

---

## 7. Pros and Cons

### ✅ Pros

| Pro | Details |
|---|---|
| **fluent_ui is purpose-built** | The `fluent_ui` package directly implements Microsoft Fluent Design — `TabView`, `TreeView`, `NavigationPane`, `CommandBar`, `ContentDialog`, `BreadcrumbBar` are all Windows-native widgets out of the box. |
| **Pixel-perfect custom rendering** | Flutter's custom rendering engine means every pixel is under your control. No fighting with native widget constraints. Windows Explorer's exact spacing, colors, and animations can be replicated. |
| **Single codebase cross-platform** | The same app could later ship on Windows and Linux with minimal changes. The Explorer could eventually run on actual Windows. |
| **Hot reload** | Sub-second iteration on UI changes during development. Massive productivity boost for a UI-heavy app. |
| **Impeller on Metal** | Smooth 120fps rendering on Apple Silicon with no shader compilation jank. GPU-accelerated drawing of complex file grids. |
| **Strong async/Isolate model** | Dart's `async/await` + `Isolate` let you do heavy file I/O without blocking the UI — critical for copying large files or listing huge directories. |
| **Mature state management** | Riverpod handles complex per-tab independent state cleanly with compile-time safety and auto-disposal. |
| **Growing desktop ecosystem** | `window_manager`, `desktop_drop`, `flutter_acrylic` etc. fill most desktop-specific gaps. |

### ❌ Cons

| Con | Details |
|---|---|
| **Non-native rendering = non-native feel** | Flutter draws its own pixels — text selection, scroll physics, focus rings, and cursor behavior won't feel like native macOS apps. Users may notice. |
| **No native text input integration** | macOS text input (spell check, text replacement, dictation, input methods) works through `NSTextInputClient`. Flutter's text fields have historically had IME and accessibility issues on macOS. |
| **Platform channel overhead** | Every native macOS API call (file icons, Spotlight, Trash) requires serialization across the platform channel. Icon loading for 1000 files means 1000 round-trips unless batched carefully. |
| **Accessibility gaps** | Flutter's macOS accessibility support has improved but still lags behind native AppKit/SwiftUI. VoiceOver support for custom widgets like the file table will require manual `Semantics` annotation. |
| **App size** | Flutter macOS apps ship with the engine (~30–50MB). A native SwiftUI equivalent would be <5MB. |
| **macOS sandbox complexity** | Flutter's plugin ecosystem doesn't handle security-scoped bookmarks or TCC (Transparency, Consent, Control) well. Significant Swift bridge code needed. |
| **Desktop maturity** | Flutter desktop is GA but less battle-tested than mobile. Edge cases (window management, multi-monitor, retina scaling) may surface bugs. |
| **Memory for file icons** | Loading and caching native file icons as PNG bitmaps across the platform channel is memory-intensive. Need careful LRU cache management. |
| **No native drag-and-drop out of the box** | Dragging files TO Finder from a Flutter app requires writing NSPasteboard code in Swift. The Flutter side only handles in-app drag targets natively. |
| **Menu bar integration** | macOS apps use the system menu bar. Flutter supports basic menu bar via `PlatformMenuBar`, but complex dynamic menus require platform channel work. |

### Comparison Position

| Criterion | Flutter | SwiftUI | Electron | Tauri |
|---|---|---|---|---|
| **Windows look fidelity** | ★★★★★ (fluent_ui) | ★★☆☆☆ (fight native feel) | ★★★★☆ (CSS) | ★★★★☆ (CSS) |
| **macOS native feel** | ★★☆☆☆ | ★★★★★ | ★★☆☆☆ | ★★★☆☆ |
| **File system depth** | ★★★☆☆ | ★★★★★ | ★★★☆☆ | ★★★★☆ |
| **Performance** | ★★★★☆ | ★★★★★ | ★★☆☆☆ | ★★★★☆ |
| **App size** | ★★☆☆☆ (50MB) | ★★★★★ (<5MB) | ★☆☆☆☆ (150MB+) | ★★★★☆ (~15MB) |
| **Dev speed** | ★★★★☆ | ★★★☆☆ | ★★★★★ | ★★★☆☆ |
| **Cross-platform** | ★★★★★ | ★☆☆☆☆ | ★★★★★ | ★★★★★ |

---

## 8. Apple Silicon Optimization

### Build Targets

| Build Type | Arch | Use Case | How |
|---|---|---|---|
| **arm64-only** | `arm64` | Apple Silicon Macs (M1–M4) — 100% of new Macs | Default `flutter build macos` output |
| **Universal Binary** | `arm64 + x86_64` | Support Intel Macs too | Xcode `ARCHS = "arm64 x86_64"` or `lipo` merge |
| **Recommended** | `arm64` only | Smaller binary, no Rosetta overhead, simpler CI | Unless Intel support required |

### Dart AOT Compilation

- Flutter macOS release builds use **Dart AOT (Ahead-of-Time)** compilation → native ARM64 machine code.
- No JIT, no interpreter at runtime. Near-native CPU performance.
- `dart:isolate` utilizes Apple Silicon's performance/efficiency core architecture — heavy file I/O can run on E-cores while UI stays on P-cores (managed by macOS scheduler).

### Impeller Rendering (Metal)

- **Enable**: Set `FLTEnableImpeller = YES` in `Info.plist` (or will be default in future Flutter releases).
- Impeller pre-compiles all shaders at build time. Zero runtime shader compilation stutter.
- Uses Metal API directly on macOS → leverages Apple Silicon's unified memory architecture (CPU and GPU share memory, no copying).
- Texture atlasing for file icons reduces draw calls when rendering large icon grids.
- Expected frame budget: **<8ms per frame** at 120Hz on M-series chips for typical file browser UI.

### Memory Optimization for Apple Silicon

```dart
// Use Isolates for heavy directory listing — runs on efficiency cores
final listing = await Isolate.run(() {
  return Directory(path).listSync()
    .map((e) => FsEntity.fromStat(e, e.statSync()))
    .toList();
});

// LRU icon cache to avoid repeated platform channel calls
class IconCache {
  final _cache = LinkedHashMap<String, Uint8List>();
  static const maxSize = 500;  // 500 icons × ~4KB avg = ~2MB

  Uint8List? get(String path) => _cache[path];
  void put(String path, Uint8List data) {
    if (_cache.length >= maxSize) _cache.remove(_cache.keys.first);
    _cache[path] = data;
  }
}
```

### Benchmark Targets

| Metric | Target | Tool |
|---|---|---|
| App launch (cold) | < 800ms | Stopwatch + os_signpost |
| Directory listing (1000 items) | < 200ms | Flutter DevTools timeline |
| Scroll FPS (details view, 10k items) | 120fps (ProMotion) | Flutter DevTools performance |
| File copy throughput | Match Finder | Isolate-based I/O |
| Memory (idle, 1 tab) | < 150MB | Xcode Instruments |
| Memory (5 tabs, 5k items each) | < 400MB | Xcode Instruments |

---

## 9. Timeline / Phases

### Phase 1 — Foundation (Weeks 1–3)
- Flutter project scaffolding with fluent_ui
- Window management (title bar, resize, min/max/close)
- App shell: sidebar + content area + status bar layout
- Theme matching Windows Explorer color palette
- Platform channel skeleton (Swift side)
- Core models: `FsEntity`, `ViewMode`, `SortConfig`
- Basic directory listing via `dart:io`
- Navigation: click folder → list contents → breadcrumb updates

**Deliverable**: App opens, shows files in a directory, can navigate by clicking folders.

### Phase 2 — Core Browser (Weeks 4–6)
- Details view with sortable columns (Name, Size, Date, Type)
- Icons view and Tiles view
- View mode switching
- Column resize and reorder
- Selection model (click, Ctrl+click, Shift+click, rubber-band)
- Toolbar / CommandBar with view actions
- File icons via platform channel (with LRU cache)
- Status bar (item count, selection info)

**Deliverable**: Fully functional multi-view file browser with selection.

### Phase 3 — Navigation & Tabs (Weeks 7–9)
- Navigation pane: Quick Access, This Mac (volumes), folder tree
- Folder tree lazy loading with expand/collapse
- Address bar: breadcrumb segments, dropdown siblings, edit mode
- Back/Forward/Up navigation with history stack
- Tab support: new tab, close tab, switch tab, independent state
- Favorites management (pin/unpin folders)

**Deliverable**: Multi-tab explorer with full navigation.

### Phase 4 — File Operations (Weeks 10–12)
- Copy, Move (via Isolates with progress)
- Delete → Move to Trash (platform channel)
- Rename (inline editing in details view)
- New Folder / New File
- Progress dialog with cancel
- Conflict resolution dialog ("Replace", "Skip", "Rename")
- Undo support (operation history)
- Clipboard (Cut/Copy/Paste state)

**Deliverable**: All CRUD file operations working with progress UI.

### Phase 5 — Advanced Features (Weeks 13–16)
- Context menus (right-click on files, folders, empty space)
- Drag and drop (internal: file → folder)
- Drag and drop (external: Finder ↔ app)
- Keyboard shortcuts (full set from Section 3.9)
- Search: basic name filter + Spotlight integration
- Preview pane with image/text/QuickLook support
- Properties dialog (General + Permissions tabs)
- Dual/split pane mode

**Deliverable**: Feature-complete explorer matching Windows Explorer capabilities.

### Phase 6 — Polish & Ship (Weeks 17–19)
- Performance optimization (virtual scrolling for 10k+ items)
- File system watching (live refresh on external changes)
- Accessibility (VoiceOver, keyboard navigation audit)
- Error handling (permissions denied, disk full, network drives)
- macOS sandbox entitlements (if App Store)
- Code signing and notarization
- CI/CD pipeline
- Testing: unit tests (models, providers), widget tests (views), integration tests (file operations)
- DMG packaging with background image + Applications alias

**Deliverable**: Shippable v1.0 application.

### Total: ~19 weeks (4.5 months) solo developer | ~10 weeks with 2 devs

---

## 10. Risks and Challenges

### 🔴 Critical Risks

| Risk | Impact | Mitigation |
|---|---|---|
| **Platform channel bottleneck for file icons** | Loading 1000+ native icons serially via MethodChannel is slow (~1-2s). UI feels sluggish. | Batch icon requests (send array of paths, return array of PNGs). Cache aggressively by file extension, not path. Use extension-based icon lookup for common types, only request unique ones. |
| **Details view performance at scale** | Flutter's built-in `DataTable` doesn't virtualize — 10k+ rows will OOM or jank. | Build custom virtualized table with `ListView.builder`. Only render visible rows. Tested approach: ~60 visible rows × 5 columns = 300 widgets max. |
| **Sandbox file access** | macOS TCC (Transparency, Consent, Control) blocks access to ~/Desktop, ~/Documents, ~/Downloads unless user grants permission. App may appear "broken" if permissions aren't requested properly. | Show clear permission dialogs on first launch. Use security-scoped bookmarks to persist access. Gracefully degrade (show locked icon) for denied paths. |
| **Text input on macOS** | Flutter's macOS text input has known issues with IME, dead keys, and text replacement. Address bar and rename field are critical text inputs. | Test extensively with international keyboards. May need to use `PlatformView` for native `NSTextField` in critical input areas (significant complexity). |

### 🟡 Moderate Risks

| Risk | Impact | Mitigation |
|---|---|---|
| **fluent_ui breaking changes** | Package is actively developed; major version updates may break API. | Pin version. Contribute upstream if fixes needed. Have abstraction layer over fluent_ui widgets. |
| **Drag-and-drop from app → Finder** | No Flutter API for this. Requires Swift NSPasteboardItem + NSDraggingSource implementation via platform channel. | Scope as stretch goal. Implement "Copy Path" as interim workaround. |
| **Symlink / alias handling** | macOS aliases vs. POSIX symlinks are different. `dart:io` only handles symlinks. macOS `.alias` files require platform channel. | Detect and resolve both via platform channel. Show appropriate overlay icon. |
| **Network volumes / FUSE mounts** | Slow I/O, disconnections, permission quirks. | Timeout handling, async loading with cancellation, graceful error states. |
| **Large file copy correctness** | Need to handle: sparse files, extended attributes, resource forks, ACLs. `dart:io` `File.copy()` doesn't preserve all metadata. | Use platform channel calling `NSFileManager.copyItem(at:to:)` which preserves macOS-specific metadata. |
| **Multi-monitor / window management** | Flutter macOS window management is less mature than mobile. Multi-window (e.g., detaching tabs) is not straightforward. | Keep single-window multi-tab design. Defer multi-window to v2. |

### 🟢 Lower Risks

| Risk | Impact | Mitigation |
|---|---|---|
| **App binary size** | ~50–80MB is larger than native alternatives. | Acceptable for desktop. Tree-shake, use `--split-debug-info`. |
| **macOS version compatibility** | Targeting macOS 13+ excludes some older Macs. | macOS 13 covers 95%+ of active Macs. Reasonable trade-off for modern API access. |
| **Impeller bugs on macOS** | Impeller is newer than Skia, may have rendering edge cases. | Can fall back to Skia (`FLTEnableImpeller = NO`). Report bugs upstream. Test on multiple Mac models. |

### Key Technical Challenges (ordered by difficulty)

1. **Custom virtualized details table** — No off-the-shelf Flutter widget does Windows-style sortable, resizable, reorderable columns with virtual scroll and multi-select. Must be built from scratch (~7 days).

2. **Platform channel architecture** — Designing a clean, performant Swift ↔ Dart bridge that handles 15+ method types, batching, streaming (FSEvents, Spotlight), and error propagation without becoming a maintenance nightmare.

3. **Per-tab independent state** — Each tab needs its own path, history, selection, scroll position, view mode. Riverpod family providers help but the wiring is complex.

4. **Drag and drop completeness** — Getting parity with Finder's DnD (spring-loaded folders, drop insertion indicator, modifier keys for copy vs. move, cross-app drags) is one of the highest-effort features.

5. **Windows Explorer visual fidelity** — Making a Flutter app *look* exactly like Windows Explorer (specific padding, icon sizes, hover states, selection rectangles, grid lines) requires extensive pixel-level tweaking of fluent_ui themes.

---

## Appendix A: Decision Record

| Decision | Choice | Alternatives Considered | Rationale |
|---|---|---|---|
| UI Library | `fluent_ui` | `macos_ui`, Material 3, custom | Goal is Windows Explorer look. `fluent_ui` is the only package implementing Microsoft's design system. |
| State Management | Riverpod | Bloc, Provider, GetX | Per-tab family providers, code generation, compile safety. Bloc is viable but more boilerplate. |
| Rendering | Impeller | Skia | Pre-compiled shaders, Metal backend, future default. No reason to use legacy Skia on new project. |
| File operations | dart:io + platform channel | FFI to C, shell commands | dart:io covers 80% of needs. Platform channel for macOS-specific APIs. No need for FFI complexity. |
| Sandbox | Start unsandboxed | Full sandbox from day 1 | Reduces development friction. Sandbox can be added later for App Store. |
| Architecture | Feature-first | Layer-first | Scales better as features grow. Each feature is a self-contained module. |

## Appendix B: Package Version Matrix

| Package | Min Version | Flutter SDK | Notes |
|---|---|---|---|
| `fluent_ui` | 4.9.1 | 3.22+ | Dart 3 required |
| `flutter_riverpod` | 2.6.1 | 3.16+ | With riverpod_generator |
| `window_manager` | 0.4.3 | 3.16+ | Stable macOS support |
| `desktop_drop` | 0.5.0 | 3.16+ | Drop target only |
| `flutter_acrylic` | 1.1.4 | 3.16+ | Mica/vibrancy effects |
| `watcher` | 1.1.0 | any | Pure Dart |
| `path_provider` | 2.1.0 | 3.16+ | macOS directory lookup |
| `file_picker` | 8.0.0 | 3.22+ | Native dialogs |

---

*This plan targets a production-quality file explorer. The Flutter approach excels at achieving Windows Explorer visual fidelity on macOS (thanks to fluent_ui's Fluent Design widgets and Flutter's custom rendering) but requires significant platform channel work for deep macOS integration. The primary trade-off vs. SwiftUI is native feel and file system depth; vs. Electron is performance and app size; vs. Tauri is development maturity and the Fluent Design widget library.*
