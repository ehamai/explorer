# Sidebar View

## SidebarView (SidebarView.swift)

Navigation sidebar with search, favorites, locations, and volumes.

```
┌──────────────┐
│ 🔍 Search... │
├──────────────┤
│ FAVORITES    │
│  ★ Desktop   │  ← Drag to reorder
│  ★ Documents │  ← Right-click → Remove
│  ★ Downloads │  ← Drop folder to add
├──────────────┤
│ LOCATIONS    │
│  🖥 Desktop  │
│  📄 Documents│
│  ⬇ Downloads │
│  🏠 Home     │
│  ▦ Apps      │
├──────────────┤
│ VOLUMES      │
│  💾 Macintosh│
│  💿 External │
├──────────────┤
│ [+ Add Folder│
│    to Favs]  │
└──────────────┘
```

**Sections:**
1. **Search:** Text field bound to `directoryVM.searchText`
2. **Favorites:** Reorderable list of FavoriteItem (drag to reorder, drop to add, context menu to remove)
3. **Locations:** System shortcuts — Desktop, Documents, Downloads, Home, Applications (SF Symbol icons)
4. **Volumes:** Mounted drives (internal/external with appropriate icons)
5. **Add Button:** "Add Current Folder" at bottom

**SidebarRow Subview:** Button with icon + name, hover effect (pointer cursor), highlighted background for active location.

**Environment:** `NavigationViewModel`, `DirectoryViewModel`, `SidebarViewModel`
**Bindings:** `@Bindable` for `directoryVM.searchText`

**Context Menu:** Remove from Favorites (on favorite items)

**Drop Targets:** Sidebar favorites section accepts folder drops to add as favorites.
