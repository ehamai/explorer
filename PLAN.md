# Explorer — macOS File Explorer: Plan Comparison & Recommendation

## Problem Statement

macOS Finder lacks two key Windows Explorer conveniences:
1. **No "Up" button** — no one-click way to navigate to the parent folder
2. **No Cut/Paste to move files** — Finder only supports Copy/Paste; moving requires drag-and-drop

We want a lightweight, performance-optimized macOS file explorer with a Finder-like look but Windows-style navigation and file-move gestures, plus a customizable favorites sidebar and multiple view modes with sorting.

---

## Three Competing Plans

| | **Plan A: SwiftUI** | **Plan B: Tauri v2** | **Plan C: AppKit** |
|---|---|---|---|
| **File** | `plan-A-swiftui.md` | `plan-B-tauri.md` | `plan-C-appkit.md` |
| **Language** | Swift | Rust + TypeScript | Swift |
| **UI Framework** | SwiftUI + AppKit bridges | React (in WKWebView) | AppKit (pure) |
| **Binary Size** | ~5–10 MB | ~8–15 MB | ~5 MB |
| **Memory** | ~30–50 MB | ~30–60 MB | ~20–40 MB (lowest) |
| **100k File Perf** | ⭐⭐⭐⭐ (via NSTableView bridge) | ⭐⭐⭐½ (TanStack Virtual + Rust) | ⭐⭐⭐⭐⭐ (native cell recycling) |
| **Native Fidelity** | ⭐⭐⭐⭐ (vibrancy, dark mode, system icons) | ⭐⭐⭐ (styled HTML, not truly native) | ⭐⭐⭐⭐⭐ (identical to Finder) |
| **Dev Velocity** | ⭐⭐⭐⭐⭐ (declarative, fast iteration) | ⭐⭐⭐⭐ (rich web ecosystem, HMR) | ⭐⭐⭐ (more boilerplate) |
| **Cross-Platform** | ❌ macOS only | ✅ Linux/Windows later | ❌ macOS only |
| **Column View** | ⚠️ Custom (no native SwiftUI) | ⚠️ Custom HTML | ✅ NSBrowser (native) |
| **Min macOS** | 14.0 (Sonoma) | 13.0 (Ventura) | 13.0 (Ventura) |
| **Startup Time** | <0.5s | ~1–2s (WebView init) | <0.3s |
| **Learning Curve** | Moderate (Swift + SwiftUI) | High (Rust + React + Tauri) | Moderate-High (AppKit patterns) |
| **App Store** | ✅ Sandboxable | ⚠️ Possible but harder | ✅ Sandboxable |
| **Debugging** | Single runtime (Xcode) | Two runtimes (DevTools + lldb) | Single runtime (Xcode) |

---

## Recommendation: **Plan A (SwiftUI + AppKit hybrid)**

### Why Plan A wins

1. **Best balance of performance and dev speed** — SwiftUI's declarative model means faster iteration, while AppKit bridges (`NSViewRepresentable`) give us NSTableView-level performance for the 100k+ file case. We get ~90% of AppKit's performance with ~50% of the code.

2. **Authentically native** — SwiftUI views automatically get vibrancy, dark mode, system fonts, and macOS idioms. No CSS tricks needed.

3. **Modern architecture** — Swift concurrency (`async/await`, `AsyncStream`, actors) provides clean, safe async file enumeration without callback hell or manual GCD.

4. **Single language, single runtime** — All Swift, debugged in Xcode, no IPC boundary, no serialization overhead.

5. **Pragmatic hybrid** — Where SwiftUI falls short (NSTableView for massive lists, NSBrowser for column view), we bridge to AppKit. This is a well-established pattern used by Apple's own apps.

### When to pick Plan C (AppKit) instead

If you find that SwiftUI's AppKit bridges become friction (too many `NSViewRepresentable` wrappers), Plan C is the fallback. It's more code but gives absolute control. Consider switching if >40% of the UI ends up as AppKit bridges.

### When to pick Plan B (Tauri) instead

Only if cross-platform (Linux/Windows) is a future goal. The native fidelity and performance trade-offs are real.

---

## ASCII Mockup — Recommended Design

