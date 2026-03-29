# Status Bar

## StatusBarView (StatusBarView.swift)

Bottom bar showing item counts and disk space.

```
┌──────────────────────────────────────────────────────┐
│  12 items · 2 selected                 142.5 GB free │
└──────────────────────────────────────────────────────┘
  ▲ item count   ▲ selection count        ▲ disk space (right-aligned)
```

**Content:** "{N} items" (with plural), "• {N} selected" (if any), available disk space (right-aligned).

**Environment:** `DirectoryViewModel`, `NavigationViewModel` — display-only, no local state.
