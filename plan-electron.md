# Implementation Plan: Windows File Explorer Clone for macOS (Apple Silicon)

## Approach: Electron + React + TypeScript

---

## 1. Technology Stack

| Layer | Technology | Version | Rationale |
|---|---|---|---|
| **Runtime** | Electron | 33+ | Mature, full Node.js API access, proven for file managers (VS Code) |
| **UI Framework** | React | 18.3+ | Component model ideal for complex UIs, massive ecosystem |
| **Language** | TypeScript | 5.4+ | Type safety across main/renderer processes, shared types |
| **UI Library** | Fluent UI React v9 (`@fluentui/react-components`) | 9.x | Microsoft's own design system — closest match to Windows 11 look and feel |
| **State Management** | Zustand | 4.x | Lightweight, no boilerplate, supports middleware for persistence; simpler than Redux for file system state |
| **Virtualization** | `@tanstack/react-virtual` | 3.x | Efficient rendering of 10,000+ file lists without DOM bloat |
| **File Watching** | chokidar | 3.x | Cross-platform fs watching with debouncing; handles macOS FSEvents natively |
| **Tree View** | react-arborist | 3.x | Full-featured tree component with drag-and-drop, virtualization, keyboard nav |
| **Drag & Drop** | `@dnd-kit/core` + `@dnd-kit/sortable` | 6.x | Modern, accessible, framework-agnostic DnD |
| **Icons** | `@fluentui/react-icons` | 2.x | 4,000+ Fluent icons matching Windows aesthetic |
| **Search** | fuse.js (in-memory) + Node.js `find`/`mdfind` (disk) | — | Fuzzy matching for quick filter; Spotlight integration for deep search |
| **Context Menus** | `electron-context-menu` + custom React menu | — | Native feel for right-click |
| **Bundler** | Vite | 5.x | Fast HMR for renderer; use `electron-vite` for unified config |
| **Packaging** | `electron-builder` | 24+ | Proven macOS DMG/pkg creation with Apple Silicon support |
| **Testing** | Vitest (unit) + Playwright (E2E) | — | Fast unit tests; Playwright has Electron support |
| **Linting** | ESLint + Prettier | — | Standard TypeScript config |

### Why Fluent UI v9 Specifically

Fluent UI v9 is Microsoft's latest design system used in Microsoft 365 and Windows 11. It provides:
- `Tree` component with expand/collapse — maps to Navigation Pane
- `DataGrid` component — maps to Details View columns with sorting
- `Toolbar` / `Ribbon`-like components — maps to the command bar
- `TabList` — maps to Windows 11 File Explorer tabs
- `Breadcrumb` — maps to the address bar
- `Dialog`, `Menu`, `Tooltip` — all match Windows 11 styling out of the box
- Built-in theming that can match Windows 11 light/dark modes

This eliminates 60-70% of custom styling work compared to using a generic UI library.

---

## 2. Architecture

### 2.1 Process Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    MAIN PROCESS (Node.js)                    │
│                                                             │
│  ┌──────────────┐  ┌──────────────┐  ┌────────────────────┐ │
│  │ FileSystem    │  │ WindowManager│  │ NativeIntegration  │ │
│  │ Service       │  │              │  │ (Dock, Menu, Touch │ │
│  │ (fs, chokidar)│  │ (BrowserWin) │  │  Bar, Spotlight)   │ │
│  └──────┬───────┘  └──────┬───────┘  └────────┬───────────┘ │
│         │                 │                    │             │
│  ┌──────┴─────────────────┴────────────────────┴───────────┐ │
│  │                    IPC Bridge                            │ │
│  │         (contextBridge + ipcMain/ipcRenderer)            │ │
│  └──────────────────────┬──────────────────────────────────┘ │
└─────────────────────────┼───────────────────────────────────┘
                          │
┌─────────────────────────┼───────────────────────────────────┐
│              RENDERER PROCESS (Chromium)                      │
│                          │                                   │
│  ┌───────────────────────┴─────────────────────────────────┐ │
│  │                  React Application                       │ │
│  │                                                         │ │
│  │  ┌─────────┐ ┌──────────┐ ┌──────────┐ ┌────────────┐  │ │
│  │  │ Nav Pane│ │ Content  │ │ Toolbar  │ │ Tab Manager│  │ │
│  │  │ (Tree)  │ │ Area     │ │ (Ribbon) │ │            │  │ │
│  │  └─────────┘ └──────────┘ └──────────┘ └────────────┘  │ │
│  │                                                         │ │
│  │  ┌───────────────────────────────────────────────────┐  │ │
│  │  │           Zustand Store (State Management)         │  │ │
│  │  │  - fileSystemStore (current dir, files, selection) │  │ │
│  │  │  - navigationStore (history, tabs, breadcrumbs)    │  │ │
│  │  │  - uiStore (view mode, pane sizes, preferences)    │  │ │
│  │  │  - clipboardStore (copy/cut/paste operations)      │  │ │
│  │  │  - searchStore (query, results, filters)           │  │ │
│  │  └───────────────────────────────────────────────────┘  │ │
│  └─────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

### 2.2 IPC Design

Use `contextBridge` with a typed API — **never expose `ipcRenderer` directly** to the renderer.

```typescript
// shared/types/ipc.ts — Shared type definitions
interface FileEntry {
  name: string;
  path: string;
  isDirectory: boolean;
  size: number;
  modified: Date;
  created: Date;
  accessed: Date;
  permissions: string;
  isHidden: boolean;
  isSymlink: boolean;
  extension: string;
  icon?: string; // base64 or file:// URL from app.getFileIcon()
}

interface DirectoryContents {
  path: string;
  entries: FileEntry[];
  totalItems: number;
  totalSize: number;
}

// IPC Channel Map (all channels are typed)
type IpcChannels = {
  // File System - Read
  'fs:readDirectory': (path: string) => Promise<DirectoryContents>;
  'fs:getFileInfo': (path: string) => Promise<FileEntry>;
  'fs:getDrives': () => Promise<DriveInfo[]>;
  'fs:getHomeDir': () => Promise<string>;
  'fs:resolveSymlink': (path: string) => Promise<string>;
  'fs:getFileIcon': (path: string, size: number) => Promise<string>;
  'fs:exists': (path: string) => Promise<boolean>;

  // File System - Write
  'fs:createDirectory': (path: string) => Promise<void>;
  'fs:delete': (paths: string[], useTrash: boolean) => Promise<void>;
  'fs:rename': (oldPath: string, newPath: string) => Promise<void>;
  'fs:copy': (sources: string[], destination: string) => Promise<void>;
  'fs:move': (sources: string[], destination: string) => Promise<void>;
  'fs:paste': (destination: string, operation: 'copy' | 'cut') => Promise<void>;

  // File System - Watch
  'fs:watch': (path: string) => void;
  'fs:unwatch': (path: string) => void;
  'fs:onChanged': (callback: (event: FsEvent) => void) => void;

  // Search
  'search:find': (query: string, directory: string, options: SearchOptions) => Promise<SearchResult[]>;
  'search:spotlight': (query: string, scope: string) => Promise<SearchResult[]>;
  'search:cancel': () => void;

  // Shell Integration
  'shell:openFile': (path: string) => Promise<void>;
  'shell:openInTerminal': (path: string) => Promise<void>;
  'shell:showInFinder': (path: string) => Promise<void>;
  'shell:getTrashPath': () => Promise<string>;

  // Dialogs
  'dialog:properties': (path: string) => Promise<void>;
  'dialog:confirm': (message: string) => Promise<boolean>;

  // Clipboard
  'clipboard:getFiles': () => Promise<string[]>;
  'clipboard:setFiles': (paths: string[], operation: 'copy' | 'cut') => void;

  // Window
  'window:setTitle': (title: string) => void;
};
```

