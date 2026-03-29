# View Components

Reusable view components used across the app.

## FileIconView (FileIconView.swift)

Reusable file icon display component.

**Props:** `FileItem`, `CGFloat` size
**Behavior:** Displays NSImage icon with aspect-fit scaling. Stateless — no environment dependencies.

## InspectorView (InspectorView.swift)

Right sidebar panel showing detailed file properties. Toggled via Cmd+I or context menu → Properties.

```
With Selection:                    No Selection:
┌────────────────────┐             ┌────────────────────┐
│      ┌──────┐      │             │                    │
│      │  📄  │      │             │                    │
│      │ 64pt │      │             │       🔍           │
│      └──────┘      │             │   No Selection     │
│    README.md       │             │                    │
│    Markdown File   │             │                    │
├────────────────────┤             └────────────────────┘
│ INFORMATION        │
│  Kind:  Markdown   │
│  Size:  4 KB       │
│  Modified: 5m ago  │
│  Created:  Mar 1   │
│  Path: /Users/...  │
├────────────────────┤
│ DETAILS            │
│  Hidden:   No      │
│  Perms:    644     │
│  Owner:    ehamai  │
└────────────────────┘
```

**Sections (when item selected):**
- **Header:** 64pt icon, file name (2 lines), kind
- **Information:** Kind, Size (or folder item count), Modified date, Created date, Full path (selectable)
- **Details:** Hidden status, POSIX permissions (octal), Owner

**Empty State:** Magnifying glass icon + "No Selection"

**Environment:** `DirectoryViewModel` — reads `inspectedItem` computed property + helper methods (`folderSize`, `createdDate`, `posixPermissions`, `fileOwner`)
