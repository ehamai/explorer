# Windows File Explorer Clone for macOS — Tauri v2 Implementation Plan

## 1. Technology Stack

| Layer | Technology | Version | Purpose |
|-------|-----------|---------|---------|
| **App Framework** | Tauri | v2.x | Native app shell, IPC, system integration |
| **Backend** | Rust | 1.75+ | File system ops, native APIs, performance-critical logic |
| **Frontend** | React | 18.x | UI rendering |
| **Language** | TypeScript | 5.x | Type-safe frontend code |
| **UI Library** | Fluent UI React v9 (`@fluentui/react-components`) | 9.x | Windows-native look & feel (Microsoft's own design system) |
| **State Mgmt** | Zustand | 4.x | Lightweight, TypeScript-first store (simpler than Redux for desktop apps) |
| **Bundler** | Vite | 5.x | Fast HMR, native ESM, Rust-friendly via `@tauri-apps/cli` |
| **Icons** | `@fluentui/react-icons` | Latest | Windows-consistent iconography |
| **Virtualization** | `@tanstack/react-virtual` | 3.x | Smooth scrolling for 100k+ file lists |
| **DnD** | `@dnd-kit/core` | 6.x | Accessible drag-and-drop |
| **Context Menu** | Custom (Fluent-styled) | — | Right-click menus matching Windows aesthetics |
| **Search** | tantivy (Rust crate) | 0.22+ | Full-text file name/content indexing |
| **File Watching** | notify (Rust crate) | 6.x | Cross-platform FS event monitoring |
| **Date Handling** | date-fns | 3.x | Lightweight date formatting |
| **Testing** | Vitest + Playwright + cargo test | — | Unit, integration, E2E |

### Why Fluent UI v9?
- Microsoft's official design system — pixel-accurate Windows 11 aesthetic
- Built for React, TypeScript-first, tree-shakeable
- Provides `DataGrid`, `Tree`, `Toolbar`, `Breadcrumb`, `TabList`, `Menu`, `Dialog` — all required components
- Theming engine supports Windows light/dark modes out of the box

---

## 2. Architecture

### 2.1 High-Level Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Tauri v2 Shell                        │
│  ┌─────────────────────┐  ┌──────────────────────────┐  │
│  │   WebView (WebKit)  │  │    Rust Core Process     │  │
│  │                     │  │                          │  │
│  │  React + Fluent UI  │◄─┤  Tauri Commands (IPC)    │  │
│  │  TypeScript App     │──►                          │  │
│  │                     │  │  ┌────────────────────┐  │  │
│  │  ┌───────────────┐  │  │  │  fs_operations     │  │  │
│  │  │ Zustand Store │  │  │  │  file_watcher      │  │  │
│  │  │ (app state)   │  │  │  │  search_engine     │  │  │
│  │  └───────────────┘  │  │  │  clipboard_mgr     │  │  │
│  │                     │  │  │  thumbnail_gen      │  │  │
│  │  ┌───────────────┐  │  │  │  archive_handler    │  │  │
│  │  │ React Router  │  │  │  │  trash_manager      │  │  │
│  │  │ (tab routing) │  │  │  │  metadata_reader    │  │  │
│  │  └───────────────┘  │  │  └────────────────────┘  │  │
│  └─────────────────────┘  └──────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

### 2.2 Architecture Pattern: **Command-Query Separation (CQS)**

- **Commands** (mutations): `copy_files`, `move_files`, `delete_files`, `rename_entry`, `create_folder`
- **Queries** (reads): `list_directory`, `get_file_metadata`, `search_files`, `get_disk_info`
- **Events** (Rust → Frontend): `fs-changed`, `operation-progress`, `search-results`, `watch-event`

This maps naturally to Tauri's command/event system.

### 2.3 Rust ↔ JavaScript Bridge Design

```rust
// Tauri command example — Rust side
#[tauri::command]
async fn list_directory(
    path: String,
    sort_by: SortColumn,
    sort_dir: SortDirection,
    show_hidden: bool,
) -> Result<DirectoryListing, AppError> {
    // ... implementation
}

// Serde-serializable types cross the bridge
#[derive(Serialize, Deserialize, specta::Type)]
pub struct DirectoryListing {
    pub path: String,
    pub entries: Vec<FileEntry>,
    pub parent: Option<String>,
    pub total_size: u64,
}

#[derive(Serialize, Deserialize, specta::Type)]
pub struct FileEntry {
    pub name: String,
    pub path: String,
    pub is_dir: bool,
    pub size: u64,
    pub modified: i64,      // Unix timestamp
    pub created: i64,
    pub accessed: i64,
    pub is_hidden: bool,
    pub is_symlink: bool,
    pub extension: Option<String>,
    pub permissions: String, // e.g., "rwxr-xr-x"
    pub file_type: FileType, // enum: Document, Image, Video, Audio, Archive, etc.
    pub icon_data: Option<String>, // base64 thumbnail or icon hint
}
```

```typescript
// TypeScript side — auto-generated types via specta/tauri-specta
import { invoke } from "@tauri-apps/api/core";

const listing = await invoke<DirectoryListing>("list_directory", {
  path: "/Users/john/Documents",
  sortBy: "name",
  sortDir: "asc",
  showHidden: false,
});
```

### 2.4 Type Safety Bridge: `tauri-specta`

Use `tauri-specta` to auto-generate TypeScript types from Rust structs. This eliminates type drift between Rust and TS — a critical advantage over manual type definitions.

### 2.5 Module Breakdown

#### Rust Backend Modules (`src-tauri/src/`)

```
src-tauri/src/
├── main.rs                 # Tauri app setup, plugin registration
├── lib.rs                  # Module declarations
├── commands/
│   ├── mod.rs
│   ├── filesystem.rs       # list_dir, create, delete, rename, copy, move
│   ├── search.rs           # search_files, index_directory
│   ├── clipboard.rs        # copy_to_clipboard, paste_from_clipboard, cut
│   ├── properties.rs       # get_properties, set_permissions
│   ├── favorites.rs        # add/remove/list favorites (Quick Access)
│   ├── disk.rs             # list_volumes, get_disk_space
│   └── preview.rs          # generate_thumbnail, read_file_preview
├── services/
│   ├── mod.rs
│   ├── watcher.rs          # FS event watcher (notify crate)
│   ├── search_index.rs     # tantivy search index management
│   ├── trash.rs            # macOS trash integration (trash crate)
│   ├── thumbnail.rs        # Image thumbnail generation
│   ├── archive.rs          # ZIP/tar extraction & creation
│   └── opener.rs           # open files with default app (open crate)
├── models/
│   ├── mod.rs
│   ├── file_entry.rs       # FileEntry, DirectoryListing
│   ├── sort.rs             # SortColumn, SortDirection
│   ├── search.rs           # SearchQuery, SearchResult
│   └── error.rs            # AppError enum
├── utils/
│   ├── mod.rs
│   ├── permissions.rs      # Unix permission helpers
│   ├── icons.rs            # File type → icon mapping
│   └── size_fmt.rs         # Human-readable size formatting
└── state.rs                # AppState (shared state via Tauri managed state)
```

#### React Frontend Structure (`src/`)

```
src/
├── main.tsx                    # React entry, Fluent UI provider
├── App.tsx                     # Root layout, tab container
├── api/
│   ├── commands.ts             # Typed wrappers around invoke()
│   ├── events.ts               # Tauri event listeners
│   └── types.ts                # Auto-generated from specta (or manual)
├── stores/
│   ├── explorerStore.ts        # Main explorer state (Zustand)
│   ├── tabStore.ts             # Tab management
│   ├── selectionStore.ts       # File selection state
│   ├── clipboardStore.ts       # Cut/copy/paste state
│   ├── settingsStore.ts        # User preferences
│   └── searchStore.ts          # Search state
├── components/
│   ├── layout/
│   │   ├── AppShell.tsx        # Main app layout container
│   │   ├── TitleBar.tsx        # Custom title bar (if frameless)
│   │   └── StatusBar.tsx       # Bottom status bar
│   ├── navigation/
│   │   ├── NavigationPane.tsx  # Left sidebar container
│   │   ├── FolderTree.tsx      # Recursive folder tree
│   │   ├── QuickAccess.tsx     # Favorites/pinned folders
│   │   ├── ThisPC.tsx          # Volumes/disks list
│   │   └── BreadcrumbBar.tsx   # Address bar with path segments
│   ├── toolbar/
│   │   ├── Ribbon.tsx          # Main toolbar/ribbon
│   │   ├── FileOperations.tsx  # Copy, Paste, Delete, etc.
│   │   ├── ViewSwitcher.tsx    # Details/Icons/Tiles toggle
│   │   └── SearchBox.tsx       # Search input
│   ├── content/
│   │   ├── ContentArea.tsx     # Main file listing container
│   │   ├── DetailsView.tsx     # Table/list with sortable columns
│   │   ├── IconsView.tsx       # Grid of file icons
│   │   ├── TilesView.tsx       # Tile cards with preview
│   │   ├── FileRow.tsx         # Single row in details view
│   │   ├── FileIcon.tsx        # File type icon component
│   │   └── EmptyState.tsx      # "This folder is empty"
│   ├── preview/
│   │   ├── PreviewPane.tsx     # Right-side preview panel
│   │   ├── ImagePreview.tsx    # Image file preview
│   │   ├── TextPreview.tsx     # Text/code file preview
│   │   └── MetadataPanel.tsx   # File metadata display
│   ├── tabs/
│   │   ├── TabBar.tsx          # Tab strip (Windows 11 style)
│   │   └── Tab.tsx             # Individual tab
│   ├── dialogs/
│   │   ├── PropertiesDialog.tsx # File/folder properties
│   │   ├── RenameDialog.tsx    # Inline rename
│   │   ├── DeleteConfirm.tsx   # Delete confirmation
│   │   ├── ConflictDialog.tsx  # Copy/move conflict resolution
│   │   └── NewFolderDialog.tsx # Create new folder
│   └── shared/
│       ├── ContextMenu.tsx     # Right-click context menu
│       ├── DragOverlay.tsx     # Drag visual feedback
│       ├── LoadingSpinner.tsx  # Loading states
│       └── VirtualList.tsx     # Virtualized scrolling wrapper
├── hooks/
│   ├── useFileOperations.ts    # Copy/paste/delete orchestration
│   ├── useNavigation.ts       # Path navigation logic
│   ├── useKeyboardShortcuts.ts # Global keyboard handler
│   ├── useContextMenu.ts      # Right-click menu logic
│   ├── useDragDrop.ts         # DnD handlers
│   ├── useFileWatcher.ts      # FS change event subscription
│   └── useSearch.ts           # Search state & debouncing
├── utils/
│   ├── fileTypes.ts            # Extension → type/icon mapping
│   ├── formatters.ts          # Size, date formatting
│   ├── paths.ts               # Path manipulation utilities
│   └── shortcuts.ts           # Keyboard shortcut definitions
└── styles/
    ├── global.css              # Global styles, scrollbar styling
    ├── windows-theme.ts        # Fluent UI theme customization
    └── variables.css           # CSS custom properties
```

---

## 3. Key Components — Detailed Design

### 3.1 Navigation Pane (Left Sidebar)

**Frontend: `NavigationPane.tsx`**
- Uses Fluent UI `Tree` component with lazy-loading children
- Sections: Quick Access (favorites), This Mac (volumes), Home folder tree
- Expand/collapse with arrow indicators
- Drag targets for moving files into folders
- Highlights current folder
- Resizable width via drag handle

**Backend: Rust commands**
- `list_volumes()` → returns mounted drives/volumes
- `list_directory_tree(path, depth)` → returns folder subtree for lazy loading
- `get_favorites()` / `add_favorite(path)` / `remove_favorite(path)` → backed by JSON config file

### 3.2 Content Area (Main View)

**Frontend: `ContentArea.tsx` + view variants**

| View Mode | Component | Key Behavior |
|-----------|-----------|-------------- |
| Details | `DetailsView.tsx` | Fluent UI `DataGrid` — sortable columns (Name, Date Modified, Type, Size), resizable columns, virtualized rows via `@tanstack/react-virtual` |
| Icons | `IconsView.tsx` | CSS Grid of `FileIcon` components, configurable icon sizes (small/medium/large/extra-large) |
| Tiles | `TilesView.tsx` | Cards showing icon + name + type + size, 2-column detail layout |

**Column sorting**: Click column header → invoke `list_directory` with `sort_by`/`sort_dir` params. Sorting happens in Rust for performance (handles 100k+ entries efficiently).

**Selection model**:
- Click = single select
- Ctrl+Click = toggle select
- Shift+Click = range select
- Ctrl+A = select all
- Rubber-band / lasso selection (stretch goal)

### 3.3 Breadcrumb / Address Bar

**Frontend: `BreadcrumbBar.tsx`**
- Displays path as clickable segments: `> Users > john > Documents > Projects`
- Click any segment → navigate to that ancestor
- Click right-arrow between segments → dropdown of sibling folders
- Click empty space or shortcut → converts to editable text input for direct path entry
- Fluent UI `Breadcrumb` component as base, heavily customized

**Backend**: `list_directory(path)` re-invoked on segment click.

### 3.4 Toolbar / Ribbon

**Frontend: `Ribbon.tsx`**
- Simplified ribbon (not full Office ribbon, closer to Windows 11 Explorer command bar)
- Buttons: New ▼ | Cut | Copy | Paste | Rename | Share | Delete | Sort ▼ | View ▼
- Contextual: buttons enable/disable based on selection
- Uses Fluent UI `Toolbar` + `ToolbarButton` + `Menu` for dropdowns

### 3.5 Tabs

**Frontend: `TabBar.tsx`**
- Fluent UI `TabList` with closeable tabs
- Each tab has independent: path, navigation history (back/forward stack), selection, view mode
- "+" button to add new tab
- Middle-click to close tab
- Drag to reorder tabs
- State managed in `tabStore.ts` — each tab is a `TabState` object

```typescript
interface TabState {
  id: string;
  path: string;
  history: string[];         // back stack
  forwardHistory: string[];  // forward stack
  viewMode: "details" | "icons" | "tiles";
  selection: Set<string>;
  sortColumn: SortColumn;
  sortDirection: "asc" | "desc";
  searchQuery: string | null;
}
```

### 3.6 Search

**Frontend: `SearchBox.tsx`**
- Search input in toolbar with debounced input (300ms)
- Results displayed in content area, replacing folder listing
- Shows matched path, highlights search term
- Filter chips: file type, date range, size range (stretch goal)

**Backend: Rust search**
- Phase 1: `walkdir` crate for recursive file name matching (glob patterns)
- Phase 2: `tantivy` crate for full-text content indexing (background index build)
- Search runs in async Rust task, streams results via Tauri events

```rust
#[tauri::command]
async fn search_files(
    app: AppHandle,
    root: String,
    query: String,
    max_results: usize,
) -> Result<(), AppError> {
    // Spawn async task, emit results incrementally
    tokio::spawn(async move {
        for result in walk_and_search(&root, &query) {
            app.emit("search-result", &result).ok();
        }
        app.emit("search-complete", ()).ok();
    });
    Ok(())
}
```

### 3.7 Context Menu

**Frontend: `ContextMenu.tsx`**
- Custom Fluent UI `Menu` triggered on `onContextMenu`
- Context-sensitive items based on:
  - What's right-clicked (file, folder, empty space, sidebar item)
  - Current selection (single vs. multi)
- Standard items: Open, Open With, Cut, Copy, Paste, Delete, Rename, Properties
- Dividers, icons, keyboard shortcut labels
- Nested menus for "New ▶" (Folder, Text Document, etc.)

### 3.8 File Preview Pane

**Frontend: `PreviewPane.tsx`**
- Toggle via View menu or keyboard shortcut (Alt+P)
- Shows preview based on file type:
  - Images: thumbnail/full preview via `<img>` tag with Tauri asset protocol
  - Text: first ~100 lines with syntax highlighting (lightweight, no full editor)
  - PDF: embedded PDF viewer or first-page render
  - Audio/Video: basic metadata display
  - Other: icon + metadata (size, dates, type)
- Resizable panel width

**Backend**:
- `generate_thumbnail(path, size)` → returns base64 image data
- `read_file_preview(path, lines)` → returns first N lines of text files

### 3.9 Properties Dialog

**Frontend: `PropertiesDialog.tsx`**
- Fluent UI `Dialog` with tabs: General, Details
- General: icon, name, type, location, size (computed recursively for folders), created/modified dates
- Details: permissions display, symlink target, extended attributes
- "Calculate size" button for folders (async, shows progress)

**Backend**:
- `get_properties(path)` → comprehensive metadata
- `calculate_directory_size(path)` → async with progress events

### 3.10 Drag & Drop

**Frontend**: `@dnd-kit/core` for intra-app DnD
- Drag files between folders in tree, between content areas
- Visual feedback: ghost image, drop indicators
- Modifier keys: default = move, hold Option = copy

**Backend**: Actual file copy/move via Rust commands.

**Native DnD** (files from/to Finder): Tauri v2 supports drag-and-drop events natively. Listen for `tauri://drag-drop` events.

---

## 4. File System Interaction

### 4.1 Core FS Operations (Rust)

| Operation | Rust Implementation | Notes |
|-----------|-------------------|-------|
| List directory | `std::fs::read_dir` + `std::fs::metadata` | Sorted in Rust, paginated for huge dirs |
| Create file/folder | `std::fs::create_dir` / `std::fs::File::create` | |
| Delete | `trash` crate → moves to macOS Trash | Never hard-delete by default |
| Rename | `std::fs::rename` | Handles cross-volume moves |
| Copy | `fs_extra::copy_items_with_progress` | Progress events via Tauri emit |
| Move | `std::fs::rename` or copy+delete for cross-volume | |
| Read metadata | `std::fs::metadata` + `std::os::unix::fs::MetadataExt` | Unix permissions, timestamps |
| Symlink info | `std::fs::read_link` | Resolve symlink targets |
| Disk info | `sysinfo` crate | Volume names, capacity, free space |
| Open file | `open` crate / `std::process::Command::new("open")` | macOS `open` command |
| Hidden files | Check for `.` prefix (Unix convention) | macOS also uses `chflags hidden` |

### 4.2 File Watching

```rust
use notify::{Watcher, RecursiveMode, Event};

// Per-tab watcher — watches current directory (non-recursive for performance)
fn watch_directory(path: &str, app: AppHandle) -> notify::Result<()> {
    let (tx, rx) = std::sync::mpsc::channel();
    let mut watcher = notify::recommended_watcher(tx)?;
    watcher.watch(Path::new(path), RecursiveMode::NonRecursive)?;

    std::thread::spawn(move || {
        for event in rx {
            match event {
                Ok(Event { kind, paths, .. }) => {
                    app.emit("fs-changed", FsChangeEvent { kind, paths }).ok();
                }
                Err(e) => eprintln!("Watch error: {}", e),
            }
        }
    });
    Ok(())
}
```

Frontend subscribes and refreshes listing:
```typescript
listen<FsChangeEvent>("fs-changed", (event) => {
  explorerStore.getState().refreshCurrentDirectory();
});
```

### 4.3 macOS-Specific Considerations

- **Sandbox**: Tauri apps can run unsandboxed for full FS access, or use macOS security-scoped bookmarks for sandboxed access
- **Permissions**: Must handle TCC (Transparency, Consent, and Control) for Desktop, Documents, Downloads access
- **Extended attributes**: `xattr` crate for reading macOS metadata (tags, Finder comments)
- **Spotlight integration**: Could use `mdls`/`mdfind` CLI tools for leveraging macOS search index
- **Trash**: The `trash` crate uses `NSFileManager.trashItem` under the hood — proper macOS Trash behavior
- **.DS_Store**: Filter out from listings by default

### 4.4 Tauri v2 Plugins Used

| Plugin | Purpose |
|--------|---------|
| `tauri-plugin-fs` | Scoped FS access (if sandboxed) |
| `tauri-plugin-dialog` | Native file open/save dialogs |
| `tauri-plugin-clipboard-manager` | System clipboard for file paths |
| `tauri-plugin-shell` | Open files with system default app |
| `tauri-plugin-os` | OS info for platform-specific behavior |
| `tauri-plugin-window-state` | Remember window size/position |
| `tauri-plugin-persisted-scope` | Remember FS access permissions |

---

## 5. Build System

### 5.1 Project Setup

```bash
# Prerequisites
rustup target add aarch64-apple-darwin  # Apple Silicon target
cargo install create-tauri-app
npm create tauri-app@latest explorer -- \
  --template react-ts \
  --manager npm

# Project root structure
explorer/
├── package.json            # Frontend deps, scripts
├── vite.config.ts          # Vite config with Tauri plugin
├── tsconfig.json           # TypeScript config
├── src/                    # React frontend
├── src-tauri/
│   ├── Cargo.toml          # Rust deps
│   ├── tauri.conf.json     # Tauri config (window, security, bundle)
│   ├── capabilities/       # Tauri v2 capability-based permissions
│   ├── src/                # Rust backend source
│   ├── icons/              # App icons (icns for macOS)
│   └── Info.plist          # macOS app metadata
├── public/                 # Static assets
└── tests/                  # E2E tests
```

### 5.2 Key Configuration Files

**`src-tauri/Cargo.toml`** (key dependencies):
```toml
[dependencies]
tauri = { version = "2", features = ["macos-private-api"] }
tauri-plugin-fs = "2"
tauri-plugin-dialog = "2"
tauri-plugin-clipboard-manager = "2"
tauri-plugin-shell = "2"
tauri-plugin-window-state = "2"
tauri-plugin-os = "2"
tauri-plugin-persisted-scope = "2"
serde = { version = "1", features = ["derive"] }
serde_json = "1"
tokio = { version = "1", features = ["full"] }
notify = "6"
walkdir = "2"
trash = "5"
fs_extra = "1.3"
sysinfo = "0.32"
open = "5"
specta = "2"
tauri-specta = "2"
tantivy = "0.22"       # Phase 2: full-text search
image = "0.25"          # Thumbnail generation
```

**`package.json`** (key dependencies):
```json
{
  "dependencies": {
    "@fluentui/react-components": "^9.x",
    "@fluentui/react-icons": "^2.x",
    "@tauri-apps/api": "^2",
    "@tauri-apps/plugin-fs": "^2",
    "@tauri-apps/plugin-dialog": "^2",
    "@tauri-apps/plugin-clipboard-manager": "^2",
    "@tauri-apps/plugin-shell": "^2",
    "@tanstack/react-virtual": "^3",
    "@dnd-kit/core": "^6",
    "@dnd-kit/sortable": "^8",
    "zustand": "^4",
    "date-fns": "^3",
    "react": "^18",
    "react-dom": "^18"
  },
  "devDependencies": {
    "@tauri-apps/cli": "^2",
    "vite": "^5",
    "@vitejs/plugin-react": "^4",
    "typescript": "^5",
    "vitest": "^1",
    "@playwright/test": "^1"
  }
}
```

### 5.3 Build Commands

```bash
# Development (hot-reload)
npm run tauri dev

# Production build (Apple Silicon native)
npm run tauri build -- --target aarch64-apple-darwin

# Universal binary (Intel + Apple Silicon)
npm run tauri build -- --target universal-apple-darwin
```

### 5.4 Code Signing & Notarization

```bash
# Required environment variables
export APPLE_SIGNING_IDENTITY="Developer ID Application: Your Name (TEAM_ID)"
export APPLE_CERTIFICATE="base64-encoded-p12"
export APPLE_CERTIFICATE_PASSWORD="password"
export APPLE_ID="your@email.com"
export APPLE_PASSWORD="app-specific-password"  # or @keychain:notarytool
export APPLE_TEAM_ID="TEAM_ID"
```

**`tauri.conf.json`** bundle section:
```json
{
  "bundle": {
    "active": true,
    "targets": ["dmg", "app"],
    "macOS": {
      "signingIdentity": null,
      "entitlements": "./Entitlements.plist",
      "minimumSystemVersion": "11.0"
    },
    "identifier": "com.yourcompany.explorer",
    "icon": ["icons/icon.icns"]
  }
}
```

**Entitlements.plist** (for file system access):
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "...">
<plist version="1.0">
<dict>
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>
    <key>com.apple.security.files.downloads.read-write</key>
    <true/>
    <!-- For full FS access, run unsandboxed or add broader entitlements -->
</dict>
</plist>
```

Tauri v2 handles code signing and notarization automatically during `tauri build` when the environment variables are set.

### 5.5 CI/CD (GitHub Actions)

```yaml
# .github/workflows/build.yml
jobs:
  build-macos:
    runs-on: macos-14  # M1 runner for Apple Silicon native build
    steps:
      - uses: actions/checkout@v4
      - uses: dtolnay/rust-toolchain@stable
        with:
          targets: aarch64-apple-darwin
      - uses: actions/setup-node@v4
        with:
          node-version: 20
      - run: npm ci
      - uses: tauri-apps/tauri-action@v0
        with:
          tagName: v__VERSION__
          releaseName: "Explorer v__VERSION__"
          args: --target aarch64-apple-darwin
```

---

## 6. Estimated Complexity

| Feature | Complexity | Effort Estimate | Notes |
|---------|-----------|----------------|-------|
| **Navigation pane (tree view)** | Medium | 2–3 weeks | Lazy loading, expand/collapse, favorites persistence |
| **Details view (data grid)** | Medium | 2–3 weeks | Column sorting, resizing, virtualization, inline rename |
| **Icons view** | Low | 1 week | CSS Grid layout, icon size variants |
| **Tiles view** | Low | 1 week | Card layout with metadata |
| **Breadcrumb bar** | Medium | 1–2 weeks | Editable mode, sibling dropdowns, path validation |
| **Toolbar/Ribbon** | Low–Medium | 1–2 weeks | Buttons + dropdowns, contextual enable/disable |
| **Tabs** | Medium | 2 weeks | Independent state per tab, tab lifecycle, keyboard shortcuts |
| **File operations (copy/move/delete)** | High | 3–4 weeks | Progress tracking, conflict resolution, undo, error handling |
| **Search** | High | 3–4 weeks | Recursive search, streaming results, full-text indexing (Phase 2) |
| **Context menus** | Medium | 1–2 weeks | Context-sensitive items, nested menus, keyboard navigation |
| **File watching** | Medium | 1–2 weeks | Debouncing, reconnecting, per-tab watchers |
| **Preview pane** | Medium | 2–3 weeks | Multiple file type handlers, thumbnail generation |
| **Drag and drop** | High | 2–3 weeks | Intra-app DnD, native DnD to/from Finder, visual feedback |
| **Keyboard shortcuts** | Medium | 1–2 weeks | Global handler, conflict resolution, discoverability |
| **Properties dialog** | Low–Medium | 1–2 weeks | Metadata display, recursive size calculation |
| **Status bar** | Low | 0.5 week | Item count, selection info, disk space |
| **Dual pane / Split view** | Medium | 2 weeks | Independent pane state, resizable divider |
| **Windows visual polish** | High | 3–4 weeks | Pixel-matching Windows 11 aesthetic on macOS, custom scrollbars, animations |
| **macOS permissions (TCC)** | Medium | 1–2 weeks | Handling access denials gracefully, security-scoped bookmarks |

**Total estimated effort: ~35–45 weeks (1 developer)**
**With 2–3 developers working in parallel: ~15–20 weeks**

---

## 7. Pros and Cons

### Pros

| Advantage | Detail |
|-----------|--------|
| **Native performance** | Rust backend compiles to native ARM64 — file operations are as fast as a native app |
| **Small binary** | ~8–15 MB app bundle (vs. ~150MB+ for Electron) |
| **Low memory** | ~40–80 MB RAM (vs. ~200–400 MB for Electron) |
| **WebKit efficiency** | macOS WebKit is highly optimized, shares the system's web engine — no bundled Chromium |
| **Fluent UI** | Microsoft's own design system means pixel-accurate Windows look without manual CSS work |
| **Rust safety** | No segfaults, no data races — critical for file operations that could destroy data |
| **Rich npm ecosystem** | Access to all React component libraries for UI needs |
| **Hot reload** | Vite HMR for instant UI iteration during development |
| **Tauri v2 maturity** | Stable release, good plugin ecosystem, active community |
| **Type safety end-to-end** | Rust → specta → TypeScript — types are guaranteed to match |
| **Security model** | Tauri v2's capability-based permissions are more secure than Electron's node integration |
| **Cross-platform potential** | Same codebase could target Windows/Linux later (though not the current goal) |

### Cons

| Disadvantage | Detail | Mitigation |
|-------------|--------|------------|
| **WebKit rendering differences** | Fluent UI designed for Chromium — some CSS/rendering differences on WebKit | Test extensively on WebKit; add WebKit-specific CSS fixes. Most Fluent UI works fine on Safari/WebKit. |
| **No native macOS feel** | App will look like Windows on macOS — users may find it jarring | This is intentional per requirements, but may cause App Store rejection if submitted |
| **WebView limitations** | Can't do GPU-accelerated custom rendering (relevant for thumbnail grids with thousands of icons) | Use virtualization (`@tanstack/react-virtual`) to keep DOM node count low |
| **Tauri IPC overhead** | Every file operation crosses JS↔Rust boundary (serialization cost) | Batch operations in Rust; send directory listings as single payload, not per-file |
| **No native drag-and-drop polish** | HTML5 DnD + Tauri DnD events are less polished than native macOS DnD | Use `@dnd-kit` for intra-app; accept slight UX degradation for external DnD |
| **File thumbnails** | Generating thumbnails in Rust is possible but less integrated than macOS Quick Look | Use `image` crate for basic thumbnails; shell out to `qlmanage` for Quick Look previews |
| **Debugging split** | Must debug Rust (lldb) and JS (WebKit Inspector) separately | Use `tauri dev` which opens WebKit Inspector automatically; Rust logging via `tracing` crate |
| **Two-language cognitive load** | Developers need Rust + TypeScript + React proficiency | Clear module boundaries reduce context switching |
| **Bundle size concern** | Fluent UI v9 is tree-shakeable but still adds ~200KB+ to JS bundle | Acceptable for desktop app; lazy-load view components |
| **No native context menu** | Custom HTML context menus don't match OS behavior exactly (e.g., no native "Services" submenu) | Fluent UI `Menu` component looks close enough; advanced users may notice |

---

## 8. Apple Silicon Optimization

### 8.1 ARM64 Native Rust Compilation

```bash
# Rust compiles directly to ARM64 (aarch64-apple-darwin)
rustup target add aarch64-apple-darwin
cargo build --release --target aarch64-apple-darwin
```

**Performance advantages:**
- File system operations (`read_dir`, `metadata`) execute at native speed — no interpreter or JIT overhead
- Sorting 100k file entries in Rust: ~10ms on M1 (vs. ~80ms in JS)
- Memory-mapped file reading for previews — zero-copy where possible
- `tantivy` search index runs at native speed — orders of magnitude faster than JS-based search

### 8.2 WebKit Performance on Apple Silicon

- **macOS WebKit is ARM64 native** — the system's `WKWebView` is already optimized for Apple Silicon
- **JavaScript JIT**: WebKit's JavaScriptCore has excellent ARM64 JIT (shared with Safari)
- **GPU compositing**: WebKit uses Metal for GPU-accelerated rendering on Apple Silicon
- **No Chromium overhead**: Unlike Electron, Tauri doesn't bundle a browser engine — uses the system's optimized WebKit
- **Unified memory**: Apple's unified memory architecture means no GPU↔CPU memory copies for WebKit rendering

### 8.3 Memory Usage Comparison (Estimated)

| App | RAM (idle) | RAM (10k files) | Binary Size |
|-----|-----------|-----------------|-------------|
| Tauri Explorer | ~40 MB | ~80 MB | ~12 MB |
| Electron Explorer | ~180 MB | ~350 MB | ~150 MB |
| Native SwiftUI | ~25 MB | ~60 MB | ~5 MB |
| Flutter | ~80 MB | ~150 MB | ~25 MB |

### 8.4 Specific Optimizations to Implement

1. **Batch IPC**: Send full directory listing in one command, not per-file
2. **Virtual scrolling**: Only render visible rows (critical for large directories)
3. **Lazy thumbnail generation**: Generate thumbnails on scroll-into-view, not on directory load
4. **Background indexing**: Search index built in background Rust thread, doesn't block UI
5. **Debounced FS watching**: Coalesce rapid FS events (e.g., during file copy) into single refresh
6. **Efficient serialization**: Use `serde` with `#[serde(skip)]` to avoid sending unnecessary fields
7. **Directory entry caching**: Cache recent directory listings in Rust with TTL, invalidated by watcher

---

## 9. Timeline Estimate

### Phase 1: Foundation (Weeks 1–4)
- Project scaffolding (Tauri v2 + React + Vite + Fluent UI)
- Rust module structure, error handling, AppState
- Basic `list_directory` command with metadata
- Navigation pane with simple folder tree
- Content area with Details view (sortable columns)
- Breadcrumb bar (read-only, clickable segments)
- Status bar
- Basic keyboard navigation (arrow keys, Enter to open)

**Deliverable**: Can browse folders, see files in detail view, navigate via tree and breadcrumbs.

### Phase 2: Core Operations (Weeks 5–10)
- File operations: copy, move, delete (to Trash), rename
- Operation progress dialog with cancel support
- Conflict resolution dialog (overwrite, skip, rename)
- Context menus (right-click)
- Toolbar with operation buttons
- Multi-select (Ctrl+Click, Shift+Click, Ctrl+A)
- Keyboard shortcuts (Ctrl+C/V/X, Delete, F2, etc.)
- File watching (auto-refresh on external changes)
- Icons view and Tiles view
- View mode switching

**Deliverable**: Fully functional file management — create, copy, move, delete, rename with multiple view modes.

### Phase 3: Advanced Features (Weeks 11–16)
- Tab support (multiple tabs, independent state)
- Search (file name search with streaming results)
- Preview pane (images, text, metadata)
- Drag and drop (intra-app)
- Properties dialog
- Favorites / Quick Access (persist pinned folders)
- Editable breadcrumb bar (click to type path)
- Column resizing in Details view

**Deliverable**: Feature-complete file explorer matching core Windows Explorer functionality.

### Phase 4: Polish & Platform (Weeks 17–22)
- Windows 11 visual polish (animations, hover effects, focus rings, scrollbar styling)
- Dual pane / split view
- Native DnD (drag files to/from Finder)
- Full-text search with tantivy indexing
- Performance optimization (profiling, reducing IPC calls)
- macOS permissions handling (TCC dialogs, error states)
- Edge cases (symlinks, aliases, permission errors, very long paths)
- Accessibility (screen reader, keyboard-only navigation)

**Deliverable**: Polished, production-quality application.

### Phase 5: Release (Weeks 23–26)
- Code signing and notarization
- Auto-update (tauri-plugin-updater)
- DMG installer with background image
- Documentation (user guide, developer docs)
- CI/CD pipeline (GitHub Actions)
- Beta testing, bug fixes
- Performance benchmarking vs. native Finder

**Deliverable**: Distributable, signed macOS application.

### Timeline Summary

| Phase | Duration | Cumulative |
|-------|----------|-----------|
| Foundation | 4 weeks | Week 4 |
| Core Operations | 6 weeks | Week 10 |
| Advanced Features | 6 weeks | Week 16 |
| Polish & Platform | 6 weeks | Week 22 |
| Release | 4 weeks | Week 26 |
| **Total** | **~26 weeks** | **~6 months (1 dev)** |

With a team of 2–3 developers: **~12–16 weeks (~3–4 months)**

---

## 10. Risks and Challenges

### 🔴 High Risk

| Risk | Impact | Likelihood | Mitigation |
|------|--------|-----------|------------|
| **WebKit CSS rendering differences** | Fluent UI components may render differently on WebKit vs. Chromium (shadows, backdrop-blur, animations) | High | Build a WebKit CSS compatibility layer early; test every component in Safari first; maintain a `webkit-fixes.css` file |
| **macOS Sandbox vs. FS access** | A file explorer needs broad FS access; macOS sandboxing is increasingly strict | High | Ship unsandboxed (outside App Store) or implement security-scoped bookmarks for user-selected folders; may preclude App Store distribution |
| **IPC performance bottleneck** | Directories with 50k+ files could cause slow serialization across the Rust↔JS bridge | Medium | Paginate directory listings (load 500 at a time), virtual scroll, background loading with streaming events |
| **Drag & drop fidelity** | HTML5 DnD + Tauri events won't match native macOS DnD experience (spring-loaded folders, Finder integration) | High | Accept UX compromise; document limitations; consider Objective-C bridge for native DnD if critical |

### 🟡 Medium Risk

| Risk | Impact | Likelihood | Mitigation |
|------|--------|-----------|------------|
| **Fluent UI v9 WebKit bugs** | Microsoft primarily tests Fluent UI on Chromium; WebKit-specific bugs may exist in `DataGrid`, `Tree`, etc. | Medium | File issues upstream; fork and patch critical components if needed; have fallback custom implementations |
| **File operation edge cases** | Symlinks, aliases, resource forks, locked files, Files in Use, permission denials, very long Unicode paths | High (for edge cases) | Comprehensive error handling in Rust; test with adversarial file systems; graceful degradation |
| **Thumbnail generation performance** | Generating thumbnails for hundreds of images in a photos folder could lag | Medium | Lazy generation (only visible items), caching to disk, use `qlmanage -t` for system thumbnails |
| **Two-language debugging** | Debugging issues that span Rust ↔ JS boundary is harder than single-language debugging | Medium | Extensive logging (`tracing` in Rust, `console` in JS); structured error types that include context |
| **Tauri v2 ecosystem maturity** | Some plugins may have bugs or missing features; fewer community resources than Electron | Medium | Pin dependency versions; have fallback implementations for critical paths; contribute fixes upstream |

### 🟢 Low Risk

| Risk | Impact | Likelihood | Mitigation |
|------|--------|-----------|------------|
| **React performance** | Complex file listings could cause React rendering bottleneck | Low | Virtual scrolling, `React.memo`, `useMemo`, Zustand's automatic shallow compare |
| **Bundle size** | Fluent UI + React + utilities could exceed 1 MB JS bundle | Low | Tree-shaking, code splitting, lazy-load view components |
| **Apple Silicon compatibility** | Rust or npm packages might not support ARM64 | Very Low | Rust and npm ecosystem has excellent ARM64 support; test native deps in CI |

### Key Technical Challenges

1. **Matching Windows 11 aesthetics on macOS**: Fluent UI gives us 80% of the way there, but window chrome (title bar, traffic lights vs. min/max/close), font rendering (Segoe UI vs. SF Pro), and scrollbar styles will differ. Custom title bar and CSS overrides needed.

2. **File system permissions**: macOS Sequoia and later have increasingly strict file access controls. A file explorer that can't access common folders is useless. Must handle permission prompts and denials gracefully.

3. **Real-time updates**: File watching must be robust (handle unmounted volumes, network drives disappearing, rapid changes during copy operations) without leaking watchers or consuming excessive resources.

4. **Undo/Redo for file operations**: Windows Explorer has undo for delete/rename/move. Implementing reliable undo in a file system context is non-trivial (what if the file was modified after move?). Consider: undo stack with best-effort reversal.

5. **Unicode and internationalization**: File names can contain any Unicode character including RTL text, emoji, combining characters, and zero-width spaces. Path handling must be robust.

---

## Appendix A: Comparison Matrix vs. Alternatives

| Criteria | Tauri + React | Electron + React | SwiftUI Native | Flutter |
|----------|:------------:|:----------------:|:--------------:|:-------:|
| Windows look fidelity | ★★★★☆ | ★★★★★ | ★★☆☆☆ | ★★★☆☆ |
| macOS integration | ★★★☆☆ | ★★★☆☆ | ★★★★★ | ★★☆☆☆ |
| Performance | ★★★★★ | ★★★☆☆ | ★★★★★ | ★★★★☆ |
| Memory usage | ★★★★★ | ★★☆☆☆ | ★★★★★ | ★★★☆☆ |
| Binary size | ★★★★★ | ★☆☆☆☆ | ★★★★★ | ★★★☆☆ |
| Development speed | ★★★★☆ | ★★★★★ | ★★★☆☆ | ★★★★☆ |
| UI component library | ★★★★☆ | ★★★★★ | ★★★☆☆ | ★★★☆☆ |
| Cross-platform potential | ★★★★☆ | ★★★★★ | ★☆☆☆☆ | ★★★★★ |
| Team hiring pool | ★★★☆☆ | ★★★★★ | ★★★☆☆ | ★★★★☆ |
| Long-term maintenance | ★★★★☆ | ★★★★☆ | ★★★★★ | ★★★☆☆ |

### Tauri's Sweet Spot
Tauri is the best choice when you want **near-native performance and resource usage** with **web-based UI flexibility**. For replicating Windows Explorer on macOS, it offers the best balance of Fluent UI fidelity and system performance — Electron gives slightly better Fluent UI rendering (Chromium), but at 10x the memory cost.

---

## Appendix B: Quick Start Commands

```bash
# 1. Create project
npm create tauri-app@latest explorer -- --template react-ts --manager npm
cd explorer

# 2. Add Fluent UI
npm install @fluentui/react-components @fluentui/react-icons

# 3. Add state management and utilities
npm install zustand @tanstack/react-virtual @dnd-kit/core @dnd-kit/sortable date-fns

# 4. Add Tauri plugins (npm side)
npm install @tauri-apps/plugin-fs @tauri-apps/plugin-dialog \
  @tauri-apps/plugin-clipboard-manager @tauri-apps/plugin-shell \
  @tauri-apps/plugin-os @tauri-apps/plugin-window-state

# 5. Add Rust dependencies (edit src-tauri/Cargo.toml, then):
cd src-tauri && cargo check && cd ..

# 6. Run dev
npm run tauri dev

# 7. Build for Apple Silicon
npm run tauri build -- --target aarch64-apple-darwin
```