```typescript
// preload.ts — Exposes typed API to renderer via contextBridge
import { contextBridge, ipcRenderer } from 'electron';

const electronAPI = {
  fs: {
    readDirectory: (path: string) => ipcRenderer.invoke('fs:readDirectory', path),
    getFileInfo: (path: string) => ipcRenderer.invoke('fs:getFileInfo', path),
    createDirectory: (path: string) => ipcRenderer.invoke('fs:createDirectory', path),
    delete: (paths: string[], useTrash: boolean) => ipcRenderer.invoke('fs:delete', paths, useTrash),
    rename: (old: string, newPath: string) => ipcRenderer.invoke('fs:rename', old, newPath),
    copy: (sources: string[], dest: string) => ipcRenderer.invoke('fs:copy', sources, dest),
    move: (sources: string[], dest: string) => ipcRenderer.invoke('fs:move', sources, dest),
    watch: (path: string) => ipcRenderer.send('fs:watch', path),
    unwatch: (path: string) => ipcRenderer.send('fs:unwatch', path),
    onChanged: (cb: (event: FsEvent) => void) => {
      const listener = (_: any, event: FsEvent) => cb(event);
      ipcRenderer.on('fs:changed', listener);
      return () => ipcRenderer.removeListener('fs:changed', listener);
    },
    getFileIcon: (path: string, size: number) => ipcRenderer.invoke('fs:getFileIcon', path, size),
    getDrives: () => ipcRenderer.invoke('fs:getDrives'),
    getHomeDir: () => ipcRenderer.invoke('fs:getHomeDir'),
  },
  search: {
    find: (query: string, dir: string, opts: SearchOptions) =>
      ipcRenderer.invoke('search:find', query, dir, opts),
    spotlight: (query: string, scope: string) =>
      ipcRenderer.invoke('search:spotlight', query, scope),
    cancel: () => ipcRenderer.send('search:cancel'),
  },
  shell: {
    openFile: (path: string) => ipcRenderer.invoke('shell:openFile', path),
    openInTerminal: (path: string) => ipcRenderer.invoke('shell:openInTerminal', path),
    showInFinder: (path: string) => ipcRenderer.invoke('shell:showInFinder', path),
  },
  clipboard: {
    getFiles: () => ipcRenderer.invoke('clipboard:getFiles'),
    setFiles: (paths: string[], op: 'copy' | 'cut') => ipcRenderer.send('clipboard:setFiles', paths, op),
  },
  dialog: {
    properties: (path: string) => ipcRenderer.invoke('dialog:properties', path),
  },
};

contextBridge.exposeInMainWorld('electronAPI', electronAPI);
```

### 2.3 Module Breakdown (Main Process)

```
src/
├── main/
│   ├── index.ts                    # App entry, window creation
│   ├── ipc/
│   │   ├── registerHandlers.ts     # Registers all IPC handlers
│   │   ├── fileSystemHandlers.ts   # fs:* channel handlers
│   │   ├── searchHandlers.ts       # search:* channel handlers
│   │   ├── shellHandlers.ts        # shell:* channel handlers
│   │   ├── clipboardHandlers.ts    # clipboard:* channel handlers
│   │   └── dialogHandlers.ts       # dialog:* channel handlers
│   ├── services/
│   │   ├── FileSystemService.ts    # Core fs operations (read, write, watch)
│   │   ├── FileWatcherService.ts   # chokidar wrapper with debouncing
│   │   ├── SearchService.ts        # mdfind/find integration
│   │   ├── ThumbnailService.ts     # File icon/thumbnail generation
│   │   ├── TrashService.ts         # shell.trashItem wrapper
│   │   └── ClipboardService.ts     # NSPasteboard integration
│   ├── windows/
│   │   ├── WindowManager.ts        # Window lifecycle, tab management
│   │   └── createMainWindow.ts     # Window config (vibrancy, etc.)
│   └── menu/
│       ├── applicationMenu.ts      # macOS menu bar
│       └── contextMenu.ts          # Right-click menus
├── preload/
│   └── index.ts                    # contextBridge setup
├── renderer/
│   └── (React app — see section 3)
├── shared/
│   ├── types/
│   │   ├── fileSystem.ts           # FileEntry, DirectoryContents, etc.
│   │   ├── ipc.ts                  # IPC channel types
│   │   └── ui.ts                   # ViewMode, SortOrder, etc.
│   ├── constants.ts                # Paths, limits, defaults
│   └── utils.ts                    # Path manipulation, formatting
└── assets/
    ├── icons/                      # App icons (icns for macOS)
    └── themes/                     # Fluent UI theme tokens
```

---

## 3. Key Components / Views

### 3.1 Component Tree

```
<App>
├── <TitleBar />                          # Custom title bar (frameless window)
├── <TabBar />                            # Windows 11-style tabs
│   └── <Tab />                           # Individual tab
├── <Toolbar />                           # Ribbon / command bar
│   ├── <NavigationButtons />             # Back, Forward, Up, Recent
│   ├── <AddressBar />                    # Breadcrumb path bar
│   │   └── <BreadcrumbSegment />         # Clickable path segment
│   └── <SearchBox />                     # Search input
├── <MainLayout />                        # Resizable split layout
│   ├── <NavigationPane />                # Left sidebar
│   │   ├── <QuickAccess />              # Pinned folders
│   │   ├── <FolderTree />               # Full directory tree
│   │   │   └── <TreeNode />             # Expandable folder node
│   │   └── <DrivesSection />            # Mounted volumes
│   ├── <ContentArea />                   # Main file listing
│   │   ├── <DetailsView />              # Table with sortable columns
│   │   │   ├── <ColumnHeader />         # Name, Date Modified, Type, Size
│   │   │   └── <FileRow />             # Single file row (virtualized)
│   │   ├── <IconsView />               # Grid of icon tiles
│   │   │   └── <FileIcon />            # Icon + name
│   │   ├── <TilesView />               # Larger tiles with metadata
│   │   │   └── <FileTile />            # Icon + name + type + size
│   │   └── <EmptyState />              # "This folder is empty"
│   └── <PreviewPane />                  # Optional right-side preview
│       ├── <ImagePreview />             # Image files
│       ├── <TextPreview />              # Text/code files
│       ├── <VideoPreview />             # Video files
│       └── <MetadataPreview />          # File properties summary
├── <StatusBar />                         # Bottom bar
│   ├── <ItemCount />                    # "42 items"
│   ├── <SelectionInfo />               # "3 items selected (1.2 MB)"
│   └── <ViewModeToggle />              # Switch view mode buttons
├── <ContextMenu />                       # Right-click menu (portal)
├── <PropertiesDialog />                  # File/folder properties modal
├── <RenameInput />                       # Inline rename overlay
└── <DragOverlay />                       # Drag-and-drop visual feedback
```

