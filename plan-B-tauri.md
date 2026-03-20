# Plan B: macOS File Explorer — Tauri v2 + React + TypeScript

## 1. Executive Summary

This plan describes a macOS-native file explorer application built with **Tauri v2** (Rust backend) and **React + TypeScript** (web frontend). The app aims to fill the gaps left by Finder — specifically the lack of a Windows-style "Up" button, cut-to-move file operations, and a customizable favorites sidebar — while preserving a Finder-like visual aesthetic with vibrancy, translucency, and dark mode support.

Tauri v2 is chosen over Electron for three reasons: (1) the Rust backend provides direct, high-performance access to macOS file system APIs without spawning child processes, enabling smooth handling of directories with 100k+ files; (2) the app binary is ~5–10 MB instead of Electron's ~150 MB since it uses the system WebView (WKWebView on macOS) instead of bundling Chromium; and (3) Tauri v2's permission-based security model and IPC system are a natural fit for a file manager that needs carefully scoped filesystem access.

The architecture follows a clean split: the Rust backend owns all file system operations (enumeration, move, copy, delete, rename, watch), persistence (favorites, preferences, window state), and exposes them as Tauri commands via JSON-RPC IPC. The React frontend is purely presentational — it renders views, handles keyboard shortcuts, manages UI state with Zustand, and calls the backend for every file operation. This ensures the frontend never directly touches the filesystem, keeping the security boundary intact.

---

## 2. Technology Stack

| Layer | Technology | Version | Purpose |
|-------|-----------|---------|---------|
| **App Framework** | Tauri | 2.x (latest stable) | Native app shell, IPC, window management |
| **Backend Language** | Rust | 1.75+ (stable) | File system ops, business logic |
| **Frontend Language** | TypeScript | 5.x | Type-safe UI code |
| **UI Framework** | React | 18.x | Component rendering |
| **Build Tool** | Vite | 5.x | Fast frontend bundling, HMR |
| **State Management** | Zustand | 4.x | Lightweight global state |
| **Virtual Scrolling** | TanStack Virtual | 3.x | Render 100k+ rows efficiently |
| **Icons** | lucide-react | latest | Clean, Finder-style icons |
| **Styling** | Tailwind CSS | 3.x | Utility-first CSS |
| **DnD** | @dnd-kit/core | 6.x | Drag-and-drop for favorites |
| **Rust: async runtime** | tokio | 1.x | Async file enumeration |
| **Rust: serialization** | serde / serde_json | 1.x | IPC data serialization |
| **Rust: file watching** | notify | 6.x | Real-time directory change events |
| **Rust: persistence** | tauri-plugin-store | 2.x | JSON key-value persistence |
| **Rust: macOS APIs** | objc2 / cocoa (optional) | latest | Vibrancy, native integrations |
| **Rust: file metadata** | std::fs + libc | — | Unix file attributes, permissions |
| **Rust: trash** | trash | 3.x | Move to Trash (macOS native) |

---

## 3. Architecture

### 3.1 High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        macOS Application                        │
│                                                                 │
│  ┌──────────────────────┐     IPC (JSON)    ┌────────────────┐  │
│  │   React Frontend     │◄════════════════►│  Rust Backend   │  │
│  │   (WKWebView)        │  invoke/listen    │  (src-tauri/)   │  │
│  │                      │                   │                 │  │
│  │  • UI Components     │                   │  • Commands     │  │
│  │  • Zustand Stores    │                   │  • File Ops     │  │
│  │  • Virtual Scroll    │                   │  • FS Watcher   │  │
│  │  • Keyboard Handler  │                   │  • Persistence  │  │
│  │  • DnD Manager       │                   │  • macOS APIs   │  │
│  └──────────────────────┘                   └────────────────┘  │
│                                                    │            │
│                                              ┌─────▼──────┐    │
│                                              │  macOS FS   │    │
│                                              │  + APIs     │    │
│                                              └────────────┘    │
└─────────────────────────────────────────────────────────────────┘
```

### 3.2 IPC Design

All frontend ↔ backend communication uses Tauri's `invoke` (request/response) and `listen`/`emit` (events) system. Invoke calls are async and return typed results.

**Command Pattern:**

```
Frontend                         Backend
────────                         ───────
invoke("list_directory",       → fn list_directory(path, sort_by, sort_dir, offset, limit)
  { path, sortBy, ... })          → reads fs, returns Vec<FileEntry>
                               ←  returns Result<DirectoryListing, String>
```

**Event Pattern (for fs watcher):**

```
Backend                          Frontend
───────                          ────────
notify crate detects change   →  emit("fs:changed", { path, kind })
                                  store.invalidate(path)
                                  re-fetch listing
```

### 3.3 Data Flow for Directory Navigation

```
User clicks folder
       │
       ▼
NavigationStore.navigate(path)
       │
       ▼
invoke("list_directory", { path, sortBy, sortDir, offset: 0, limit: 500 })
       │                                              │
       │         Rust: tokio::fs::read_dir()          │
       │         + metadata() for each entry          │
       │         sorted server-side                   │
       │         returns paginated slice              │
       ▼                                              │
DirectoryStore.setEntries(entries)                    │
       │                                              │
       ▼                                              │
<VirtualList> renders visible rows (~50)              │
       │                                              │
       ▼                                              │
User scrolls → onRangeChange → invoke("list_directory", { offset: 500, limit: 500 })
                                                      │
                                                      ▼
                                              append to entries
```

### 3.4 State Stores (Zustand)

| Store | Responsibility |
|-------|---------------|
| `useNavigationStore` | Current path, history stack (back/forward/up), breadcrumb segments |
| `useDirectoryStore` | File entries for current directory, total count, loading state |
| `useSortStore` | Sort column, sort direction |
| `useClipboardStore` | Cut/copy buffer (paths + operation type) |
| `useFavoritesStore` | Pinned folders, add/remove/reorder |
| `useViewStore` | Current view mode (list/icon/column), column widths |
| `useSelectionStore` | Selected file(s), multi-select state |
| `usePreferencesStore` | Show hidden files, default view, etc. |

---

## 4. Core Features Implementation

### 4.1 "Up" Button — Parent Folder Navigation

**User Perspective:**
A clearly visible "↑" button sits in the toolbar, immediately left of the breadcrumb path. Clicking it navigates to the parent directory. It is disabled (greyed out) when at the root (`/`). The keyboard shortcut `Cmd+Up` also triggers it, matching Finder's behavior.

**Frontend Components:**
- `<Toolbar>` — top bar containing the Up button, Back/Forward, breadcrumb, view mode toggle, search
- `<UpButton>` — renders an up-arrow icon button. Reads `currentPath` from `useNavigationStore`, computes parent via `path.split('/').slice(0, -1).join('/')`, calls `navigate(parentPath)`.

```tsx
// components/Toolbar/UpButton.tsx
import { useNavigationStore } from '@/stores/navigationStore';
import { ChevronUp } from 'lucide-react';

