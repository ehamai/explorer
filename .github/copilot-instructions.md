# Copilot Instructions for Explorer

## Architecture Overview
Explorer is a macOS SwiftUI file browser using MVVM + Services architecture. See `plan.md` at the repo root for the full architectural overview, and `PLAN.md` files in each source subdirectory for layer-specific documentation.

## Plan File System

### Structure
```
plan.md                              # Main architectural plan (repo root)
Explorer/Sources/Models/PLAN.md      # Models layer documentation
Explorer/Sources/Views/PLAN.md       # Views layer documentation
Explorer/Sources/ViewModels/PLAN.md  # ViewModels layer documentation
Explorer/Sources/Services/PLAN.md    # Services layer documentation
Explorer/Sources/Helpers/PLAN.md     # Helpers layer documentation
Explorer/Tests/PLAN.md               # Test suite documentation
```

### Plan Maintenance Rules

**IMPORTANT**: When making code changes, always update the relevant PLAN.md file(s) to reflect the change. Plans must stay in sync with the code.

#### When to Update Existing Plans
- Adding/removing/modifying properties on existing types
- Adding/removing/modifying methods on existing types
- Changing protocol conformances
- Modifying state management patterns
- Changing error handling behavior
- Adding/removing keyboard shortcuts or menu commands
- Modifying navigation flows
- Changing persistence formats or locations
- Adding/removing environment object dependencies in views

#### When to Create New Plans
- Adding a new source directory (e.g., `Explorer/Sources/Networking/`) → create `PLAN.md` in that directory
- The new plan should follow the same structure as existing plans

#### What to Document for New Types

**New Model/Struct/Enum**:
- Purpose (one sentence)
- All properties with types, access levels, and purposes
- All methods with signatures and behavior descriptions
- Protocol conformances
- Relationships to other types
- Design patterns used

**New View**:
- Purpose
- View hierarchy position (where it sits in the tree)
- State management (@Environment, @State, @Binding usage)
- User interactions handled
- Navigation flows affected

**New ViewModel**:
- Purpose
- All published/observed properties
- Core methods with business logic description
- Dependencies (services used)
- Inter-ViewModel communication patterns

**New Service**:
- Purpose
- Public API (all methods with signatures)
- Concurrency model (actor, async/await, GCD, sync)
- Error handling strategy
- Persistence details (if any)
- Dependencies

**New Test Suite**:
- Suite name and test count
- What component is tested
- Key test scenarios covered
- Any new test helpers or patterns

#### Update the Main Plan
After updating any sub-plan, check if the main `plan.md` needs updates:
- New features should be added to the Feature Inventory
- New keyboard shortcuts should be added to the Keyboard Shortcuts table
- New environment objects should be added to the Environment Object Injection table
- Architectural changes should be reflected in the Architecture diagram
- New files should be added to the Project Structure tree

## Coding Conventions

### Architecture
- **MVVM + Services**: Views read state from ViewModels via @Environment; ViewModels delegate I/O to Services
- **ViewModels never reference each other**: Views coordinate cross-ViewModel actions
- **@Observable macro**: Use `@Observable` (not `ObservableObject`) for all new observable types
- **@MainActor**: Apply to any class that manages UI state
- **Dependency injection**: Accept dependencies via init parameters with defaults

### State Management
- Use `@Environment` for dependency injection (not @ObservedObject or @StateObject)
- Use `private(set)` for properties that views should read but not write
- Use `didSet` observers for derived state that should auto-update
- Keep `@State` for view-local state only (not shared state)

### File Operations
- All file I/O goes through `FileSystemService` (actor-isolated)
- Use `async/await` for file operations
- Use `FileManager.trashItem` for deletions (not `removeItem`)
- After file operations, reload affected directories via `directoryVM.loadDirectory` and `splitManager.reloadAllPanes`

### Error Handling
- FileSystemService throws — callers handle errors
- ViewModels currently catch silently (known gap — improve when possible)
- FavoritesManager uses fallback chains for bookmark resolution

### Concurrency
- FileSystemService is a Swift actor — thread-safe by design
- DirectoryViewModel is @MainActor — all state on main thread
- DirectoryWatcher uses GCD with utility QoS
- Views use `Task { await ... }` blocks for async operations

### Testing
- Use Swift Testing framework (`@Test`, `@Suite`)
- Create temp directories with UUID-based paths in `.test-tmp/`
- Use `defer { cleanup(dir) }` for cleanup
- Mark suites testing @MainActor types with `@MainActor`
- No mocking — use real FileManager with temp directories

### Views
- Use `@ViewBuilder` for complex conditional content
- Use SwiftUI Table for list views (not List)
- Use LazyVGrid with adaptive columns for grid views
- Context menus should include: Open, Cut/Copy/Paste, Rename, Favorites (folders), Properties, Trash
- Drop targets need validation via FileMoveService

### Naming Conventions
- ViewModels: `*ViewModel` suffix (e.g., `DirectoryViewModel`)
- Services: `*Service`, `*Manager`, or `*Watcher` suffix
- Models: Descriptive names (e.g., `FileItem`, `BrowserTab`, `PaneState`)
- Plan files: Always named `PLAN.md` (uppercase)
- Test files: `*Tests.swift` suffix matching the component name

## Common Tasks

### Adding a New View
1. Create the view in `Explorer/Sources/Views/`
2. Add it to the view hierarchy in its parent view
3. Inject necessary environment objects
4. Update `Explorer/Sources/Views/PLAN.md` with full documentation
5. Update `plan.md` Project Structure if adding a new file

### Adding a New Service
1. Create in `Explorer/Sources/Services/`
2. Choose concurrency model (actor for shared I/O, @Observable for UI state, class for lifecycle)
3. Wire it up in ExplorerApp (if app-scoped) or in the consuming ViewModel
4. Update `Explorer/Sources/Services/PLAN.md`
5. Update `plan.md` dependency graph
6. Write tests in `Explorer/Tests/`
7. Update `Explorer/Tests/PLAN.md`

### Adding a Keyboard Shortcut
1. Add CommandGroup entry in ExplorerApp.swift
2. Implement the action (respecting text editing vs file operation dual-mode pattern)
3. Update `plan.md` Keyboard Shortcuts table
4. Update `Explorer/Sources/Views/PLAN.md` if it affects view interactions

### Adding a New Model
1. Create in `Explorer/Sources/Models/`
2. Define protocol conformances (Identifiable, Hashable, Codable as needed)
3. Update `Explorer/Sources/Models/PLAN.md`
4. Update `plan.md` if it changes the composition hierarchy

### Refactoring
1. Read the relevant PLAN.md files BEFORE starting
2. Make the code changes
3. Update ALL affected PLAN.md files
4. Run `swift test` to verify nothing broke
5. Run `swift build` to verify compilation