### 3.2 Component Details

#### `<TitleBar />`
- **Why custom**: Frameless window + `titleBarStyle: 'hiddenInset'` gives us macOS traffic lights while allowing a custom tab bar in the title area (like Windows 11).
- **Implementation**: CSS `-webkit-app-region: drag` for draggable area; traffic light buttons via `BrowserWindow.setWindowButtonPosition()`.
- **Complexity**: Medium — need to handle window controls offset on macOS.

#### `<TabBar />`
- **Renders**: Fluent UI `<TabList>` with horizontal scrolling.
- **State**: `navigationStore.tabs[]` — each tab has its own path, history stack, and selection state.
- **Features**: Add tab (+), close tab (×), reorder via drag, middle-click to close, context menu (Close Other Tabs, Duplicate Tab).
- **Key challenge**: Each tab needs independent navigation history but shares the same Electron window.

#### `<Toolbar />`
- **Renders**: Fluent UI `<Toolbar>` with grouped buttons.
- **Sections**: Clipboard (Cut/Copy/Paste), Organize (Move to, Copy to, Delete, Rename), New (New Folder, New File), Layout (View mode, Sort by, Group by), Selection (Select All, Select None, Invert).
- **Responsive**: Collapses into overflow menu on narrow windows.

#### `<AddressBar />`
- **Dual mode**: Breadcrumb display mode (default) and text input mode (click to edit).
- **Breadcrumb mode**: Each segment is clickable (navigates) and has a `>` chevron dropdown showing sibling folders.
- **Input mode**: Full path text input with autocomplete dropdown (suggests matching folder names as you type).
- **Implementation**: Custom component wrapping Fluent UI `<Breadcrumb>` + `<Input>`. The chevron dropdowns require `<MenuPopover>` that loads sibling directories on demand.
- **Complexity**: High — the sibling-folder dropdown on each chevron is the hardest part.

#### `<NavigationPane />`
- **Renders**: Three collapsible sections inside a resizable panel.
- **Quick Access**: Hardcoded favorites (Desktop, Documents, Downloads, Pictures) + user-pinned folders. Stored in persistent Zustand state (via `zustand/middleware` persist to `localStorage`).
- **Folder Tree**: Uses `react-arborist` for virtualized tree rendering. Nodes expand lazily (directory contents fetched on expand via IPC). Shows expand/collapse chevrons and folder icons.
- **Drives/Volumes**: Lists mounted volumes from `fs:getDrives` which runs `diskutil list` under the hood.
- **Drag targets**: Each tree node is a valid drop target for file move/copy.

#### `<DetailsView />`
- **The most important and complex view.**
- **Implementation**: Custom virtualized table using `@tanstack/react-virtual` for row virtualization, or Fluent UI's `<DataGrid>` if performance is sufficient for 10k+ rows.
- **Columns**: Name (icon + text), Date Modified, Type, Size — resizable, reorderable, sortable.
- **Column sorting**: Click header to sort asc/desc; hold Shift for multi-column sort. Sorting happens in the Zustand store (not IPC — files are already loaded).
- **Selection**: Click to select, Ctrl+Click for toggle, Shift+Click for range, rubber-band selection (mouse drag rectangle).
- **Inline rename**: Double-click (with delay to distinguish from open) or F2 renders a text input over the file name.
- **Row rendering**: Each `<FileRow>` receives data via virtualization context, not individual props — avoids re-render cascades.

#### `<IconsView />` and `<TilesView />`
- **Grid layout**: CSS Grid with `auto-fill` and `minmax()` for responsive sizing.
- **Virtualization**: `@tanstack/react-virtual` with grid mode (both row and column virtualization).
- **Icons**: `app.getFileIcon()` via IPC for actual file type icons; fall back to Fluent icons by extension.
- **Tiles view**: Adds a second line showing file type and size alongside the icon.

#### `<PreviewPane />`
- **Toggle**: Button in toolbar; state in `uiStore.previewPaneOpen`.
- **Renders**: Based on file type: `<img>` for images, `<video>` for video, syntax-highlighted `<pre>` for text (using a lightweight highlighter like `highlight.js`), and a metadata table for everything else.
- **Performance concern**: Large images/videos must be loaded lazily with size limits.

#### `<ContextMenu />`
- **Implementation**: React portal + `useContextMenu` hook that captures `onContextMenu` events.
- **Menu items vary by context**: File selected, folder selected, empty space in content area, tree node.
- **Standard items**: Open, Open With, Cut, Copy, Paste, Delete, Rename, Properties, Pin to Quick Access.
- **Native integration**: "Open in Terminal", "Show in Finder" via `shell` API.

#### `<PropertiesDialog />`
- **Renders**: Fluent UI `<Dialog>` with tabs: General, Security/Permissions.
- **General tab**: File name (editable), type, location, size (calculated recursively for folders), created/modified/accessed dates, attributes.
- **Permissions tab**: POSIX permissions display (read/write/execute for owner/group/other).
- **Folder size**: Calculated asynchronously with progress display — requires recursive `fs.stat` in main process.

#### `<StatusBar />`
- **Simple bar at the bottom**: Item count, selection summary, view mode toggle icons.
- **Renders**: Fluent UI `<Toolbar>` in compact mode with `<Text>` elements.

---

## 4. File System Interaction

### 4.1 Reading Directories

```typescript
// main/services/FileSystemService.ts
import * as fs from 'fs/promises';
import * as path from 'path';
import { app, nativeImage } from 'electron';

class FileSystemService {
  async readDirectory(dirPath: string): Promise<DirectoryContents> {
    const entries = await fs.readdir(dirPath, { withFileTypes: true });

    const fileEntries: FileEntry[] = await Promise.all(
      entries.map(async (entry) => {
        const fullPath = path.join(dirPath, entry.name);
        try {
          const stat = await fs.stat(fullPath);
          return {
            name: entry.name,
            path: fullPath,
            isDirectory: entry.isDirectory(),
            isSymlink: entry.isSymbolicLink(),
            size: stat.size,
            modified: stat.mtime,
            created: stat.birthtime,
            accessed: stat.atime,
            permissions: this.formatPermissions(stat.mode),
            isHidden: entry.name.startsWith('.'),
            extension: entry.isDirectory() ? '' : path.extname(entry.name).slice(1),
          };
        } catch {
          // Handle permission denied, broken symlinks
          return this.createErrorEntry(entry.name, fullPath);
        }
      })
    );

    return {
      path: dirPath,
      entries: fileEntries,
      totalItems: fileEntries.length,
      totalSize: fileEntries.reduce((sum, e) => sum + e.size, 0),
    };
  }
}
```

