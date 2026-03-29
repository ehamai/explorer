# AGENTS.md — Explorer AI Agent Instructions

This file is the **source of truth** for how AI agents should work with the Explorer codebase. The `.github/copilot-instructions.md` file points here.

## Git Policy

**Do NOT commit changes automatically.** After completing work, leave changes staged or unstaged so the user can review and commit manually. Never run `git commit` unless the user explicitly asks you to commit.

## Architecture Overview

Explorer is a native macOS file browser built with SwiftUI (macOS 14+/Sonoma). It uses **MVVM + Services** architecture:

```
Views  →  ViewModels  →  Services  →  File System
                ↕
             Models
```

- **Views** read state from ViewModels via `@Environment`; coordinate cross-ViewModel actions
- **ViewModels** manage UI state (`@Observable`, `@MainActor`); delegate I/O to Services
- **Services** handle file I/O, clipboard, directory watching, favorites, drag-drop
- **Models** define data types (FileItem, ViewMode, FileSortDescriptor, tabs, panes)

### State Ownership
```
┌─────────────────────────────────────────────────────────────────────────┐
│  ◀ ▶ ▲   [≡ List ▾]                                    [⫏ Split]      │
├────────────┬────────────────────────────┬───────────────────────────────┤
│  🔍 Search │  Tab1 │ Tab2 │ Tab3       │  Tab1 │ Tab2                  │
│            ├────────────────────────────┼───────────────────────────────┤
│ FAVORITES  │  / ▸ Users ▸ me ▸ Docs    │  / ▸ Users ▸ me ▸ Downloads  │
│  ★ Desktop │════════════════════════════╪═══════════════════════════════│
│  ★ Docs    │  Name       Date     Size │  Name       Date       Size  │
│            │ 📁 src    2 hrs ago  --   │  📄 a.zip  Yesterday  12 MB  │
│ LOCATIONS  │ 📁 docs   3 days ago --   │  📄 b.pdf  Mar 15     1.2 MB │
│  🖥 Desktop│ 📄 README  1 hr ago 4 KB │                               │
│  📄 Docs   ├────────────────────────────┼───────────────────────────────┤
│  🏠 Home   │  12 items · 2 selected    │  3 items        48.2 GB free │
├────────────┴────────────────────────────┴───────────────────────────────┤
│               ← Left Pane (active) →      ← Right Pane →              │
└─────────────────────────────────────────────────────────────────────────┘
```

```
SplitScreenManager (@Observable)
├── leftPane: PaneState
│   └── tabManager: TabManager (@Observable)
│       └── tabs: [BrowserTab]
│           ├── navigationVM: NavigationViewModel (@Observable)
│           └── directoryVM: DirectoryViewModel (@Observable, @MainActor)
└── rightPane: PaneState? (split mode only)
    └── (same structure)
```

### Environment Object Injection
| Object | Scope | Purpose |
|--------|-------|---------|
| SplitScreenManager | Global | Split-screen state, pane activation |
| SidebarViewModel | Global | Favorites, system locations, volumes |
| ClipboardManager | Global | Cut/copy/paste state shared across panes |
| FavoritesManager | Global | Persistent favorites storage |
| TabManager | Per-pane | Tab list and active tab for one pane |
| NavigationViewModel | Per-tab | Navigation history for one tab |
| DirectoryViewModel | Per-tab | Directory contents for one tab |

## Project Structure
```
explorer/
├── AGENTS.md                        # This file — AI agent instructions
├── README.md                        # Project readme
├── Package.swift                    # SPM manifest (macOS 14+, swift-testing 0.12+)
├── .github/
│   └── copilot-instructions.md      # Points to AGENTS.md
├── Explorer/
│   ├── Sources/
│   │   ├── ExplorerApp.swift        # @main entry point, window/scene/command setup
│   │   ├── Helpers/                 # Formatting utilities
│   │   │   └── README.md
│   │   ├── Models/                  # Data types and state managers
│   │   │   └── README.md
│   │   ├── Services/                # File I/O, clipboard, watcher, favorites, drag-drop
│   │   │   └── README.md
│   │   ├── ViewModels/              # DirectoryViewModel, NavigationViewModel, SidebarViewModel
│   │   │   └── README.md
│   │   └── Views/                   # SwiftUI views
│   │       ├── README.md            # Overview, MainView, PaneView
│   │       ├── Components/          # FileIconView, InspectorView
│   │       │   └── README.md
│   │       ├── Content/             # ContentAreaView, FileListView, IconGridView
│   │       │   └── README.md
│   │       ├── Sidebar/             # SidebarView
│   │       │   └── README.md
│   │       ├── StatusBar/           # StatusBarView
│   │       │   └── README.md
│   │       └── Toolbar/             # PathBarView, TabBarView
│   │           └── README.md
│   ├── Resources/
│   │   └── Explorer.entitlements
│   └── Tests/                       # 203 tests across 17 suites
│       └── README.md
```

