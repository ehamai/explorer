# Explorer Sources

Entry point and top-level app configuration.

## ExplorerApp (ExplorerApp.swift)

The `@main` entry point for the application.

```
┌──────────────────────────────────────────────────────────┐
│                    ExplorerApp                            │
│                                                          │
│  Creates & owns:                                         │
│    • SplitScreenManager    (global split-screen state)   │
│    • SidebarViewModel      (favorites, volumes)          │
│    • ClipboardManager      (cut/copy/paste)              │
│    • FavoritesManager      (persistent bookmarks)        │
│                                                          │
│  Injects via .environment() into WindowGroup → MainView  │
│                                                          │
│  Defines CommandGroups for:                               │
│    • File menu    (New Tab, New Folder, Close)           │
│    • Edit menu    (Cut, Copy, Paste, Select All)         │
│    • View menu    (List/Icon mode, Hidden files, Split)  │
│    • Navigate menu (Back, Forward, Enclosing Folder)     │
│    • Sidebar menu  (Inspector, Trash)                    │
└──────────────────────────────────────────────────────────┘
```

**Responsibilities:**
- Creates and injects all global state objects via `.environment()`
- Configures `WindowGroup` with `MainView` as root
- Defines keyboard shortcuts via `CommandGroup` entries
- Implements dual-mode keyboard handling (text editing vs file operations)

**Dual-Mode Pattern:** Cut/Copy/Paste/SelectAll check if a text field is focused. If so, they forward to the system text handling. Otherwise, they operate on file selections.