export function UpButton() {
  const { currentPath, navigate } = useNavigationStore();
  const isRoot = currentPath === '/';
  const parentPath = currentPath.split('/').slice(0, -1).join('/') || '/';

  return (
    <button
      className="toolbar-btn"
      disabled={isRoot}
      onClick={() => navigate(parentPath)}
      title="Go to parent folder (⌘↑)"
    >
      <ChevronUp size={18} />
    </button>
  );
}
```

**Backend:**
No special backend command needed — navigation is simply calling `list_directory` with the parent path.

**Keyboard Shortcut:**
- `Cmd+Up` → navigate to parent directory
- Registered via a global `useEffect` keydown listener in `<App>`.

---

### 4.2 Cut/Paste to Move Files

**User Perspective:**
Select one or more files, press `Cmd+X` to "cut" (files dim with 50% opacity to indicate pending move). Navigate to the destination folder. Press `Cmd+V` to paste (move). Files disappear from the source and appear in the destination. If the destination has a name conflict, a dialog offers to "Keep Both", "Replace", or "Cancel". Right-click context menu also shows Cut and Paste options. `Cmd+C` copies (for copy-paste), `Cmd+V` pastes as copy if the buffer is a copy operation.

**Frontend Components:**
- `useClipboardStore` — holds `{ paths: string[], operation: 'cut' | 'copy' } | null`
- `<FileEntry>` — renders with `opacity-50` class when the entry's path is in the cut clipboard
- `<ContextMenu>` — right-click menu with Cut / Copy / Paste / Delete / Rename options
- Keyboard handler in `<App>` catches `Cmd+X`, `Cmd+C`, `Cmd+V`

```tsx
// stores/clipboardStore.ts
import { create } from 'zustand';
import { invoke } from '@tauri-apps/api/core';

interface ClipboardState {
  paths: string[];
  operation: 'cut' | 'copy' | null;
  cut: (paths: string[]) => void;
  copy: (paths: string[]) => void;
  paste: (destinationDir: string) => Promise<PasteResult>;
  clear: () => void;
}

interface PasteResult {
  moved: number;
  failed: Array<{ path: string; error: string }>;
}

export const useClipboardStore = create<ClipboardState>((set, get) => ({
  paths: [],
  operation: null,

  cut: (paths) => set({ paths, operation: 'cut' }),
  copy: (paths) => set({ paths, operation: 'copy' }),
  clear: () => set({ paths: [], operation: null }),

  paste: async (destinationDir) => {
    const { paths, operation } = get();
    if (!operation || paths.length === 0) {
      return { moved: 0, failed: [] };
    }

    const result = await invoke<PasteResult>(
      operation === 'cut' ? 'move_files' : 'copy_files',
      { sources: paths, destination: destinationDir }
    );

    if (operation === 'cut') {
      set({ paths: [], operation: null });
    }

    return result;
  },
}));
```

**Backend (Rust):**

```rust
// src-tauri/src/commands/file_ops.rs

#[derive(Serialize)]
pub struct PasteResult {
    moved: usize,
    failed: Vec<FailedOp>,
}

#[derive(Serialize)]
pub struct FailedOp {
    path: String,
    error: String,
}

#[tauri::command]
pub async fn move_files(sources: Vec<String>, destination: String) -> Result<PasteResult, String> {
    let dest = PathBuf::from(&destination);
    if !dest.is_dir() {
        return Err("Destination is not a directory".into());
    }

    let mut moved = 0;
    let mut failed = Vec::new();

    for source in &sources {
        let src = PathBuf::from(source);
        let file_name = src.file_name()
            .ok_or_else(|| "Invalid source path".to_string())?;
        let target = dest.join(file_name);

        match std::fs::rename(&src, &target) {
            Ok(()) => moved += 1,
            Err(e) => {
                // rename() fails across mount points; fall back to copy+delete
                if e.raw_os_error() == Some(libc::EXDEV) {
                    match copy_recursive(&src, &target) {
                        Ok(()) => {
                            std::fs::remove_dir_all(&src).ok(); // or remove_file
                            moved += 1;
                        }
                        Err(e) => failed.push(FailedOp {
                            path: source.clone(),
                            error: e.to_string(),
                        }),
                    }
                } else {
                    failed.push(FailedOp {
                        path: source.clone(),
                        error: e.to_string(),
                    });
                }
            }
        }
    }

    Ok(PasteResult { moved, failed })
}
```

**Keyboard Shortcuts:**
- `Cmd+X` → Cut selected files
- `Cmd+C` → Copy selected files
- `Cmd+V` → Paste (move if cut, copy if copied)
- `Delete` / `Cmd+Backspace` → Move to Trash

---

### 4.3 Favorites Sidebar

**User Perspective:**
A left sidebar (220px wide, resizable) displays a list of pinned folders. Default favorites include Home, Desktop, Documents, Downloads, Applications. The user can drag any folder from the content area onto the sidebar to pin it. Right-click a favorite to remove it. Favorites can be reordered via drag-and-drop within the sidebar. The list is persisted to disk and restored on launch.

**Frontend Components:**
- `<Sidebar>` — the full left panel
- `<FavoritesList>` — maps over favorites, renders `<FavoriteItem>` for each
- `<FavoriteItem>` — icon + label, click to navigate, right-click to remove
- Uses `@dnd-kit/core` for reordering and drop-to-add

```tsx
// components/Sidebar/FavoritesList.tsx
export function FavoritesList() {
  const { favorites, removeFavorite, reorderFavorites } = useFavoritesStore();
  const { navigate } = useNavigationStore();

  return (
    <DndContext onDragEnd={handleDragEnd}>
      <SortableContext items={favorites.map(f => f.path)}>
        <div className="favorites-list">
          <span className="sidebar-heading">Favorites</span>
          {favorites.map((fav) => (
            <SortableFavoriteItem
              key={fav.path}
              favorite={fav}
              onClick={() => navigate(fav.path)}
              onRemove={() => removeFavorite(fav.path)}
            />
          ))}
        </div>
      </SortableContext>
    </DndContext>
  );
}
```

**Backend (Rust):**
- Persistence via `tauri-plugin-store`:
  - Store file: `~/.explorer/favorites.json`
  - Commands: `get_favorites`, `add_favorite`, `remove_favorite`, `reorder_favorites`

```rust
#[tauri::command]
pub async fn add_favorite(
    path: String,
    store: tauri::State<'_, StoreHandle>,
) -> Result<(), String> {
    let mut favorites: Vec<Favorite> = store
        .get("favorites")
        .and_then(|v| serde_json::from_value(v).ok())
        .unwrap_or_default();

    if favorites.iter().any(|f| f.path == path) {
        return Ok(()); // already exists
    }

    let label = PathBuf::from(&path)
        .file_name()
        .map(|n| n.to_string_lossy().into_owned())
        .unwrap_or_else(|| path.clone());

    favorites.push(Favorite { path, label });
    store.set("favorites", serde_json::to_value(&favorites).unwrap());
    store.save().map_err(|e| e.to_string())?;
    Ok(())
}
```

**Keyboard Shortcuts:**
- `Cmd+D` → Add current folder to favorites
- (No standard shortcut for remove — use right-click context menu)

---

### 4.4 Multiple View Modes

**User Perspective:**
Three view mode buttons in the toolbar (icon-strip, like Finder): List, Icon, Column. The current mode is highlighted. Switching is instant — no reload, the same data is just re-rendered.

#### 4.4.1 List View (default)
A table with columns: Name, Date Modified, Size, Kind. Column headers are clickable to sort (see 4.5). Rows are fixed-height (28px) for virtual scrolling. File icon + name in the first column. Alternating row backgrounds. Selected rows highlighted in accent blue.

#### 4.4.2 Icon/Grid View
Files displayed as a grid of icons (64×64 or 128×128) with the filename below. Grid reflows based on window width. Icon size adjustable with a slider in the status bar.

#### 4.4.3 Column View
Miller columns: each directory level is a column (250px wide). Selecting a folder opens its contents in the next column to the right. Selecting a file shows a preview panel on the right. Horizontal scrolling when many columns are open.

**Frontend Components:**
- `<ContentArea>` — switches between views based on `useViewStore().mode`
- `<ListView>` — uses TanStack Virtual for virtualized table rows
- `<IconView>` — uses TanStack Virtual grid for virtualized grid cells
- `<ColumnView>` — horizontal scroll container with `<ColumnPanel>` components
- `<ViewModeToggle>` — three-button group in the toolbar

```tsx
// components/ContentArea/ContentArea.tsx
export function ContentArea() {
  const { mode } = useViewStore();
  const { entries, totalCount, isLoading } = useDirectoryStore();

  switch (mode) {
    case 'list':
      return <ListView entries={entries} totalCount={totalCount} />;
    case 'icon':
      return <IconView entries={entries} totalCount={totalCount} />;
    case 'column':
      return <ColumnView />;
    default:
      return <ListView entries={entries} totalCount={totalCount} />;
  }
}
```

**Backend:**
No view-specific backend logic. All views consume the same `FileEntry` data from `list_directory`.

**Keyboard Shortcuts:**
- `Cmd+1` → List view
- `Cmd+2` → Icon view
- `Cmd+3` → Column view

---

### 4.5 Sorting

**User Perspective:**
In List view, clicking a column header sorts by that column. Clicking again reverses direction. A small arrow (▲/▼) indicates current sort column and direction. Sorting is fast because it happens on the Rust side — the frontend requests a pre-sorted listing.

Available sort fields: `name`, `date_modified`, `size`, `kind`.

**Frontend Components:**
- `<ColumnHeader>` — clickable header cell, shows sort indicator
- `useSortStore` — holds `{ field: SortField, direction: 'asc' | 'desc' }`
- Changing sort triggers a re-invoke of `list_directory` with new sort params

```tsx
// stores/sortStore.ts
type SortField = 'name' | 'date_modified' | 'size' | 'kind';