## Documentation System

### README.md Files
Each source directory and subdirectory contains a `README.md` documenting its components. These are the primary reference for understanding what each component does, its properties, methods, dependencies, and patterns.

### Rules for Maintaining Documentation

**Read before coding:** Always read the relevant README.md file(s) BEFORE making changes to understand current state.

**Update after coding:** When making code changes, update the README.md in the same directory as the changed file. Documentation must stay in sync with the code.

#### When to Update an Existing README.md
- Adding/removing/modifying properties on existing types
- Adding/removing/modifying methods on existing types
- Changing protocol conformances or state management patterns
- Changing error handling behavior
- Adding/removing keyboard shortcuts or menu commands
- Modifying navigation flows or persistence formats

#### When to Create a New README.md
- Adding a new source subdirectory → create `README.md` in that directory
- The new README.md should document only the components in that directory
- Keep it concise and focused — avoid duplicating information from parent README.md files

#### What to Document for New Types

**Model/Struct/Enum:** Purpose, properties (type, access, purpose), methods (signature, behavior), protocol conformances, relationships to other types.

**View:** Purpose, position in view hierarchy, environment dependencies, local state, user interactions handled.

**ViewModel:** Purpose, published properties, core methods, service dependencies, state management patterns.

**Service:** Purpose, public API, concurrency model, error handling strategy, persistence details.

**Test Suite:** Suite name, test count, component tested, key scenarios covered.

#### Granularity Rules
- Each README.md documents **only** the components in its own directory
- Keep content concise — property tables and method signatures, not verbose prose
- If a directory has subdirectories with their own README.md files, the parent README.md should be an overview with links to subdirectory docs
- Avoid cross-referencing implementation details between README.md files; each should be self-contained for its scope

## Coding Conventions

### Architecture
- **MVVM + Services**: Views read state from ViewModels via @Environment; ViewModels delegate I/O to Services
- **ViewModels never reference each other**: Views coordinate cross-ViewModel actions
- **@Observable macro**: Use `@Observable` (not `ObservableObject`) for all new observable types
- **@MainActor**: Apply to any class that manages UI state
- **Dependency injection**: Accept dependencies via init parameters with defaults

### State Management
- Use `@Environment` for dependency injection (not @ObservedObject or @StateObject)
- Use `private(set)` for properties that views should read but not write
- Use `didSet` observers for derived state that should auto-update
- Keep `@State` for view-local state only (not shared state)

### File Operations
- All file I/O goes through `FileSystemService` (actor-isolated)
- Use `async/await` for file operations
- Use `FileManager.trashItem` for deletions (not `removeItem`)
- After file operations, reload affected directories via `directoryVM.loadDirectory` and `splitManager.reloadAllPanes`

### Error Handling
- FileSystemService throws — callers handle errors
- ViewModels currently catch silently (known gap — improve when possible)
- FavoritesManager uses fallback chains for bookmark resolution

### Concurrency
- FileSystemService is a Swift actor — thread-safe by design
- DirectoryViewModel is @MainActor — all state on main thread
- DirectoryWatcher uses GCD with utility QoS
- Views use `Task { await ... }` blocks for async operations

### Views
- Use `@ViewBuilder` for complex conditional content
- Use SwiftUI Table for list views (not List)
- Use LazyVGrid with adaptive columns for grid views
- Context menus should include: Open, Cut/Copy/Paste, Rename, Favorites (folders), Properties, Trash
- Drop targets need validation via FileMoveService

### Naming Conventions
- ViewModels: `*ViewModel` suffix (e.g., `DirectoryViewModel`)
- Services: `*Service`, `*Manager`, or `*Watcher` suffix
- Models: Descriptive names (e.g., `FileItem`, `BrowserTab`, `PaneState`)
- Documentation: Always named `README.md`
- Test files: `*Tests.swift` suffix matching the component name

## Testing