### 4.2 File Watching

```typescript
// main/services/FileWatcherService.ts
import chokidar from 'chokidar';

class FileWatcherService {
  private watchers = new Map<string, chokidar.FSWatcher>();
  private debounceTimers = new Map<string, NodeJS.Timeout>();

  watch(dirPath: string, onChange: (events: FsEvent[]) => void): void {
    if (this.watchers.has(dirPath)) return;

    const pendingEvents: FsEvent[] = [];

    const watcher = chokidar.watch(dirPath, {
      depth: 0,                    // Only watch immediate children
      ignoreInitial: true,         // Don't fire for existing files
      awaitWriteFinish: {          // Wait for writes to complete
        stabilityThreshold: 300,
        pollInterval: 100,
      },
      // Use macOS FSEvents (default on macOS) — much more efficient than polling
      useFsEvents: true,
    });

    watcher
      .on('add', (filePath) => this.enqueue(pendingEvents, 'add', filePath, dirPath, onChange))
      .on('unlink', (filePath) => this.enqueue(pendingEvents, 'remove', filePath, dirPath, onChange))
      .on('change', (filePath) => this.enqueue(pendingEvents, 'change', filePath, dirPath, onChange))
      .on('addDir', (filePath) => this.enqueue(pendingEvents, 'addDir', filePath, dirPath, onChange));

    this.watchers.set(dirPath, watcher);
  }

  // Debounce: batch events over 200ms to avoid UI thrashing
  private enqueue(pending: FsEvent[], type: string, filePath: string, dir: string, cb: Function) {
    pending.push({ type, path: filePath });
    clearTimeout(this.debounceTimers.get(dir));
    this.debounceTimers.set(dir, setTimeout(() => {
      cb([...pending]);
      pending.length = 0;
    }, 200));
  }

  unwatch(dirPath: string): void {
    this.watchers.get(dirPath)?.close();
    this.watchers.delete(dirPath);
  }
}
```

### 4.3 File Operations

```typescript
// File operations use Electron's shell API where possible for native behavior
import { shell } from 'electron';

// Delete to Trash (preferred on macOS)
await shell.trashItem(filePath);

// Open file with default app
await shell.openPath(filePath);

// Show in Finder
shell.showItemInFolder(filePath);

// Copy/Move — use fs.cp (Node 18+) for recursive copy
await fs.cp(source, destination, { recursive: true, preserveTimestamps: true });

// For move across volumes, copy + delete
await fs.cp(source, destination, { recursive: true });
await fs.rm(source, { recursive: true });
```

### 4.4 File Icons

```typescript
// Electron can extract native file icons from macOS
import { app, nativeImage } from 'electron';

async function getFileIcon(filePath: string, size: 'small' | 'normal' | 'large'): Promise<string> {
  const sizeMap = { small: 16, normal: 32, large: 48 };
  const icon = await app.getFileIcon(filePath, { size });
  return icon.toDataURL(); // Returns base64 PNG
}
```

### 4.5 Search Implementation

```typescript
// Approach 1: macOS Spotlight via mdfind (fast, indexes automatically)
import { execFile } from 'child_process';

function spotlightSearch(query: string, scope: string): Promise<string[]> {
  return new Promise((resolve, reject) => {
    execFile('mdfind', ['-onlyin', scope, query], { maxBuffer: 10 * 1024 * 1024 }, (err, stdout) => {
      if (err) reject(err);
      resolve(stdout.trim().split('\n').filter(Boolean));
    });
  });
}

// Approach 2: Manual find for non-indexed locations
function findSearch(query: string, scope: string): Promise<string[]> {
  return new Promise((resolve, reject) => {
    execFile('find', [scope, '-iname', `*${query}*`, '-maxdepth', '5'], { maxBuffer: 10 * 1024 * 1024, timeout: 10000 }, (err, stdout) => {
      if (err && err.killed) reject(new Error('Search timed out'));
      resolve((stdout || '').trim().split('\n').filter(Boolean));
    });
  });
}
```

### 4.6 macOS-Specific Considerations

| Concern | Approach |
|---|---|
| **Permissions** | macOS sandboxing requires explicit TCC (Transparency, Consent, and Control) permissions. Must handle `EPERM` gracefully and guide users to System Preferences > Privacy > Files and Folders. |
| **Hidden files** | Files starting with `.` — toggle visibility in UI settings. Also respect `chflags hidden` via `stat.flags`. |
| **Symlinks** | `fs.lstat()` to detect symlinks; `fs.readlink()` to resolve. Display with overlay icon. |
| **Extended attributes** | Use `xattr` command to read/write macOS metadata (tags, Finder comments). |
| **Volumes** | List mounted volumes from `/Volumes/` directory. Monitor mount/unmount via `child_process` watching `diskutil`. |
| **.DS_Store** | Filter out `.DS_Store` from listings by default. |
| **Resource forks** | Ignore `._` files and `__MACOSX/` directories in listings. |

---

## 5. Build System

### 5.1 Project Setup

```bash
# Initialize with electron-vite (unified Vite config for main + renderer)
npm create electron-vite@latest explorer -- --template react-ts

# Project structure created:
# ├── electron.vite.config.ts
# ├── src/
# │   ├── main/          # Electron main process
# │   ├── preload/        # Preload scripts
# │   └── renderer/       # React app
# │       ├── src/
# │       │   ├── App.tsx
# │       │   └── main.tsx
# │       └── index.html
# ├── resources/          # App icons
# └── package.json
```

### 5.2 Key Configuration

```typescript
// electron.vite.config.ts
import { defineConfig, externalizeDepsPlugin } from 'electron-vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  main: {
    plugins: [externalizeDepsPlugin()],
    build: {
      rollupOptions: {
        external: ['chokidar', 'fsevents'],
      },
    },
  },
  preload: {
    plugins: [externalizeDepsPlugin()],
  },
  renderer: {
    plugins: [react()],
    build: {
      target: 'chrome126', // Match Electron 33's Chromium
    },
  },
});
```

### 5.3 Packaging for Apple Silicon

```javascript
// electron-builder.config.js
module.exports = {
  appId: 'com.explorer.app',
  productName: 'Explorer',
  directories: { output: 'dist' },
  mac: {
    target: [
      { target: 'dmg', arch: ['arm64'] },       // Apple Silicon native
      // { target: 'dmg', arch: ['x64'] },       // Intel (optional)
      // { target: 'dmg', arch: ['universal'] },  // Universal binary (optional, larger)
    ],
    category: 'public.app-category.utilities',
    icon: 'resources/icon.icns',
    hardenedRuntime: true,
    gatekeeperAssess: false,
    entitlements: 'build/entitlements.mac.plist',
    entitlementsInherit: 'build/entitlements.mac.plist',
    darkModeSupport: true,
    // Minimum macOS 12 for Apple Silicon optimizations
    minimumSystemVersion: '12.0',
  },
  dmg: {
    sign: false,
    contents: [
      { x: 130, y: 220 },
      { x: 410, y: 220, type: 'link', path: '/Applications' },
    ],
  },
};
```

