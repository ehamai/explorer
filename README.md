# Explorer

A native macOS file browser built with SwiftUI. Explorer provides a Finder-like experience with dual-pane split-screen, tabbed browsing, drag-and-drop file operations, favorites, and an inspector panel.

## Features

- **Dual-pane split view** — independent left/right panes, each with their own tabs and navigation
- **Tabbed browsing** — multiple tabs per pane with independent history
- **List & icon views** — sortable multi-column table or adaptive icon grid
- **Drag & drop** — move files between directories, panes, tabs, sidebar, and breadcrumbs
- **Cut / Copy / Paste** — full clipboard support across panes
- **Favorites** — persistent sidebar favorites with security-scoped bookmarks
- **Inspector panel** — file metadata, permissions, and properties
- **Search** — real-time case-insensitive filtering of the current directory
- **File system monitoring** — auto-refreshes when files change on disk
- **Path bar** — breadcrumb navigation with an editable mode (supports `~` expansion)

## Requirements

- **macOS 14+** (Sonoma)
- **Swift 5.10+**
- **Xcode 15.3+** (or a compatible Swift toolchain)

## Getting Started

```bash
# Clone the repository
git clone https://github.com/<owner>/explorer.git
cd explorer

# Build
swift build

# Run
swift run Explorer

# Run tests
swift test
```

You can also open the package in Xcode (`File → Open → Package.swift`) and run from there.

## Dependencies

| Dependency | Version | Purpose |
|---|---|---|
| [swift-testing](https://github.com/swiftlang/swift-testing) | 0.12+ | Test framework (dev only) |

There are **no runtime dependencies** — Explorer uses only the Swift standard library, Foundation, AppKit, and SwiftUI.

## Architecture

Explorer follows **MVVM + Services**:

```
Views  →  ViewModels  →  Services  →  File System
                ↕
             Models
```

- **Views** read state from ViewModels via `@Environment` and coordinate cross-ViewModel actions.
- **ViewModels** manage UI state (`@Observable`, `@MainActor`) and delegate I/O to services.
- **Services** handle file operations (`FileSystemService` actor), clipboard, directory watching, favorites persistence, and drag-drop validation.
- **Models** define data types like `FileItem`, `ViewMode`, `FileSortDescriptor`, and tab/pane state.

## Project Structure

```
Explorer/
├── Sources/
│   ├── ExplorerApp.swift        # @main entry point
│   ├── Models/                  # Data types (FileItem, ViewMode, tabs, panes)
│   ├── ViewModels/              # DirectoryViewModel, NavigationViewModel, SidebarViewModel
│   ├── Views/                   # SwiftUI views (MainView, FileListView, IconGridView, …)
│   ├── Services/                # FileSystemService, ClipboardManager, DirectoryWatcher, …
│   └── Helpers/                 # Formatting utilities
├── Resources/
│   └── Explorer.entitlements    # App sandbox configuration
└── Tests/                       # 203 tests across 17 suites
```

## Keyboard Shortcuts

| Shortcut | Action |
|---|---|
| ⌘T | New tab |
| ⌘W | Close tab (or window) |
| ⌘\\ | Toggle split view |
| ⌘⇧N | New folder |
| ⌘[ / ⌘] | Back / Forward |
| ⌘↑ | Enclosing folder |
| ⌘1 / ⌘2 | List view / Icon view |
| ⌘⇧. | Toggle hidden files |
| ⌘X / ⌘C / ⌘V | Cut / Copy / Paste |
| ⌘⌫ | Move to Trash |
| ⌘I | Inspector |
| ⌘A | Select All |

## License

See [LICENSE](LICENSE) for details.