interface SortState {
  field: SortField;
  direction: 'asc' | 'desc';
  toggleSort: (field: SortField) => void;
}

export const useSortStore = create<SortState>((set, get) => ({
  field: 'name',
  direction: 'asc',
  toggleSort: (field) => {
    const state = get();
    if (state.field === field) {
      set({ direction: state.direction === 'asc' ? 'desc' : 'asc' });
    } else {
      set({ field, direction: 'asc' });
    }
  },
}));
```

**Backend (Rust):**
Sorting is done in the `list_directory` command after enumeration:

```rust
fn sort_entries(entries: &mut Vec<FileEntry>, sort_by: &str, ascending: bool) {
    entries.sort_by(|a, b| {
        // Always sort directories before files
        let dir_cmp = b.is_dir.cmp(&a.is_dir);
        if dir_cmp != std::cmp::Ordering::Equal {
            return dir_cmp;
        }

        let cmp = match sort_by {
            "name" => natord::compare_ignore_case(&a.name, &b.name),
            "date_modified" => a.modified_at.cmp(&b.modified_at),
            "size" => a.size.cmp(&b.size),
            "kind" => a.kind.cmp(&b.kind),
            _ => std::cmp::Ordering::Equal,
        };

        if ascending { cmp } else { cmp.reverse() }
    });
}
```

**Keyboard Shortcuts:**
None standard (clicking headers is the primary interaction).

---

### 4.6 Performance — 100k+ Files

See dedicated Section 5 below.

---

### 4.7 Finder-Like Look and Feel

**User Perspective:**
The app looks like a native macOS application: translucent sidebar, clean typography (SF Pro via system font stack), proper dark/light mode, macOS traffic-light window controls in the native title bar area. Rounded corners on selections, muted colors, no garish Windows-style chrome.

**Implementation:**

1. **Window Vibrancy:** Tauri v2 supports `vibrancy` in `tauri.conf.json`:
   ```json
   {
     "app": {
       "windows": [{
         "title": "Explorer",
         "width": 1200,
         "height": 800,
         "decorations": true,
         "transparent": true
       }]
     }
   }
   ```
   Use `window.set_vibrancy(Vibrancy::Sidebar)` on the Rust side for the sidebar region, or apply it globally via `tauri.conf.json`.

2. **System Font Stack:**
   ```css
   body {
     font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Text',
                  'Helvetica Neue', sans-serif;
     font-size: 13px;
     -webkit-font-smoothing: antialiased;
   }
   ```

3. **Dark Mode:** Use `prefers-color-scheme` media query + Tailwind's `dark:` variant. All colors defined as CSS custom properties that swap in dark mode.

4. **CSS Theme Variables:**
   ```css
   :root {
     --bg-primary: #ffffff;
     --bg-sidebar: rgba(246, 246, 246, 0.8);
     --bg-selected: rgba(0, 122, 255, 0.15);
     --text-primary: #1d1d1f;
     --text-secondary: #6e6e73;
     --border: rgba(0, 0, 0, 0.1);
     --accent: #007aff;
   }

   @media (prefers-color-scheme: dark) {
     :root {
       --bg-primary: #1e1e1e;
       --bg-sidebar: rgba(30, 30, 30, 0.8);
       --bg-selected: rgba(0, 122, 255, 0.3);
       --text-primary: #f5f5f7;
       --text-secondary: #a1a1a6;
       --border: rgba(255, 255, 255, 0.1);
       --accent: #0a84ff;
     }
   }
   ```

5. **Toolbar Design:** Traffic-light buttons (close/minimize/maximize) in the native title bar. Below, a custom toolbar row with navigation buttons, breadcrumb, search, and view toggle.

6. **Tailwind Config:** Extend with macOS-appropriate spacing (4px grid), border radius (6px for cards, 4px for buttons), and subtle shadows.

---

## 5. Performance Strategy

### 5.1 Problem Statement
A directory with 100,000+ files (e.g., `node_modules`) must be browsable without UI freezes. The bottleneck is (a) enumerating + stat-ing 100k files, and (b) rendering 100k DOM nodes.

### 5.2 Rust-Side: Async Streaming Enumeration

**Approach: Paginated server-side enumeration.**

The `list_directory` command accepts `offset` and `limit` parameters. On first call, Rust enumerates the entire directory, sorts it, caches it, and returns the first page. Subsequent pages are served from cache.

```rust
use std::collections::HashMap;
use std::sync::Mutex;
use std::path::PathBuf;
use tokio::fs;