### Framework & Patterns
- Use Swift Testing framework (`@Test`, `@Suite`)
- Create temp directories with UUID-based paths in `.test-tmp/`
- Use shared `TestHelpers` utilities (`makeTempDir`, `createFile`, `createFolder`, `cleanup`, `makeFileItem`)
- Use `defer { TestHelpers.cleanup(dir) }` for cleanup
- Mark suites testing @MainActor types with `@MainActor`
- No mocking — use real FileManager with temp directories
- Accept dependencies via init parameters for testability

### Requirements
- **Every functional change must include unit tests.** Add corresponding tests in the appropriate `*Tests.swift` file.
- **Tests must pass before considering work complete.** Always run `swift test` after functional changes.
- **New types require a new test suite.** Create a matching `*Tests.swift` file with a `@Suite` struct.
- **Test naming:** Descriptive camelCase names (e.g., `navigateToSameURLIsNoOp`, `sortByFieldTogglesSameField`).
- **Test file per component:** Each testable component gets its own test file.
- **Update Tests/README.md** when adding new test suites or significantly expanding existing ones.

## Common Tasks

### Adding a New View
1. Create the view in the appropriate `Explorer/Sources/Views/` subdirectory
2. Add it to the view hierarchy in its parent view
3. Inject necessary environment objects
4. Update the `README.md` in the same subdirectory
5. Update `Explorer/Sources/Views/README.md` if it changes the hierarchy

### Adding a New Service
1. Create in `Explorer/Sources/Services/`
2. Choose concurrency model (actor for shared I/O, @Observable for UI state, class for lifecycle)
3. Accept dependencies via init parameters with defaults for testability
4. Wire it up in ExplorerApp (if app-scoped) or in the consuming ViewModel
5. Update `Explorer/Sources/Services/README.md`
6. Write unit tests in `Explorer/Tests/<ServiceName>Tests.swift`
7. Update `Explorer/Tests/README.md`
8. Run `swift test` to verify

### Adding a New Model
1. Create in `Explorer/Sources/Models/`
2. Define protocol conformances (Identifiable, Hashable, Codable as needed)
3. Write unit tests in `Explorer/Tests/<ModelName>Tests.swift`
4. Update `Explorer/Sources/Models/README.md`
5. Update `Explorer/Tests/README.md`
6. Run `swift test` to verify

### Adding a New ViewModel
1. Create in `Explorer/Sources/ViewModels/`
2. Accept dependencies via init parameters with defaults
3. Mark with `@MainActor` if it manages UI state
4. Write unit tests in `Explorer/Tests/<ViewModelName>Tests.swift`
5. Update `Explorer/Sources/ViewModels/README.md`
6. Update `Explorer/Tests/README.md`
7. Run `swift test` to verify

### Adding a Keyboard Shortcut
1. Add CommandGroup entry in ExplorerApp.swift
2. Implement the action (respecting text editing vs file operation dual-mode pattern)
3. Update the relevant View's README.md
4. Update root `README.md` keyboard shortcuts table if user-facing

### Modifying Existing Functionality
1. Read the relevant README.md file(s) BEFORE starting
2. Make the code changes
3. Add or update unit tests to cover the changed behavior
4. Run `swift test` to verify all tests pass
5. Run `swift build` to verify compilation
6. Update the README.md in the same directory as the changed file

### Refactoring
1. Read the relevant README.md file(s) BEFORE starting
2. Run `swift test` to establish a green baseline BEFORE making changes
3. Make the code changes
4. Run `swift test` to verify nothing broke
5. Run `swift build` to verify compilation
6. Update all affected README.md files

### Adding a New Source Directory
1. Create the directory under `Explorer/Sources/`
2. Create a `README.md` in the new directory documenting its components
3. If it has subdirectories, each gets its own `README.md`
4. Update this file's Project Structure section

## Build & Run
```bash
swift build           # Build
swift run Explorer    # Run
swift test            # Test (203 tests, 17 suites)
swift package clean   # Clean
```

**Requirements:** Swift 5.10+, macOS 14+ (Sonoma), Xcode 15.3+
**Dependencies:** `swift-testing` 0.12+ (test only — no runtime deps)

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
- **User-selected file access**: Read-write
- **Bookmark scoping**: App-scope bookmarks for persistent favorites access

## Persistence
- **Favorites**: `~/Library/Application Support/Explorer/favorites.json`
- **Security bookmarks**: Auto-refreshed on load if stale; fallback chain
- **No other persistence**: Sort, view mode, window state not persisted