### 5.4 Code Signing & Notarization

```bash
# Required for distribution outside the Mac App Store
# 1. Apple Developer Certificate (Developer ID Application)
# 2. Notarize with Apple's service

# Environment variables needed:
# CSC_LINK — base64-encoded .p12 certificate
# CSC_KEY_PASSWORD — certificate password
# APPLE_ID — Apple ID email
# APPLE_APP_SPECIFIC_PASSWORD — App-specific password
# APPLE_TEAM_ID — Team ID

# electron-builder handles signing + notarization automatically
# when these env vars are set and `hardenedRuntime: true` is configured
```

### 5.5 Entitlements (macOS Sandbox)

```xml
<!-- build/entitlements.mac.plist -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "...">
<plist version="1.0">
<dict>
    <key>com.apple.security.cs.allow-jit</key>
    <true/>
    <key>com.apple.security.cs.allow-unsigned-executable-memory</key>
    <true/>
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>
    <key>com.apple.security.files.bookmarks.app-scope</key>
    <true/>
</dict>
</plist>
```

### 5.6 Build Scripts

```jsonc
// package.json scripts
{
  "scripts": {
    "dev": "electron-vite dev",
    "build": "electron-vite build",
    "preview": "electron-vite preview",
    "lint": "eslint src/ --ext .ts,.tsx",
    "typecheck": "tsc --noEmit",
    "test": "vitest run",
    "test:e2e": "playwright test",
    "pack": "electron-builder --dir",
    "dist": "electron-builder --mac --arm64",
    "dist:universal": "electron-builder --mac --universal",
    "postinstall": "electron-builder install-app-deps"
  }
}
```

---

## 6. Estimated Complexity

| Feature | Complexity | Effort (days) | Notes |
|---|---|---|---|
| **Project scaffolding & build** | Low | 2 | electron-vite template gets most of this done |
| **Window chrome & title bar** | Medium | 2 | Custom title bar with macOS traffic lights requires pixel-level tuning |
| **Tab support** | Medium | 4 | Each tab needs independent state (path, history, selection) |
| **Navigation pane / folder tree** | Medium | 5 | Lazy loading, expand/collapse, drag targets, pinning |
| **Details view (table)** | **High** | 8 | Virtualization, column resize/reorder/sort, multi-select, rubber-band selection |
| **Icons view** | Medium | 3 | Grid virtualization, responsive sizing |
| **Tiles view** | Medium | 3 | Similar to icons with more metadata |
| **Address bar / breadcrumbs** | **High** | 5 | Dual-mode (breadcrumb ↔ text), sibling folder dropdowns, autocomplete |
| **Toolbar / ribbon** | Medium | 3 | Fluent UI Toolbar covers most; responsive overflow is work |
| **File system read/list** | Low | 2 | Node.js fs API is straightforward |
| **File operations (CRUD)** | Medium | 4 | Copy/move across volumes, progress, undo, error handling |
| **File watching** | Medium | 3 | chokidar setup, debouncing, reconnection on volume unmount |
| **Search** | Medium | 4 | Spotlight integration + fallback find + UI (results list, highlighting) |
| **Context menus** | Medium | 3 | Multiple context types, native menu integration |
| **Drag and drop** | **High** | 5 | Within-app DnD + external DnD (Finder ↔ app), visual feedback, copy vs move |
| **Preview pane** | Medium | 4 | Multiple file types, lazy loading, size limits |
| **Properties dialog** | Medium | 3 | Recursive folder size calculation, permission display |
| **Keyboard shortcuts** | Medium | 3 | Full shortcut map, conflict resolution with macOS defaults |
| **Status bar** | Low | 1 | Simple reactive display |
| **Dual/split pane** | Medium | 4 | Independent panes with resizer; doubles state complexity |
| **Theming (Win11 look)** | Medium | 3 | Fluent UI tokens, custom CSS for exact Windows 11 match |
| **File icons** | Medium | 3 | `app.getFileIcon()` + caching + fallback icons |
| **Clipboard integration** | Medium | 2 | Copy/cut/paste files across tabs and from Finder |
| **macOS integration** | Medium | 3 | Dock menu, app menu, Spotlight, permission prompts |
| **Packaging & signing** | Medium | 2 | electron-builder config, certificates, notarization |
| **Performance optimization** | **High** | 5 | Profiling, virtualization tuning, memory leaks, IPC batching |

**Total estimated: ~85-95 developer-days (~4-5 months for 1 developer)**

---

## 7. Pros and Cons

### Pros

| # | Pro | Detail |
|---|---|---|
| 1 | **Fluent UI is a perfect fit** | Microsoft's own React component library gives authentic Windows 11 look with minimal custom CSS. No other platform (SwiftUI, Flutter, Tauri) has access to this. |
| 2 | **Fastest path to a functional prototype** | React + Electron + Fluent UI means most UI components exist out of the box. A working prototype can be ready in 2-3 weeks. |
| 3 | **Full Node.js fs access** | Direct, unrestricted file system access via `fs`, `child_process`, `chokidar`. No FFI bridges, no IPC serialization bottlenecks for file ops. |
| 4 | **Mature ecosystem** | Electron is used by VS Code, Slack, Discord, 1Password. Every problem has a Stack Overflow answer or npm package. |
| 5 | **Web dev skills transfer** | Any React developer can contribute immediately. Hiring pool is massive compared to Swift or Rust. |
| 6 | **Hot Module Replacement** | Vite HMR means UI iteration is sub-second. Much faster dev loop than SwiftUI previews or Tauri rebuilds. |
| 7 | **DevTools built in** | Chrome DevTools for debugging, profiling, network analysis, React DevTools for component inspection. |
| 8 | **Cross-platform potential** | Same codebase could be extended to Windows/Linux with minimal changes, though this plan targets macOS. |
| 9 | **Rich text/media rendering** | Chromium renders images, video, PDFs, SVGs, markdown — preview pane is trivial compared to native approaches. |
| 10 | **VS Code proves the model** | VS Code is essentially a file explorer + editor in Electron, proving this architecture scales. |

### Cons