#[derive(Clone, Serialize)]
pub struct FileEntry {
    pub name: String,
    pub path: String,
    pub is_dir: bool,
    pub size: u64,
    pub modified_at: u64,   // Unix timestamp in milliseconds
    pub kind: String,       // "Folder", "PDF Document", "PNG Image", etc.
    pub is_hidden: bool,
    pub permissions: u32,
}

#[derive(Serialize)]
pub struct DirectoryListing {
    pub path: String,
    pub entries: Vec<FileEntry>,
    pub total_count: usize,
    pub offset: usize,
    pub has_more: bool,
}

struct DirCache {
    entries: Vec<FileEntry>,
    sort_by: String,
    sort_dir: String,
}

type CacheMap = Mutex<HashMap<String, DirCache>>;

#[tauri::command]
pub async fn list_directory(
    path: String,
    sort_by: Option<String>,
    sort_dir: Option<String>,
    offset: Option<usize>,
    limit: Option<usize>,
    cache: tauri::State<'_, CacheMap>,
) -> Result<DirectoryListing, String> {
    let sort_by = sort_by.unwrap_or_else(|| "name".into());
    let sort_dir = sort_dir.unwrap_or_else(|| "asc".into());
    let offset = offset.unwrap_or(0);
    let limit = limit.unwrap_or(500);

    // Check cache
    let cache_key = format!("{}:{}:{}", path, sort_by, sort_dir);
    {
        let cache_guard = cache.lock().unwrap();
        if let Some(cached) = cache_guard.get(&cache_key) {
            let end = (offset + limit).min(cached.entries.len());
            let slice = cached.entries[offset..end].to_vec();
            return Ok(DirectoryListing {
                path: path.clone(),
                entries: slice,
                total_count: cached.entries.len(),
                offset,
                has_more: end < cached.entries.len(),
            });
        }
    }

    // Enumerate directory
    let mut entries = Vec::new();
    let mut read_dir = fs::read_dir(&path).await.map_err(|e| e.to_string())?;

    while let Some(entry) = read_dir.next_entry().await.map_err(|e| e.to_string())? {
        let metadata = entry.metadata().await.map_err(|e| e.to_string())?;
        let name = entry.file_name().to_string_lossy().into_owned();
        let is_hidden = name.starts_with('.');

        entries.push(FileEntry {
            name: name.clone(),
            path: entry.path().to_string_lossy().into_owned(),
            is_dir: metadata.is_dir(),
            size: metadata.len(),
            modified_at: metadata
                .modified()
                .map(|t| t.duration_since(std::time::UNIX_EPOCH).unwrap_or_default().as_millis() as u64)
                .unwrap_or(0),
            kind: get_kind(&name, metadata.is_dir()),
            is_hidden,
            permissions: 0, // populate from metadata on Unix
        });
    }

    // Sort
    sort_entries(&mut entries, &sort_by, sort_dir == "asc");

    // Cache
    let total = entries.len();
    {
        let mut cache_guard = cache.lock().unwrap();
        cache_guard.insert(cache_key, DirCache {
            entries: entries.clone(),
            sort_by: sort_by.clone(),
            sort_dir: sort_dir.clone(),
        });
    }

    let end = (offset + limit).min(total);
    let slice = entries[offset..end].to_vec();

    Ok(DirectoryListing {
        path,
        entries: slice,
        total_count: total,
        offset,
        has_more: end < total,
    })
}
```

### 5.3 Cache Invalidation

The `notify` crate watches the current directory for changes. When a change is detected, the cached listing for that path is evicted, and an event is emitted to the frontend to re-fetch.

```rust
// src-tauri/src/watcher.rs
use notify::{Watcher, RecursiveMode, Event, EventKind};

pub fn start_watcher(
    app_handle: tauri::AppHandle,
    cache: Arc<CacheMap>,
) -> notify::Result<impl Watcher> {
    let mut watcher = notify::recommended_watcher(move |res: Result<Event, _>| {
        if let Ok(event) = res {
            match event.kind {
                EventKind::Create(_) | EventKind::Remove(_) | EventKind::Modify(_) => {
                    for path in &event.paths {
                        let dir = if path.is_dir() {
                            path.to_string_lossy().into_owned()
                        } else {
                            path.parent()
                                .map(|p| p.to_string_lossy().into_owned())
                                .unwrap_or_default()
                        };
                        // Evict cache
                        let mut guard = cache.lock().unwrap();
                        guard.retain(|k, _| !k.starts_with(&dir));
                        drop(guard);

                        // Notify frontend
                        app_handle.emit("fs:changed", &dir).ok();
                    }
                }
                _ => {}
            }
        }
    })?;
    Ok(watcher)
}
```

### 5.4 Frontend: Virtual Scrolling

**TanStack Virtual** renders only the rows visible in the viewport (typically ~30–50 at a time). As the user scrolls, new rows are rendered and off-screen rows are recycled. This keeps DOM node count constant regardless of directory size.

```tsx
// components/ContentArea/ListView.tsx
import { useVirtualizer } from '@tanstack/react-virtual';

