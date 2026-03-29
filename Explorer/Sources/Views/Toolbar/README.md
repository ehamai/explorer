# Toolbar Views

Views that appear in the toolbar area of each pane.

## PathBarView (PathBarView.swift)

Breadcrumb navigation with editable text mode.

```
Breadcrumb Mode:
┌──────────────────────────────────────────────────────┐
│  📁 / ▸ 📁 Users ▸ 📁 ehamai ▸ 📁 Documents        │  ← Click any segment to navigate
└──────────────────────────────────────────────────────┘     Drop files on segment to move

Edit Mode (click to activate):
┌──────────────────────────────────────────────────────┐
│  /Users/ehamai/Documents                          ⏎  │  ← Monospaced, ~ expansion
└──────────────────────────────────────────────────────┘

Invalid Path:
┌──────────────────────────────────────────────────────┐
│  /does/not/exist                                     │  ← Red border (1s timeout)
└══════════════════════════════════════════════════════─┘
```

**Two Modes:**
1. **Breadcrumb Mode:** Horizontal scroll of clickable path components with chevron separators and folder icons. Each component is a drop target for file moves.
2. **Edit Mode:** Monospaced text field with path validation. Supports `~` expansion for home directory. Shows red border on invalid path (1s timeout). Escape cancels.

**Environment:** `NavigationViewModel`, `SplitScreenManager`
**Local State:** `isEditing`, `editText`, `showError`, `dropTargetURL`
**Focus:** `@FocusState textFieldFocused`

## TabBarView (TabBarView.swift)

Tab management UI shown when multiple tabs exist.

```
┌─────────────────┬───────────────┬──────────────────┐
│ 📁 Documents    │ 📁 Downloads  │ 📁 src     ✕     │  ← ✕ appears on hover
│   (active)      │               │                  │
└═════════════════┴───────────────┴──────────────────┘
  ▲ highlighted                      ▲ close button
```

**TabItemView Subview:**
- Close button (appears on hover, only if multiple tabs)
- Folder icon + tab display name
- Active tab highlighted background
- Drag-over: blinking animation + auto-switch after 0.5s via DispatchWorkItem

**Environment:** `TabManager`
**Per-Item State:** `isHovering`, `isBlinking`, `switchWorkItem`