| # | Con | Detail | Mitigation |
|---|---|---|---|
| 1 | **Memory footprint** | Electron bundles Chromium — baseline ~150-250MB RAM even for an empty window. A file explorer should use 30-50MB. | Accept the tradeoff or use aggressive renderer recycling. No real mitigation — this is Electron's fundamental cost. |
| 2 | **App size** | Distributable is 150-250MB (Chromium + Node.js). SwiftUI would be <10MB. | Universal binary is 350MB+. ARM64-only cuts to ~180MB. Still 10x larger than native. |
| 3 | **Not a native macOS app** | Will never feel perfectly native on macOS — scrolling physics, text rendering, menu behavior, window management all differ subtly. | Since we're deliberately mimicking *Windows* UI, this is less of a concern. Users will expect it to look foreign. |
| 4 | **Startup time** | Cold start is 2-4 seconds (Chromium init). Native Swift app starts in <0.5s. | Use `backgroundThrottling: false`, preload critical data, show splash screen. |
| 5 | **Battery drain** | Chromium's GPU compositing and JS engine consume more power than native AppKit rendering. | Reduce animation, disable GPU acceleration for static views, throttle file watchers when on battery. |
| 6 | **macOS integration gaps** | No native drag-and-drop with Finder (requires workarounds), no Quick Look (spacebar preview), no Spotlight integration for indexed results, no Share menu. | Implement custom equivalents. `shell.showItemInFolder()` for Finder integration. Quick Look can be invoked via `child_process`. |
| 7 | **Security surface** | Chromium + Node.js is a large attack surface. Must be careful with `nodeIntegration`, `contextIsolation`, CSP. | Follow Electron security checklist rigorously. Use `contextBridge`, disable `nodeIntegration`, set strict CSP. |
| 8 | **No App Store distribution** | Apple's Mac App Store requires full sandbox, which conflicts with a file explorer's need for broad file access. | Distribute via DMG with notarization. Most file explorers (Path Finder, Forklift) do this. |
| 9 | **IPC overhead for file ops** | Every file operation crosses the IPC bridge (serialized JSON). Listing a directory with 10,000 files means serializing 10,000 objects. | Batch and paginate large directories. Stream results via IPC events instead of single invoke. |
| 10 | **Fluent UI bundle size** | Fluent UI v9 tree-shakes well, but importing many components can add 500KB-1MB to renderer bundle. | Import only used components. Monitor bundle with `rollup-plugin-visualizer`. |

---

## 8. Apple Silicon Optimization

### 8.1 Native ARM64 Build

```bash
# Electron 33+ has native Apple Silicon builds
# electron-builder produces arm64 .app natively
npm run dist  # Produces arm64 DMG

# To verify architecture of the built app:
file dist/mac-arm64/Explorer.app/Contents/MacOS/Explorer
# Expected: Mach-O 64-bit executable arm64
```

### 8.2 Performance Considerations

| Area | Optimization | Impact |
|---|---|---|
| **Electron binary** | Use `arm64` target only (not universal) to avoid Rosetta 2 overhead | 2x faster startup vs x64 under Rosetta |
| **Native modules** | Ensure `chokidar`, `fsevents` compile for arm64 via `electron-rebuild` or `@electron/rebuild` | `fsevents` is macOS-native and critical for watch performance |
| **V8 JIT** | V8 on ARM64 has excellent JIT performance; no special action needed | Close to x64 performance for JS execution |
| **Memory** | ARM64 Electron uses ~10-15% less memory than x64 Rosetta due to native page sizes | ~200MB vs ~230MB baseline |
| **GPU / Metal** | Chromium on macOS uses Metal for compositing by default on M-series chips | Hardware-accelerated CSS animations, smooth scrolling |
| **File I/O** | M-series SSD controller is extremely fast (7GB/s); directory listing perf is I/O bound, not CPU bound | `fs.readdir` + `Promise.all(stat)` for 10,000 files completes in <200ms on M1+ |
| **Large directories** | For dirs with 50,000+ files, stream results in batches of 500 via IPC events to avoid blocking the renderer | Keeps UI responsive during large directory loads |

### 8.3 Memory Usage Targets

| Scenario | Target | Notes |
|---|---|---|
| Idle (1 tab, small directory) | <200MB | Chromium baseline is unavoidable |
| Active (3 tabs, typical usage) | <350MB | Watch for leaked watchers/listeners |
| Heavy (10 tabs, 10k+ file dirs) | <600MB | Virtualization prevents DOM bloat; IPC data should be GC'd |

### 8.4 Profiling Strategy

```typescript
// Use Electron's built-in performance hooks
const { performance } = require('perf_hooks');

// Measure directory listing time
performance.mark('readdir-start');
const entries = await fs.readdir(path, { withFileTypes: true });
performance.mark('readdir-end');
performance.measure('readdir', 'readdir-start', 'readdir-end');

// Monitor renderer memory from main process
const metrics = await win.webContents.getProcessMemoryInfo();
console.log(`Renderer memory: ${metrics.private / 1024}MB`);

// Use Chrome DevTools Performance tab for renderer profiling
// Accessible via View > Toggle Developer Tools in development
```

---

## 9. Timeline Estimate

### Phase 1: Foundation (Weeks 1-3)
**Goal: Window opens, folders list, basic navigation works.**

- [ ] Project scaffolding with electron-vite + React + TypeScript
- [ ] Fluent UI integration with Windows 11 theme tokens
- [ ] Custom title bar with macOS traffic light integration
- [ ] Main process FileSystemService (readDirectory, getFileInfo)
- [ ] IPC bridge with contextBridge (typed API)
- [ ] Basic layout: NavigationPane (static) + ContentArea (details view)
- [ ] Details view with name/size/date/type columns
- [ ] Address bar (text input mode only, no breadcrumbs yet)
- [ ] Back/Forward navigation with history stack
- [ ] Status bar with item count

**Deliverable**: Can browse folders, see files in a table, navigate forward/back.

### Phase 2: Core File Management (Weeks 4-6)
**Goal: Full file operations, proper tree view, keyboard navigation.**

- [ ] Folder tree in NavigationPane (lazy-loaded with react-arborist)
- [ ] Quick Access section with pinnable favorites
- [ ] Volumes/drives section
- [ ] File operations: create folder, delete (to Trash), rename (inline), copy, move
- [ ] Clipboard: Cut/Copy/Paste with keyboard shortcuts
- [ ] File watching with chokidar (auto-refresh on changes)
- [ ] Keyboard shortcuts (Cmd+C, Cmd+V, Cmd+Delete, Enter to open, etc.)
- [ ] Toolbar with Fluent UI command buttons
- [ ] Column sorting (click header) and resizing
- [ ] Multi-select (Cmd+Click, Shift+Click)

**Deliverable**: Functional file manager with core operations.

### Phase 3: Advanced UI (Weeks 7-9)
**Goal: Address bar breadcrumbs, tabs, multiple view modes, context menus.**

- [ ] Address bar breadcrumb mode with clickable segments
- [ ] Sibling folder dropdown on chevrons
- [ ] Path autocomplete in text input mode
- [ ] Tab support (add, close, reorder, independent state per tab)
- [ ] Icons view (grid layout, virtualized)
- [ ] Tiles view
- [ ] Context menus (right-click) with context-appropriate items
- [ ] File type icons (via app.getFileIcon + caching)
- [ ] Hidden files toggle
- [ ] Rubber-band selection in content area

**Deliverable**: Visually complete file explorer with tabs and multiple views.