export function ListView({ entries, totalCount }: ListViewProps) {
  const parentRef = useRef<HTMLDivElement>(null);

  const virtualizer = useVirtualizer({
    count: totalCount,
    getScrollElement: () => parentRef.current,
    estimateSize: () => 28, // row height in pixels
    overscan: 20,           // render 20 extra rows outside viewport
  });

  // Load more pages when scrolling near the end
  const items = virtualizer.getVirtualItems();
  const lastItem = items[items.length - 1];
  useEffect(() => {
    if (lastItem && lastItem.index >= entries.length - 50) {
      loadMoreEntries(); // invoke list_directory with next offset
    }
  }, [lastItem?.index]);

  return (
    <div ref={parentRef} className="list-view-scroll" style={{ overflow: 'auto', height: '100%' }}>
      <div style={{ height: virtualizer.getTotalSize(), position: 'relative' }}>
        {items.map((virtualRow) => {
          const entry = entries[virtualRow.index];
          if (!entry) return null;
          return (
            <div
              key={virtualRow.key}
              className="list-row"
              style={{
                position: 'absolute',
                top: virtualRow.start,
                height: 28,
                width: '100%',
              }}
            >
              <FileRow entry={entry} />
            </div>
          );
        })}
      </div>
    </div>
  );
}
```

### 5.5 Performance Summary Table

| Layer | Technique | Impact |
|-------|-----------|--------|
| Rust enumeration | `tokio::fs::read_dir` (async, non-blocking) | No UI thread blocking |
| Rust sorting | Server-side sort with `natord` for natural name ordering | Frontend receives pre-sorted data |
| Rust caching | In-memory `HashMap<String, Vec<FileEntry>>` per sort config | Instant page loads after first fetch |
| Cache invalidation | `notify` crate watches current directory | Cache stays fresh |
| IPC pagination | 500-entry pages via `offset`/`limit` | Reduces IPC payload size |
| Frontend rendering | TanStack Virtual (virtualized list/grid) | Constant DOM nodes (~50) |
| Frontend debounce | 150ms debounce on search/filter input | Prevents excessive re-renders |
| Lazy metadata | Thumbnails/previews loaded on-demand for visible rows only | Minimal upfront work |

---

## 6. File System Operations

### 6.1 Rust Command Table

| Command | Parameters | Description |
|---------|-----------|-------------|
| `list_directory` | path, sort_by, sort_dir, offset, limit | Paginated, sorted directory listing |
| `move_files` | sources: Vec<String>, destination: String | Move files (cut+paste) |
| `copy_files` | sources: Vec<String>, destination: String | Copy files |
| `delete_files` | paths: Vec<String>, use_trash: bool | Delete or move to trash |
| `rename_file` | path: String, new_name: String | Rename a file/folder |
| `create_folder` | parent: String, name: String | Create new directory |
| `get_file_info` | path: String | Detailed metadata for preview |
| `open_file` | path: String | Open with default macOS app |
| `reveal_in_finder` | path: String | Show in Finder |

### 6.2 Move Implementation Details

The `move_files` command (shown in §4.2) handles two cases:
1. **Same volume:** Uses `std::fs::rename()` — instant, atomic.
2. **Cross-volume:** Detects `EXDEV` error, falls back to recursive copy + delete.

### 6.3 Trash Support

Uses the `trash` crate, which calls macOS's `NSFileManager.trashItem` under the hood:

```rust
#[tauri::command]
pub async fn delete_files(paths: Vec<String>, use_trash: bool) -> Result<usize, String> {
    let mut deleted = 0;
    for path_str in &paths {
        let path = PathBuf::from(path_str);
        if use_trash {
            trash::delete(&path).map_err(|e| e.to_string())?;
        } else {
            if path.is_dir() {
                std::fs::remove_dir_all(&path).map_err(|e| e.to_string())?;
            } else {
                std::fs::remove_file(&path).map_err(|e| e.to_string())?;
            }
        }
        deleted += 1;
    }
    Ok(deleted)
}
```

### 6.4 Open with Default App

```rust
#[tauri::command]
pub async fn open_file(path: String) -> Result<(), String> {
    std::process::Command::new("open")
        .arg(&path)
        .spawn()
        .map_err(|e| e.to_string())?;
    Ok(())
}
```

### 6.5 File Kind Detection

```rust
fn get_kind(name: &str, is_dir: bool) -> String {
    if is_dir {
        return "Folder".into();
    }
    match name.rsplit('.').next() {
        Some(ext) => match ext.to_lowercase().as_str() {
            "pdf" => "PDF Document",
            "png" => "PNG Image",
            "jpg" | "jpeg" => "JPEG Image",
            "gif" => "GIF Image",
            "svg" => "SVG Image",
            "mp4" | "mov" => "Video",
            "mp3" | "wav" | "aac" => "Audio",
            "rs" => "Rust Source",
            "ts" | "tsx" => "TypeScript",
            "js" | "jsx" => "JavaScript",
            "json" => "JSON",
            "md" => "Markdown",
            "txt" => "Plain Text",
            "zip" | "gz" | "tar" => "Archive",
            "dmg" => "Disk Image",
            "app" => "Application",
            other => other,
        }
        .into(),
        None => "Document".into(),
    }
}
```

---

## 7. Persistence

### 7.1 Storage Approach

Use **`tauri-plugin-store`** (official Tauri v2 plugin) for JSON-based key-value persistence. Store file location: `~/Library/Application Support/com.explorer.app/store.json`.

### 7.2 What Gets Persisted

| Key | Type | Description |
|-----|------|-------------|
| `favorites` | `Favorite[]` | Pinned sidebar folders |
| `preferences` | `Preferences` | Show hidden files, default view, icon size, etc. |
| `window_state` | `WindowState` | Window position, size, sidebar width |
| `recent_paths` | `string[]` | Last 20 visited directories (for "Recent" in sidebar) |
| `column_widths` | `Record<string, number>` | Custom column widths in list view |

### 7.3 Data Types

```rust
#[derive(Serialize, Deserialize, Clone)]
pub struct Favorite {
    pub path: String,
    pub label: String,
}

#[derive(Serialize, Deserialize, Clone)]
pub struct Preferences {
    pub show_hidden_files: bool,
    pub default_view: String,       // "list" | "icon" | "column"
    pub icon_size: u32,             // 64 | 96 | 128
    pub confirm_delete: bool,
    pub default_sort_field: String,
    pub default_sort_dir: String,
}

