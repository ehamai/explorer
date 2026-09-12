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
- **Details:** Hidden status, POSIX permissions (octal), Owner, iCloud status (with ICloudStatusBadge when inside iCloud Drive)

**Empty State:** Magnifying glass icon + "No Selection"

**Environment:** `DirectoryViewModel` — reads `inspectedItem` computed property + helper methods (`folderSize`, `createdDate`, `posixPermissions`, `fileOwner`)

## ICloudStatusBadge (ICloudStatusBadge.swift)

Compact badge view showing a file's iCloud sync status using an SF Symbol.

**Props:** `ICloudStatus`
**Behavior:**
- Displays an SF Symbol corresponding to the status (e.g., cloud, cloud.fill, arrow.down.circle)
- Color-coded: blue for synced, gray for cloud-only, orange for downloading/uploading, red for error
- Tooltip shows the status label on hover
- Hidden for `.local` status (no badge displayed)

**Stateless** — no environment dependencies. Used by FileListView, IconGridView, MosaicView, and InspectorView.

## MosaicThumbnailView (MosaicThumbnailView.swift)

Cell view for the mosaic gallery layout. Renders differently based on whether the file supports thumbnails.

**Props:** `MosaicLayoutItem`, `FileItem`, `isSelected: Bool`, `isCut: Bool`, `isDropTarget: Bool` (default `false`; accent fill + border while a drag hovers a folder cell)

**Thumbnail Cell** (images, videos, PDFs — `hasThumbnail == true`):
- Full-bleed thumbnail loaded asynchronously via ThumbnailCache/ThumbnailLoader
- Placeholder: system file icon while thumbnail loads
- Bottom-left: last modified date shown only for non-media files (PDFs); hidden for images/videos
- Bottom-right badges: play.circle.fill for videos, doc.text.fill for PDFs
- Background: black for images/videos, controlBackgroundColor for PDFs

**Non-Thumbnail Cell** (folders, other files — `hasThumbnail == false`):
- Centered FileIconView (48pt max) + filename + date/item count
- Bordered card style with separator stroke

**Drag:** Handled by the parent `MosaicView`, which overlays a `FileDragSource` (Helpers) on each cell. Dragging a selected item starts a native multi-item drag of all selected files (stacked images + count badge).

**Environment:** `ThumbnailCache`, `ThumbnailLoader`