### Phase 4: Search, Preview, Polish (Weeks 10-12)
**Goal: Search works, preview pane, drag-and-drop, properties dialog.**

- [ ] Search: Spotlight integration (`mdfind`) + fallback `find`
- [ ] Search UI: input, results list, highlighting
- [ ] Preview pane (toggle): images, text, video, metadata
- [ ] Drag and drop within app (move/copy files)
- [ ] Drag and drop from/to Finder
- [ ] Properties dialog (General tab: size, dates, permissions)
- [ ] Dual/split pane view
- [ ] Progress dialogs for long operations (copy/move/delete)
- [ ] Undo support for file operations (at least delete → restore from Trash)

**Deliverable**: Feature-complete file explorer.

### Phase 5: Optimization & Distribution (Weeks 13-15)
**Goal: Fast, stable, distributable.**

- [ ] Performance profiling (startup time, large directory rendering, memory)
- [ ] Virtualization tuning (handle 50,000+ file directories)
- [ ] IPC batching and streaming for large data
- [ ] Memory leak hunting (detach watchers, remove listeners)
- [ ] Error handling: permission denied, missing files, broken symlinks, full disk
- [ ] Apple Silicon native build verification
- [ ] DMG packaging with electron-builder
- [ ] Code signing with Developer ID certificate
- [ ] Notarization with Apple
- [ ] Automated build pipeline (GitHub Actions)
- [ ] End-to-end tests with Playwright

**Deliverable**: Production-ready, signed, notarized DMG for Apple Silicon.

### Summary Timeline

| Phase | Duration | Cumulative |
|---|---|---|
| Phase 1: Foundation | 3 weeks | Week 3 |
| Phase 2: Core File Management | 3 weeks | Week 6 |
| Phase 3: Advanced UI | 3 weeks | Week 9 |
| Phase 4: Search, Preview, Polish | 3 weeks | Week 12 |
| Phase 5: Optimization & Distribution | 3 weeks | Week 15 |
| **Total** | **15 weeks** | **~4 months** |

*Assumes 1 full-time experienced developer. With 2 developers, phases 2-4 can overlap significantly (front-end/back-end split), reducing to ~10 weeks.*

---

## 10. Risks and Challenges

### Critical Risks

| # | Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|---|
| 1 | **Details view performance with large directories** | High | High | Directories with 50,000+ files will expose virtualization limits, IPC serialization bottlenecks, and sorting performance issues. *Mitigation*: Paginate at the IPC level (send 500 items at a time), sort in a Web Worker, use `requestIdleCallback` for non-critical renders. |
| 2 | **Memory bloat in multi-tab scenarios** | High | Medium | Each tab holds a full directory listing in memory. 10 tabs × 10,000 files × ~500 bytes/entry = ~50MB in state alone, plus DOM/React overhead. *Mitigation*: Evict background tab data after inactivity; re-fetch on tab switch. |
| 3 | **macOS permission prompts break UX** | High | Medium | First time accessing Documents, Desktop, Downloads, or external drives, macOS shows a TCC consent dialog. If denied, the app silently fails. *Mitigation*: Detect `EPERM`, show a friendly "Grant access in System Preferences" dialog with a direct link. |
| 4 | **Drag-and-drop between app and Finder** | Medium | High | Electron's DnD API has limited interop with macOS Finder. Dragging files *from* the app to Finder requires `webContents.startDrag()` with icon, which is poorly documented and buggy. *Mitigation*: Prototype this early (Week 2). If it doesn't work reliably, fall back to copy-to-clipboard. |
| 5 | **Address bar sibling-folder dropdown** | Medium | Medium | The Windows File Explorer chevron shows sibling directories — this requires fetching the parent directory's contents on hover/click, rendering a dropdown, and handling keyboard navigation. No existing React component does this. *Mitigation*: Build a custom `<BreadcrumbDropdown>` early; scope for complexity. |

### Moderate Risks

| # | Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|---|
| 6 | **Electron security model vs file access** | Medium | Medium | A file explorer needs broad file access, which conflicts with Electron's security recommendations (minimal permissions). `contextIsolation` + `contextBridge` help, but the preload API surface is large. *Mitigation*: Validate all paths in main process handlers; reject paths outside expected scopes. |
| 7 | **Fluent UI theming doesn't perfectly match Windows 11** | Medium | Low | Fluent UI React v9 is close but not pixel-perfect to Windows 11 (e.g., Mica material, acrylic blur). *Mitigation*: Accept 90% fidelity. Use CSS `backdrop-filter: blur()` for some effects. True Mica is impossible in Chromium. |
| 8 | **chokidar/FSEvents reliability** | Low | Medium | chokidar can miss events on macOS, especially on network volumes or external drives. *Mitigation*: Add a manual refresh button; periodically re-scan active directory (every 30s) as a fallback. |
| 9 | **Electron version churn** | Low | Medium | Electron releases every 8 weeks with breaking changes. Chromium updates can change behavior. *Mitigation*: Pin Electron version; update quarterly with testing. |
| 10 | **App size concerns for distribution** | Low | Low | 180MB DMG for a file explorer feels excessive to users accustomed to <10MB native apps. *Mitigation*: ARM64-only (not universal) saves ~80MB. Use `asar` for renderer bundling. Communicate the tradeoff. |

### Technical Debt Risks

| # | Risk | Detail |
|---|---|---|
| 11 | **IPC channel proliferation** | As features grow, the IPC surface area expands. Without discipline, this becomes an untyped mess. *Mitigation*: Use the shared `IpcChannels` type map from day 1. Consider `electron-trpc` for type-safe IPC if complexity grows. |
| 12 | **State management complexity** | Multiple tabs × multiple panes × clipboard × search × preferences = complex state graph. *Mitigation*: Separate Zustand stores by domain. Avoid derived state; compute in selectors. |
| 13 | **Testing file operations** | Unit testing code that creates/deletes real files is fragile and slow. *Mitigation*: Use a temp directory fixture (`os.tmpdir()`) for integration tests. Mock `fs` in unit tests. |

---

## Appendix A: Comparison Quick Reference

This plan is designed to be compared against SwiftUI, Tauri, and Flutter approaches. Key differentiators for Electron:

| Dimension | Electron | vs SwiftUI | vs Tauri | vs Flutter |
|---|---|---|---|---|
| **Windows 11 fidelity** | ★★★★★ (Fluent UI) | ★★ (custom CSS) | ★★★★ (web UI) | ★★★ (custom widgets) |
| **macOS native feel** | ★★ | ★★★★★ | ★★★ | ★★ |
| **Memory usage** | ★★ (200MB+) | ★★★★★ (30MB) | ★★★★ (50MB) | ★★★ (80MB) |
| **App size** | ★ (180MB) | ★★★★★ (5MB) | ★★★★ (15MB) | ★★★ (40MB) |
| **Dev speed** | ★★★★★ | ★★★ | ★★★★ | ★★★★ |
| **Ecosystem/libs** | ★★★★★ | ★★★ | ★★★★ | ★★★★ |
| **File system access** | ★★★★★ | ★★★★★ | ★★★★ (Rust) | ★★★ (platform channels) |
| **Startup time** | ★★ (2-4s) | ★★★★★ (<0.5s) | ★★★★ (<1s) | ★★★ (1-2s) |
| **Battery efficiency** | ★★ | ★★★★★ | ★★★★ | ★★★ |