#[derive(Serialize, Deserialize, Clone)]
pub struct WindowState {
    pub x: f64,
    pub y: f64,
    pub width: f64,
    pub height: f64,
    pub sidebar_width: f64,
    pub is_maximized: bool,
}
```

### 7.4 Window State Restoration

On app launch, read `window_state` from store and apply to the Tauri window. On `close_requested` event, save current window geometry.

```rust
// src-tauri/src/main.rs (setup hook)
app.on_window_event(|window, event| {
    if let tauri::WindowEvent::CloseRequested { .. } = event {
        let size = window.outer_size().unwrap();
        let pos = window.outer_position().unwrap();
        // Save to store...
    }
});
```

---

## 8. Project Structure

```
explorer/
├── package.json                  # npm workspace root
├── tsconfig.json
├── tailwind.config.ts
├── vite.config.ts
├── index.html
│
├── src/                          # React frontend
│   ├── main.tsx                  # React entry point
│   ├── App.tsx                   # Root component, keyboard handler
│   ├── styles/
│   │   ├── globals.css           # CSS variables, dark mode, base styles
│   │   └── tailwind.css          # Tailwind imports
│   │
│   ├── components/
│   │   ├── Sidebar/
│   │   │   ├── Sidebar.tsx       # Left sidebar container
│   │   │   ├── FavoritesList.tsx  # Favorites with DnD
│   │   │   ├── FavoriteItem.tsx   # Single favorite entry
│   │   │   └── DevicesList.tsx    # Volumes/devices section
│   │   │
│   │   ├── Toolbar/
│   │   │   ├── Toolbar.tsx       # Top toolbar container
│   │   │   ├── UpButton.tsx      # Parent directory button
│   │   │   ├── NavButtons.tsx    # Back/Forward buttons
│   │   │   ├── Breadcrumb.tsx    # Path breadcrumb trail
│   │   │   ├── SearchInput.tsx   # Filter/search input
│   │   │   └── ViewModeToggle.tsx # List/Icon/Column toggle
│   │   │
│   │   ├── ContentArea/
│   │   │   ├── ContentArea.tsx   # View mode switcher
│   │   │   ├── ListView.tsx      # Table/list view (virtual)
│   │   │   ├── IconView.tsx      # Grid/icon view (virtual)
│   │   │   ├── ColumnView.tsx    # Miller column view
│   │   │   ├── ColumnPanel.tsx   # Single column in column view
│   │   │   ├── FileRow.tsx       # Row component for list view
│   │   │   ├── FileIcon.tsx      # File type icon renderer
│   │   │   └── ColumnHeader.tsx  # Sortable column header
│   │   │
│   │   ├── ContextMenu/
│   │   │   ├── ContextMenu.tsx   # Right-click context menu
│   │   │   └── MenuItems.tsx     # Menu item definitions
│   │   │
│   │   ├── StatusBar/
│   │   │   └── StatusBar.tsx     # Bottom bar: item count, disk space, icon slider
│   │   │
│   │   └── Dialogs/
│   │       ├── RenameDialog.tsx  # Inline rename input
│   │       └── ConflictDialog.tsx # Name conflict resolution
│   │
│   ├── stores/
│   │   ├── navigationStore.ts    # Path, history, back/forward/up
│   │   ├── directoryStore.ts     # File entries, loading, pagination
│   │   ├── sortStore.ts          # Sort field + direction
│   │   ├── clipboardStore.ts     # Cut/copy/paste buffer
│   │   ├── favoritesStore.ts     # Pinned folders
│   │   ├── viewStore.ts          # View mode, column widths
│   │   ├── selectionStore.ts     # Selected files, multi-select
│   │   └── preferencesStore.ts   # User preferences
│   │
│   ├── hooks/
│   │   ├── useKeyboardShortcuts.ts  # Global shortcut handler
│   │   ├── useFsWatcher.ts          # Listen for fs:changed events
│   │   └── useContextMenu.ts        # Right-click hook
│   │
│   ├── lib/
│   │   ├── commands.ts           # Typed wrappers around invoke()
│   │   ├── fileTypes.ts          # Icon mapping, kind helpers
│   │   ├── formatters.ts         # Size formatting, date formatting
│   │   └── paths.ts              # Path manipulation utilities
│   │
│   └── types/
│       └── index.ts              # TypeScript interfaces (FileEntry, etc.)
│
├── src-tauri/                    # Rust backend
│   ├── Cargo.toml
│   ├── tauri.conf.json           # Tauri config (window, permissions, plugins)
│   ├── capabilities/
│   │   └── default.json          # Permission grants for commands
│   ├── src/
│   │   ├── main.rs               # Tauri entry point, plugin registration
│   │   ├── lib.rs                # Command registration
│   │   ├── commands/
│   │   │   ├── mod.rs
│   │   │   ├── directory.rs      # list_directory, get_file_info
│   │   │   ├── file_ops.rs       # move, copy, delete, rename, create
│   │   │   ├── favorites.rs      # CRUD for favorites
│   │   │   ├── preferences.rs    # Get/set preferences
│   │   │   └── system.rs         # open_file, reveal_in_finder, get_volumes
│   │   ├── watcher.rs            # FS watcher (notify crate)
│   │   ├── cache.rs              # Directory listing cache
│   │   └── utils.rs              # get_kind, path helpers
│   │
│   └── icons/                    # App icons (icns for macOS)
│       └── icon.icns
│
└── README.md
```

---

## 9. Build & Distribution

### 9.1 Development

```bash
# Install dependencies
npm install
cd src-tauri && cargo build && cd ..