```
┌──────────────────────────────────────────────────────────────────────────────┐
│ ● ● ●                        Explorer — Documents                          │
├──────────────────────────────────────────────────────────────────────────────┤
│ TOOLBAR                                                                     │
│ [◀][▶][↑ Up]  │ 🏠 > Users > ehamai > Documents       │ [≡][⊞][⫏] │ 🔍    │
│  Back Fwd Up  │        Breadcrumb Path Bar             │ Lst Ico Col│Search │
├─────────────┬────────────────────────────────────────────────────────────────┤
│  FAVORITES  │  CONTENT AREA (List View)                                     │
│             │                                                               │
│  ▾ Pinned   │  Name ▲           Date Modified     Size       Kind           │
│    📁 Work  │  ─────────────────────────────────────────────────────────     │
│    📁 Music │  📁 Projects     2024-12-01 10:30   --         Folder         │
│    📁 dev   │  📁 Archive      2024-11-15 09:00   --         Folder         │
│    📁 Photos│  📄 readme.md    2024-12-10 14:22   4 KB       Markdown       │
│             │  📄 report.pdf   2024-12-09 11:45   2.1 MB     PDF Document   │
│  ▾ System   │  📄 notes.txt    2024-12-08 16:30   512 B      Plain Text     │
│    🖥 Desktop│  ░░ budget.xlsx  2024-12-07 09:15   156 KB     Spreadsheet ░░ │
│    📥 Downlds│  📄 photo.jpg    2024-12-06 20:00   3.4 MB     JPEG Image    │
│    🏠 Home  │  📄 script.sh    2024-12-05 08:45   1.2 KB     Shell Script   │
│             │                 ↑ dimmed = item was "cut" (⌘X)               │
│  ▾ Volumes  │                                                               │
│    💻 Mac HD│                                                               │
│             │                                                               │
│  ─────────  │                                                               │
│  [+ Pin]    │                                                               │
├─────────────┴────────────────────────────────────────────────────────────────┤
│ STATUS BAR                                                                   │
│  8 items  •  1 selected  •  42.5 GB available                               │
└──────────────────────────────────────────────────────────────────────────────┘


ICON / GRID VIEW (⌘2):
┌────────────────────────────────────────────────────────────────┐
│                                                                │
│   ┌──────┐   ┌──────┐   ┌──────┐   ┌──────┐   ┌──────┐       │
│   │ 📁   │   │ 📁   │   │ 📄   │   │ 📄   │   │ 📄   │       │
│   │      │   │      │   │      │   │      │   │      │       │
│   │Projec│   │Archiv│   │readme│   │report│   │notes │       │
│   └──────┘   └──────┘   └──────┘   └──────┘   └──────┘       │
│                                                                │
│   ┌──────┐   ┌──────┐   ┌──────┐                               │
│   │ 📄   │   │ 🖼   │   │ 📄   │                               │
│   │      │   │      │   │      │                               │
│   │budget│   │photo │   │script│                               │
│   └──────┘   └──────┘   └──────┘                               │
│                                                                │
└────────────────────────────────────────────────────────────────┘


COLUMN VIEW (⌘3):
┌───────────────┬───────────────┬───────────────┬──────────────────┐
│  Users        │  ehamai       │  Documents    │  ▌ Preview ▌     │
│ ─────────     │ ─────────     │ ─────────     │                  │
│  admin        │ ▸ Desktop     │ ▸ Projects    │  report.pdf      │
│ ▸ ehamai    ◀ │ ▸ Documents ◀ │   readme.md   │  ───────────     │
│  guest        │ ▸ Downloads   │   report.pdf◀ │  PDF Document    │
│               │ ▸ Music       │   notes.txt   │  2.1 MB          │
│               │   .zshrc      │   budget.xlsx │  Modified: Dec 9 │
└───────────────┴───────────────┴───────────────┴──────────────────┘


RIGHT-CLICK CONTEXT MENU:
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
│  Pin to Favorites │
│  Get Info    ⌘I   │
│  Quick Look  ␣    │
└──────────────────┘
```

---

## Key Keyboard Shortcuts

| Action | Shortcut |
|--------|----------|
| Go to Parent (Up) | ⌘↑ |
| Back / Forward | ⌘[ / ⌘] |
| Cut | ⌘X |
| Copy | ⌘C |
| Paste (move if cut, copy if copied) | ⌘V |
| Move to Trash | ⌘⌫ |
| Rename | Enter |
| List / Icon / Column view | ⌘1 / ⌘2 / ⌘3 |
| New Folder | ⇧⌘N |
| Toggle Hidden Files | ⇧⌘. |
| Quick Look | Space |
| Search / Filter | ⌘F |

---

## Implementation Todos

### Phase 1: Foundation
- **project-setup** — Create Xcode project, configure Swift Package Manager, set up App Sandbox entitlements
- **app-shell** — Main window with NSSplitView (sidebar + content), NSToolbar, status bar
- **file-model** — FileItem struct, FileSystemService actor for async directory enumeration

### Phase 2: Core Navigation
- **navigation-vm** — NavigationViewModel with back/forward/up stack, breadcrumb path bar
- **up-button** — Toolbar up button (⌘↑) that always navigates to parent directory
- **directory-listing** — List view with NSTableView bridge for performance, sortable columns

### Phase 3: File Operations
- **clipboard-manager** — ClipboardManager with cut/copy/paste state machine (⌘X/⌘C/⌘V)
- **file-ops** — Move, copy, delete, rename operations with undo support
- **context-menu** — Right-click menu with Cut/Copy/Paste/Rename/Trash/Pin to Favorites

### Phase 4: Sidebar & Views
- **favorites-sidebar** — Pinned locations with drag-to-add, right-click-to-remove, persistence via security-scoped bookmarks
- **icon-view** — Grid/icon view mode using LazyVGrid or NSCollectionView
- **column-view** — Miller column view (NSBrowser bridge or custom)
- **sorting** — Column header sorting by name/date/size/kind, sort direction toggle

### Phase 5: Polish
- **performance** — 100k+ file optimization: batched async enumeration, thumbnail caching, FSEvents watcher
- **visual-polish** — Vibrancy materials, dark mode, system icons, window state persistence
- **testing** — Unit tests for ViewModels/Services, UI tests for key flows