## Appendix B: Recommended Folder Structure (Full)

```
explorer/
├── package.json
├── electron.vite.config.ts
├── tsconfig.json
├── tsconfig.node.json
├── tsconfig.web.json
├── electron-builder.config.js
├── .eslintrc.cjs
├── .prettierrc
├── build/
│   ├── entitlements.mac.plist
│   └── notarize.js
├── resources/
│   ├── icon.icns                         # macOS app icon
│   ├── icon.png                          # 1024x1024 source
│   └── file-type-icons/                  # Fallback icons by extension
├── src/
│   ├── main/
│   │   ├── index.ts                      # App entry point
│   │   ├── ipc/
│   │   │   ├── registerHandlers.ts
│   │   │   ├── fileSystemHandlers.ts
│   │   │   ├── searchHandlers.ts
│   │   │   ├── shellHandlers.ts
│   │   │   ├── clipboardHandlers.ts
│   │   │   └── dialogHandlers.ts
│   │   ├── services/
│   │   │   ├── FileSystemService.ts
│   │   │   ├── FileWatcherService.ts
│   │   │   ├── SearchService.ts
│   │   │   ├── ThumbnailService.ts
│   │   │   ├── TrashService.ts
│   │   │   └── ClipboardService.ts
│   │   ├── windows/
│   │   │   ├── WindowManager.ts
│   │   │   └── createMainWindow.ts
│   │   └── menu/
│   │       ├── applicationMenu.ts
│   │       └── contextMenu.ts
│   ├── preload/
│   │   └── index.ts
│   ├── renderer/
│   │   ├── index.html
│   │   ├── src/
│   │   │   ├── main.tsx                  # React entry
│   │   │   ├── App.tsx                   # Root component
│   │   │   ├── components/
│   │   │   │   ├── layout/
│   │   │   │   │   ├── TitleBar.tsx
│   │   │   │   │   ├── MainLayout.tsx
│   │   │   │   │   └── ResizablePanel.tsx
│   │   │   │   ├── navigation/
│   │   │   │   │   ├── TabBar.tsx
│   │   │   │   │   ├── Tab.tsx
│   │   │   │   │   ├── AddressBar.tsx
│   │   │   │   │   ├── BreadcrumbSegment.tsx
│   │   │   │   │   ├── NavigationButtons.tsx
│   │   │   │   │   └── SearchBox.tsx
│   │   │   │   ├── sidebar/
│   │   │   │   │   ├── NavigationPane.tsx
│   │   │   │   │   ├── QuickAccess.tsx
│   │   │   │   │   ├── FolderTree.tsx
│   │   │   │   │   ├── TreeNode.tsx
│   │   │   │   │   └── DrivesSection.tsx
│   │   │   │   ├── content/
│   │   │   │   │   ├── ContentArea.tsx
│   │   │   │   │   ├── DetailsView.tsx
│   │   │   │   │   ├── ColumnHeader.tsx
│   │   │   │   │   ├── FileRow.tsx
│   │   │   │   │   ├── IconsView.tsx
│   │   │   │   │   ├── FileIcon.tsx
│   │   │   │   │   ├── TilesView.tsx
│   │   │   │   │   ├── FileTile.tsx
│   │   │   │   │   └── EmptyState.tsx
│   │   │   │   ├── preview/
│   │   │   │   │   ├── PreviewPane.tsx
│   │   │   │   │   ├── ImagePreview.tsx
│   │   │   │   │   ├── TextPreview.tsx
│   │   │   │   │   ├── VideoPreview.tsx
│   │   │   │   │   └── MetadataPreview.tsx
│   │   │   │   ├── toolbar/
│   │   │   │   │   └── Toolbar.tsx
│   │   │   │   ├── statusbar/
│   │   │   │   │   ├── StatusBar.tsx
│   │   │   │   │   ├── ItemCount.tsx
│   │   │   │   │   ├── SelectionInfo.tsx
│   │   │   │   │   └── ViewModeToggle.tsx
│   │   │   │   ├── dialogs/
│   │   │   │   │   ├── PropertiesDialog.tsx
│   │   │   │   │   ├── ConfirmDialog.tsx
│   │   │   │   │   └── ProgressDialog.tsx
│   │   │   │   └── shared/
│   │   │   │       ├── ContextMenu.tsx
│   │   │   │       ├── RenameInput.tsx
│   │   │   │       ├── DragOverlay.tsx
│   │   │   │       └── FileIconResolver.tsx
│   │   │   ├── stores/
│   │   │   │   ├── fileSystemStore.ts
│   │   │   │   ├── navigationStore.ts
│   │   │   │   ├── uiStore.ts
│   │   │   │   ├── clipboardStore.ts
│   │   │   │   └── searchStore.ts
│   │   │   ├── hooks/
│   │   │   │   ├── useFileOperations.ts
│   │   │   │   ├── useKeyboardShortcuts.ts
│   │   │   │   ├── useContextMenu.ts
│   │   │   │   ├── useDragAndDrop.ts
│   │   │   │   ├── useFileWatcher.ts
│   │   │   │   └── useSelection.ts
│   │   │   ├── utils/
│   │   │   │   ├── fileSize.ts           # Format bytes → "1.2 MB"
│   │   │   │   ├── dateFormat.ts         # Format dates
│   │   │   │   ├── pathUtils.ts          # Path manipulation
│   │   │   │   └── sortUtils.ts          # Column sorting logic
│   │   │   ├── themes/
│   │   │   │   ├── windows11Light.ts     # Fluent UI theme tokens
│   │   │   │   └── windows11Dark.ts
│   │   │   └── types/
│   │   │       └── electron.d.ts         # Window.electronAPI types
│   │   └── styles/
│   │       ├── global.css
│   │       ├── titlebar.css
│   │       └── variables.css
│   └── shared/
│       ├── types/
│       │   ├── fileSystem.ts
│       │   ├── ipc.ts
│       │   └── ui.ts
│       ├── constants.ts
│       └── utils.ts
├── tests/
│   ├── unit/
│   │   ├── services/
│   │   │   └── FileSystemService.test.ts
│   │   ├── stores/
│   │   │   └── fileSystemStore.test.ts
│   │   └── utils/
│   │       └── fileSize.test.ts
│   ├── integration/
│   │   └── ipc.test.ts
│   └── e2e/
│       ├── navigation.spec.ts
│       ├── fileOperations.spec.ts
│       └── playwright.config.ts
└── .github/
    └── workflows/
        └── build.yml                     # CI: lint, test, build, sign
```

---

*Plan prepared for comparison against SwiftUI, Tauri, and Flutter implementation approaches.*