# Start dev server (hot-reload frontend + Rust rebuilds)
npm run tauri dev
```

### 9.2 Production Build

```bash
# Build optimized release
npm run tauri build
# Output: src-tauri/target/release/bundle/dmg/Explorer_x.y.z_aarch64.dmg
#         src-tauri/target/release/bundle/macos/Explorer.app
```

### 9.3 Tauri Build Config

```json
// src-tauri/tauri.conf.json (key sections)
{
  "productName": "Explorer",
  "version": "0.1.0",
  "identifier": "com.explorer.app",
  "build": {
    "frontendDist": "../dist"
  },
  "app": {
    "windows": [
      {
        "title": "Explorer",
        "width": 1200,
        "height": 800,
        "minWidth": 600,
        "minHeight": 400,
        "decorations": true,
        "transparent": true,
        "titleBarStyle": "Overlay",
        "hiddenTitle": true
      }
    ],
    "security": {
      "csp": "default-src 'self'; img-src 'self' asset: https://asset.localhost"
    }
  },
  "bundle": {
    "active": true,
    "targets": ["dmg", "app"],
    "icon": ["icons/icon.icns"],
    "macOS": {
      "minimumSystemVersion": "13.0",
      "signingIdentity": null,
      "entitlements": null
    }
  },
  "plugins": {
    "store": {}
  }
}
```

### 9.4 macOS Code Signing

For distribution outside the App Store:
1. Obtain an Apple Developer ID certificate
2. Set `APPLE_SIGNING_IDENTITY` environment variable
3. Notarize with `xcrun notarytool submit`
4. Tauri's `tauri build` handles signing + notarization when configured

### 9.5 Universal Binary (Intel + Apple Silicon)

```bash
# Build universal macOS binary
npm run tauri build -- --target universal-apple-darwin
```

Requires both `x86_64-apple-darwin` and `aarch64-apple-darwin` Rust targets installed:
```bash
rustup target add x86_64-apple-darwin aarch64-apple-darwin
```

---

## 10. Pros & Cons

### ✅ Pros

| Aspect | Detail |
|--------|--------|
| **Binary size** | ~8–15 MB vs Electron's ~150 MB (uses system WebView) |
| **Memory usage** | ~30–60 MB vs Electron's ~150–300 MB |
| **Performance** | Rust backend for file ops is orders of magnitude faster than Node.js |
| **Security** | Tauri's permission model restricts filesystem access by default |
| **macOS integration** | Native window chrome, vibrancy, `NSFileManager` APIs accessible via Rust |
| **Cross-platform potential** | Same codebase can target Linux/Windows later (change UI theme) |
| **Ecosystem** | Full React/TypeScript ecosystem for UI (component libs, tooling, testing) |
| **Build tooling** | Vite for sub-second HMR, cargo for optimized release builds |
| **File system ops** | Rust's `std::fs` + `tokio::fs` is robust, fast, and well-tested |

### ❌ Cons

| Aspect | Detail |
|--------|--------|
| **WKWebView limitations** | Safari's rendering engine has quirks (no SharedArrayBuffer, some CSS gaps) |
| **Not truly native UI** | Despite styling, it's HTML/CSS in a WebView — screen readers, native drag-and-drop have edges |
| **Rust learning curve** | Team must be comfortable with Rust for backend changes |
| **macOS-only WKWebView** | On Linux/Windows, WebView2 or WebKitGTK have different behaviors |
| **File thumbnails** | Generating thumbnails (e.g., image previews) requires custom Rust code or shelling out to `qlmanage` |
| **Spotlight/metadata** | No access to macOS Spotlight index or extended attributes without custom FFI |
| **Finder feature gaps** | Quick Look preview, Tags, AirDrop integration require significant macOS FFI work |
| **Debug experience** | Debugging spans two runtimes (browser DevTools for frontend, lldb for Rust) |
| **Vibrancy API** | Tauri v2's vibrancy support is limited to whole-window; per-region vibrancy needs raw `objc2` |
| **IPC overhead** | Every file op crosses the IPC boundary; serialization cost for large payloads |

### ⚠️ Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| WKWebView rendering inconsistencies | Test on macOS 13, 14, 15; use standard CSS; avoid bleeding-edge APIs |
| 100k file enumeration takes >1s | Show loading skeleton immediately; stream first page fast; cache aggressively |
| Cross-volume move data loss | Always copy-then-delete (never delete first); verify copy integrity |
| Tauri v2 API breaking changes | Pin to specific Tauri v2.x version; follow Tauri's migration guides |

---

## 11. ASCII Mockup

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ ● ● ●                          Explorer                                    │
├──────────┬──────────────────────────────────────────────────────────────────┤
│          │  ◀  ▶  ▲   / Users / ehamai / Projects        🔍 Search      │
│          │  ←  →  ↑   \_breadcrumb trail__________/      [≡] [⊞] [⫏]    │
│ FAVORITES│  nav  Up                                       List Icon Col    │
│──────────│──────────────────────────────────────────────────────────────────│
│          │                                                                  │
│ 🏠 Home  │  Name              Date Modified      Size      Kind            │
│ 🖥 Desktop│  ─────────────────────────────────────────────────────          │
│ 📁 Docs  │  📁 .git            Dec 15, 2024      —         Folder          │
│ 📥 Downl │  📁 node_modules    Dec 14, 2024      —         Folder          │
│ 💼 Projec│  📁 src             Dec 16, 2024      —         Folder          │
│          │  📁 src-tauri       Dec 16, 2024      —         Folder          │
│ ─────────│  📄 .gitignore      Dec 10, 2024      1.2 KB    Plain Text      │
│          │  📄 Cargo.toml      Dec 15, 2024      892 B     TOML            │
│ DEVICES  │  📄 index.html      Dec 12, 2024      423 B     HTML            │
│ 💻 Macint│  📄 package.json    Dec 16, 2024      1.5 KB    JSON            │
│          │  📄 README.md       Dec 16, 2024      3.2 KB    Markdown        │
│          │  📄 tsconfig.json   Dec 12, 2024      645 B     JSON            │
│          │  📄 vite.config.ts  Dec 12, 2024      312 B     TypeScript      │
│          │                                                                  │
│          │                                                                  │
│          │                                                                  │
│          │                                                                  │
├──────────┴──────────────────────────────────────────────────────────────────┤
│ 11 items  ·  42.5 GB available                                    ◀═●══▶  │
│ status bar                                                     icon slider │
└─────────────────────────────────────────────────────────────────────────────┘

Layout Key:
─────────────────────────────────────────────
  ● ● ●           = macOS traffic light buttons (close/minimize/maximize)
  ◀ ▶             = Back / Forward navigation buttons
  ▲ (Up)          = UP BUTTON — always visible, goes to parent directory
  / Users / ...   = Clickable breadcrumb path segments
  🔍              = Filter/search input (filters current directory)
  [≡] [⊞] [⫏]   = View mode toggle: List / Icon / Column
  FAVORITES       = Sidebar section: pinned folders (drag to add, right-click to remove)
  DEVICES         = Sidebar section: mounted volumes
  Name / Date ... = Sortable column headers (click to sort, arrow shows direction)
  Content area    = Virtual-scrolled file listing (handles 100k+ files)
  Status bar      = Item count, available space, icon size slider (for icon view)
  ◀═●══▶         = Icon size slider (visible in Icon view mode)

Keyboard Shortcuts:
─────────────────────────────────────────────
  ⌘↑              Navigate to parent directory (Up button)
  ⌘X              Cut selected files
  ⌘C              Copy selected files
  ⌘V              Paste (move if cut, copy if copied)
  ⌘⌫             Move selected files to Trash
  ⌘D              Add current folder to Favorites
  ⌘1 / ⌘2 / ⌘3  Switch to List / Icon / Column view
  ⌘A              Select all files
  ⌘N              New Finder window
  ⌘⇧N            New folder
  Enter            Rename selected file (inline edit)
  Space            Quick Look preview (future)
  ⌘.              Toggle hidden files
  ⌘F              Focus search/filter input
  ⌘[ / ⌘]        Back / Forward navigation
```

### Icon View Mockup

```
┌──────────┬──────────────────────────────────────────────────────────────────┐
│          │  ◀  ▶  ▲   / Users / ehamai / Pictures       🔍               │
│ FAVORITES│──────────────────────────────────────────────────[≡] [⊞] [⫏]──│
│──────────│                                                                  │
│ 🏠 Home  │   ┌────────┐  ┌────────┐  ┌────────┐  ┌────────┐               │
│ 🖥 Desktop│   │        │  │        │  │        │  │        │               │
│ 📁 Docs  │   │  📁    │  │  📁    │  │  🖼    │  │  🖼    │               │
│ 📥 Downl │   │        │  │        │  │        │  │        │               │
│          │   └────────┘  └────────┘  └────────┘  └────────┘               │
│          │   Vacation     Screenshots  IMG_001     IMG_002                  │
│          │                                                                  │
│          │   ┌────────┐  ┌────────┐  ┌────────┐  ┌────────┐               │
│          │   │        │  │        │  │        │  │        │               │
│          │   │  🖼    │  │  🖼    │  │  📄    │  │  📄    │               │
│          │   │        │  │        │  │        │  │        │               │
│          │   └────────┘  └────────┘  └────────┘  └────────┘               │
│          │   IMG_003     IMG_004     notes.txt   readme.md                  │
│          │                                                                  │
├──────────┴──────────────────────────────────────────────────────────────────┤
│ 8 items  ·  42.5 GB available                                     ◀═●══▶  │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Column View Mockup

```
┌──────────┬──────────────────────────────────────────────────────────────────┐
│          │  ◀  ▶  ▲   / Users / ehamai                  🔍               │
│ FAVORITES│──────────────────────────────────────────────────[≡] [⊞] [⫏]──│
│──────────│                                                                  │
│ 🏠 Home  │  Users       │ ehamai       │ Projects      │ explorer         │
│ 🖥 Desktop│ ────────────│──────────────│───────────────│────────────────   │
│ 📁 Docs  │  admin      │ .config      │ explorer    ▶ │  📁 .git         │
│ 📥 Downl │  ehamai   ▶ │  Desktop     │  rust-app     │  📁 node_modules │
│          │  guest      │  Documents   │  web-ui       │  📁 src           │
│          │  shared     │  Downloads   │  api-server   │  📁 src-tauri     │
│          │             │  Movies      │               │  📄 package.json  │
│          │             │  Music       │               │  📄 README.md     │
│          │             │  Pictures    │               │  📄 tsconfig.json │
│          │             │  Projects  ▶ │               │                    │
│          │             │  Public      │               │                    │
│          │             │              │               │                    │
├──────────┴──────────────────────────────────────────────────────────────────┤
│ 7 items in "explorer"  ·  42.5 GB available                                │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Appendix A: Key TypeScript Interfaces

```typescript
// src/types/index.ts

export interface FileEntry {
  name: string;
  path: string;
  is_dir: boolean;
  size: number;
  modified_at: number;   // Unix timestamp ms
  kind: string;
  is_hidden: boolean;
  permissions: number;
}

export interface DirectoryListing {
  path: string;
  entries: FileEntry[];
  total_count: number;
  offset: number;
  has_more: boolean;
}

export interface Favorite {
  path: string;
  label: string;
}

export interface PasteResult {
  moved: number;
  failed: Array<{ path: string; error: string }>;
}

export type SortField = 'name' | 'date_modified' | 'size' | 'kind';
export type SortDirection = 'asc' | 'desc';
export type ViewMode = 'list' | 'icon' | 'column';
```

## Appendix B: Keyboard Shortcut Registry

```typescript
// src/hooks/useKeyboardShortcuts.ts
import { useEffect } from 'react';
import { useNavigationStore } from '@/stores/navigationStore';
import { useClipboardStore } from '@/stores/clipboardStore';
import { useSelectionStore } from '@/stores/selectionStore';
import { useViewStore } from '@/stores/viewStore';

export function useKeyboardShortcuts() {
  const { navigateUp, goBack, goForward, currentPath } = useNavigationStore();
  const { cut, copy, paste } = useClipboardStore();
  const { selectedPaths, selectAll } = useSelectionStore();
  const { setMode } = useViewStore();

  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      const meta = e.metaKey; // Cmd on macOS
      if (!meta) return;

      switch (e.key) {
        case 'ArrowUp':
          e.preventDefault();
          navigateUp();
          break;
        case 'x':
          e.preventDefault();
          cut(selectedPaths);
          break;
        case 'c':
          e.preventDefault();
          copy(selectedPaths);
          break;
        case 'v':
          e.preventDefault();
          paste(currentPath);
          break;
        case 'a':
          e.preventDefault();
          selectAll();
          break;
        case 'Backspace':
          e.preventDefault();
          // delete selected files (move to trash)
          break;
        case '1':
          e.preventDefault();
          setMode('list');
          break;
        case '2':
          e.preventDefault();
          setMode('icon');
          break;
        case '3':
          e.preventDefault();
          setMode('column');
          break;
        case '[':
          e.preventDefault();
          goBack();
          break;
        case ']':
          e.preventDefault();
          goForward();
          break;
      }
    };

    window.addEventListener('keydown', handler);
    return () => window.removeEventListener('keydown', handler);
  }, [selectedPaths, currentPath]);
}
```

## Appendix C: Navigation Store with History

```typescript
// src/stores/navigationStore.ts
import { create } from 'zustand';
import { invoke } from '@tauri-apps/api/core';
import { useDirectoryStore } from './directoryStore';
import { useSortStore } from './sortStore';

interface NavigationState {
  currentPath: string;
  history: string[];
  historyIndex: number;

  navigate: (path: string) => void;
  navigateUp: () => void;
  goBack: () => void;
  goForward: () => void;
  getBreadcrumbs: () => Array<{ label: string; path: string }>;
}

export const useNavigationStore = create<NavigationState>((set, get) => ({
  currentPath: '/Users/' + (process.env.USER || 'user'),
  history: ['/Users/' + (process.env.USER || 'user')],
  historyIndex: 0,

  navigate: (path: string) => {
    const { history, historyIndex } = get();
    // Truncate forward history
    const newHistory = [...history.slice(0, historyIndex + 1), path];
    set({
      currentPath: path,
      history: newHistory,
      historyIndex: newHistory.length - 1,
    });
    // Trigger directory fetch
    const { field, direction } = useSortStore.getState();
    useDirectoryStore.getState().fetchDirectory(path, field, direction);
  },

  navigateUp: () => {
    const { currentPath, navigate } = get();
    if (currentPath === '/') return;
    const parent = currentPath.split('/').slice(0, -1).join('/') || '/';
    navigate(parent);
  },

  goBack: () => {
    const { history, historyIndex } = get();
    if (historyIndex <= 0) return;
    const newIndex = historyIndex - 1;
    const path = history[newIndex];
    set({ currentPath: path, historyIndex: newIndex });
    const { field, direction } = useSortStore.getState();
    useDirectoryStore.getState().fetchDirectory(path, field, direction);
  },

  goForward: () => {
    const { history, historyIndex } = get();
    if (historyIndex >= history.length - 1) return;
    const newIndex = historyIndex + 1;
    const path = history[newIndex];
    set({ currentPath: path, historyIndex: newIndex });
    const { field, direction } = useSortStore.getState();
    useDirectoryStore.getState().fetchDirectory(path, field, direction);
  },

  getBreadcrumbs: () => {
    const { currentPath } = get();
    const parts = currentPath.split('/').filter(Boolean);
    return parts.map((part, i) => ({
      label: part,
      path: '/' + parts.slice(0, i + 1).join('/'),
    }));
  },
}));
```

---

*End of Plan B — Tauri v2 + React + TypeScript Implementation Plan*
