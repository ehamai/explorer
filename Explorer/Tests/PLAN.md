# Test Plan

## Overview
Explorer has 203 unit/integration tests across 17 test suites (+ 1 shared helper file), using the Swift Testing framework (0.12+). Tests use real filesystem operations on temporary directories — no mock objects or dependency injection overrides.

## Framework
- **Swift Testing** (`@Test`, `@Suite` macros) — modern replacement for XCTest
- **Package dependency**: `swift-testing` 0.12+ from `github.com/swiftlang/swift-testing`
- **Import**: `@testable import Explorer` + `import Testing`

## Test Infrastructure

### Temp Directory Pattern
All tests that touch the filesystem use UUID-based temporary directories:
```swift
func makeTempDir() throws -> URL {
    let projectRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // Tests/
        .deletingLastPathComponent()  // Explorer/
        .deletingLastPathComponent()  // project root
    let testTmpRoot = projectRoot.appendingPathComponent(".test-tmp")
    try FileManager.default.createDirectory(at: testTmpRoot, withIntermediateDirectories: true)
    let dir = testTmpRoot.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}
```
- Location: `.test-tmp/` at project root (gitignored)
- Isolation: UUID ensures no test interference
- Cleanup: `defer { cleanup(dir) }` in each test

### Shared TestHelpers (TestHelpers.swift)
Centralised helpers available to all test suites:
```swift
TestHelpers.makeTempDir() throws -> URL              // UUID-based temp dir in .test-tmp/
TestHelpers.createFile(_:in:content:) throws -> URL  // Writes text file (@discardableResult)
TestHelpers.createFolder(_:in:) throws -> URL        // Creates subdirectory (@discardableResult)
TestHelpers.cleanup(_:)                               // try? removeItem
TestHelpers.makeFileItem(name:isDirectory:isHidden:size:dateModified:kind:basePath:) -> FileItem
    // Synthetic FileItem for unit tests that don't need real files on disk
```

### Thread Safety
- Tests using `@MainActor`-isolated types (DirectoryViewModel, SplitScreenManager, ClipboardManager, TabManager) are decorated with `@MainActor` on the `@Suite`
- This ensures main-thread serialization for all test methods in the suite

### Actor-Based Test Utilities
DirectoryWatcherTests uses a private `CallbackTracker` actor to safely count async callbacks across test boundaries without data races.

---

## Summary Table

| # | Suite | File | @MainActor | Tests | Component |
|---|-------|------|:---:|:---:|-----------|
| 1 | DirectoryViewModel loading state | DirectoryViewModelTests.swift | ✓ | 7 | DirectoryViewModel |
| 2 | DirectoryViewModel sort and filter | DirectoryViewModelSortFilterTests.swift | ✓ | 22 | DirectoryViewModel |
| 3 | FileMoveService | FileMoveServiceTests.swift | — | 12 | FileMoveService |
| 4 | Pasteboard command behaviors | PasteboardCommandTests.swift | ✓ | 8 | DirectoryViewModel + ClipboardManager |
| 5 | SplitScreenManager.resolveDoubleClickTarget | SplitScreenDoubleClickTests.swift | ✓ | 3 | SplitScreenManager |
| 6 | SplitScreenManager | SplitScreenManagerTests.swift | ✓ | 12 | SplitScreenManager |
| 7 | FileSystemService | FileSystemServiceTests.swift | — | 18 | FileSystemService |
| 8 | ClipboardManager paste operations | ClipboardManagerTests.swift | ✓ | 10 | ClipboardManager |
| 9 | NavigationViewModel | NavigationViewModelTests.swift | — | 22 | NavigationViewModel |
| 10 | FormatHelpers | FormatHelpersTests.swift | — | 11 | FormatHelpers |
| 11 | ViewMode | ViewModeTests.swift | — | 5 | ViewMode |
| 12 | FileSortDescriptor | FileSortDescriptorTests.swift | — | 15 | FileSortDescriptor |
| 13 | FileItem | FileItemTests.swift | — | 12 | FileItem |
| 14 | TabManager | TabManagerTests.swift | ✓ | 15 | TabManager |
| 15 | FavoritesManager | FavoritesManagerTests.swift | — | 15 | FavoritesManager |
| 16 | SidebarViewModel | SidebarViewModelTests.swift | — | 10 | SidebarViewModel |
| 17 | DirectoryWatcher | DirectoryWatcherTests.swift | — | 6 | DirectoryWatcher |
| | | **Total** | | **203** | |

---

## Test Suites

### 1. DirectoryViewModelTests (DirectoryViewModelTests.swift)
**Suite**: "DirectoryViewModel loading state" | `@MainActor`
**Tests**: 7
**Note**: Uses inline helpers (predates shared TestHelpers).

| Test | Purpose | Key Assertion |
|------|---------|---------------|
| isLoadingFalseAfterLoadDirectory | Loading flag transitions correctly | `vm.isLoading == false` after completion |
| isLoadingFalseAfterReloadCurrentDirectory | Reload doesn't leave loading hanging | `vm.isLoading == false` with correct item count |
| isLoadingFalseAfterConcurrentLoadAndReload | Concurrent operations serialize safely | Final state correct after load + reload |
| isLoadingFalseAfterMultipleConcurrentLoads | 5 concurrent loads via TaskGroup | No state corruption |
| loadDirectoryForNonexistentDirSetsLoadingFalse | Error handling for bad paths | `isLoading == false`, empty items |
| loadDirectoryClearsSelection | Fresh load resets selection | `selectedItems.isEmpty` |
| reloadCurrentDirectoryPreservesSelection | Reload maintains selection | Selection count preserved |

**Coverage**: Loading state machine, concurrent access safety, selection behavior on load vs reload.

### 2. DirectoryViewModelSortFilterTests (DirectoryViewModelSortFilterTests.swift)
**Suite**: "DirectoryViewModel sort and filter" | `@MainActor`
**Tests**: 22

#### Sort by Name (2 tests)
| Test | Purpose |
|------|---------|
| sortByNameAscending | A-Z sort order on 3 files |
| sortByNameDescending | Z-A sort order on 3 files |

#### Sort Toggle Behavior (2 tests)
| Test | Purpose |
|------|---------|
| sortByFieldTogglesSameField | Sorting by same field toggles ascending↔descending |
| sortByDifferentFieldResetsToAscending | Switching field resets to ascending |

#### Sort by Other Fields (2 tests)
| Test | Purpose |
|------|---------|
| sortBySizeAscending | Small → large by file size |
| sortByDateAscending | Old → new by modification date |

#### Hidden Files (3 tests)
| Test | Purpose |
|------|---------|
| showHiddenFalseFiltersHidden | Default hides dotfiles, allItems still contains them |
| showHiddenTrueShowsAll | Toggle reveals hidden files |
| toggleHiddenFlipsFlag | toggleHidden() flips boolean |

#### Search (4 tests)
| Test | Purpose |
|------|---------|
| searchTextFiltersItems | Substring match filters items |
| searchTextCaseInsensitive | Search ignores case |
| clearSearchTextShowsAll | Empty search restores all items |
| combinedFilterSortSearch | Hidden + search + sort combined |

#### Selection (4 tests)
| Test | Purpose |
|------|---------|
| selectAllSelectsVisibleItems | Selects only visible (non-hidden) items |
| clearSelectionEmptiesSet | Clears selection set |
| selectedURLsMapsCorrectly | Maps selected IDs to URLs |
| inspectedItemReturnsFirstSelected | Returns first selected FileItem |

#### Edge Cases (1 test)
| Test | Purpose |
|------|---------|
| inspectedItemNilWhenNoSelection | nil when nothing selected |

#### View Mode (1 test)
| Test | Purpose |
|------|---------|
| viewModeDefaultIsList | Default viewMode is .list |

#### Counts (2 tests)
| Test | Purpose |
|------|---------|
| itemCountMatchesItemsCount | itemCount == items.count |
| selectedCountMatchesSelectionCount | selectedCount == selectedItems.count |

#### Watcher Integration (1 test)
| Test | Purpose |
|------|---------|
| watcherOnChangeTriggersReload | Watcher onChange triggers auto-reload of directory contents |

**Coverage**: All sort fields/orders, toggle behavior, hidden file filtering, search with case insensitivity, combined filter pipeline, selection management, computed counts, watcher integration.

### 3. FileMoveServiceTests (FileMoveServiceTests.swift)
**Suite**: "FileMoveService"
**Tests**: 12
**Note**: Uses inline helpers (predates shared TestHelpers).

#### Folder Drop Validation (4 tests)
| Test | Validates |
|------|-----------|
| folderDropAcceptsFileFromDifferentDir | Valid cross-directory drop |
| folderDropRejectsDestinationItself | Self-drop prevention |
| folderDropRejectsParentIntoSubtree | Circular reference prevention |
| folderDropAllowsSiblingFolder | Sibling folder operations |

#### Background Drop Validation (5 tests)
| Test | Validates |
|------|-----------|
| backgroundDropRejectsFilesAlreadyInDestination | Duplicate prevention |
| backgroundDropAcceptsFilesFromDifferentDir | External file drop |
| backgroundDropRejectsDestinationItself | Self-drop prevention |
| backgroundDropRejectsParentIntoSubtree | Hierarchy violation |
| backgroundDropFiltersMixedURLs | Mixed valid/invalid filtering |

#### Move Execution (3 tests)
| Test | Validates |
|------|-----------|
| moveItemsMovesFileToDestination | Actual file move succeeds |
| moveItemsTracksSourceDirs | Multi-source directory tracking |
| moveItemsHandlesNameConflictGracefully | Conflict doesn't crash (movedCount == 0) |

**Coverage**: All validation paths, actual file operations, error scenarios.

### 4. PasteboardCommandTests (PasteboardCommandTests.swift)
**Suite**: "Pasteboard command behaviors" | `@MainActor`
**Tests**: 8
**Note**: Uses inline helpers (predates shared TestHelpers).

#### Selection Commands (3 tests)
| Test | Validates |
|------|-----------|
| selectAllSelectsAllVisibleItems | Multi-file selection |
| selectAllRespectsSearchFilter | Filtered selection (2/3 files match) |
| clearSelectionDeselectsAll | Selection reset |

#### Pasteboard Operations (2 tests)
| Test | Validates |
|------|-----------|
| copyPathWritesCorrectPathToPasteboard | NSPasteboard write |
| copyPathOverwritesPreviousPasteboardContent | Overwrite behavior |

#### ClipboardManager State (3 tests)
| Test | Validates |
|------|-----------|
| clipboardCutSetsOperationAndURLs | Cut state: isCut, hasPendingOperation, URLs |
| clipboardCopySetsOperationAndURLs | Copy state: !isCut, pending, URLs |
| clipboardClearResetsState | Clear: no pending operation, empty URLs |

**Coverage**: Selection logic, pasteboard integration, clipboard state machine.

### 5. SplitScreenDoubleClickTests (SplitScreenDoubleClickTests.swift)
**Suite**: "SplitScreenManager.resolveDoubleClickTarget" | `@MainActor`
**Tests**: 3
**Note**: Uses inline helpers (predates shared TestHelpers).

| Test | Validates |
|------|-----------|
| doubleClickUsesActivePane | Returns right (active) pane's selection, not left |
| doubleClickIgnoresInactivePaneSelection | Returns nil when active pane has no selection |
| doubleClickSinglePane | Works correctly in non-split mode |

**Coverage**: Active pane priority, inactive pane isolation, single-pane fallback.

### 6. SplitScreenManagerTests (SplitScreenManagerTests.swift)
**Suite**: "SplitScreenManager" | `@MainActor`
**Tests**: 12

| Test | Purpose |
|------|---------|
| initSinglePane | isSplitScreen false, rightPane nil on init |
| initActivePaneIsLeft | activePaneID == leftPane.id |
| toggleEnablesSplit | isSplitScreen true, rightPane created |
| toggleActivatesRightPane | activePaneID switches to rightPane |
| toggleBackToSingleDestroysRightPane | Double toggle destroys rightPane |
| toggleBackActivatesLeftPane | Double toggle restores leftPane as active |
| activateSetsPane | activate(pane:) updates activePaneID |
| isActiveReturnsCorrectly | true for active, false for other |
| activePaneReturnsCorrect | Returns left in single, right if active in split |
| activeTabManagerMatchesActivePane | Matches activePane.tabManager identity |
| reloadAllPanesReloadsMatchingTabs | Both panes refresh when showing target URL |
| togglePreservesLeftPaneState | Left pane tabs survive toggle round-trip |

**Coverage**: Init state, toggle lifecycle, pane activation, active pane resolution, reload propagation, state preservation.

### 7. FileSystemServiceTests (FileSystemServiceTests.swift)
**Suite**: "FileSystemService"
**Tests**: 18

| Test | Purpose |
|------|---------|
| fullEnumerateListsFiles | 3 files → count == 3 |
| fullEnumerateShowHiddenFalse | Hidden file excluded |
| fullEnumerateShowHiddenTrue | Hidden file included |
| fullEnumerateEmptyDir | Empty dir → empty array |
| fullEnumerateNonexistentThrows | Bogus URL throws |
| fullEnumerateReturnsCorrectProperties | name, isDirectory correct |
| moveItemsMovesFile | Source gone, destination exists |
| moveItemsThrowsOnConflict | Throws on name collision |
| copyItemsCopiesFile | Both source and destination exist |
| copyItemsThrowsOnConflict | Throws on name collision |
| deleteItemsTrashesFile | File removed (graceful skip if Trash unavailable) |
| renameItemReturnsNewURL | New URL has new name |
| renameItemOldURLGone | Old path no longer exists |
| createFolderReturnsURL | Folder exists at returned URL |
| createFolderThrowsIfExists | Throws on existing folder |
| fileExistsTrueForExisting | true for real file |
| fileExistsFalseForNonexistent | false for bogus path |
| isDirectoryTrueForDir | true for dir, false for file |

**Coverage**: All public FileSystemService methods, error paths, hidden file filtering.

### 8. ClipboardManagerTests (ClipboardManagerTests.swift)
**Suite**: "ClipboardManager paste operations" | `@MainActor`
**Tests**: 10

| Test | Purpose |
|------|---------|
| pasteCutMovesFiles | Cut + paste moves files to destination |
| pasteCutReturnsSourceDir | Returns source directory URL |
| pasteCutClearsState | After paste, operation is idle |
| pasteCopyLeavesSource | Copy + paste preserves source |
| pasteCopyReturnsNil | Returns nil (no dir to refresh) |
| pasteIdleReturnsNil | Paste without cut/copy → nil |
| cutPostsNotification | clipboardStateChanged notification posted |
| copyPostsNotification | clipboardStateChanged notification posted |
| clearPostsNotification | clipboardStateChanged notification posted |
| sourceDirectoryTracked | sourceDirectory matches first URL's parent |

**Coverage**: Full paste lifecycle (cut/copy/idle), notification posting, source directory tracking.

### 9. NavigationViewModelTests (NavigationViewModelTests.swift)
**Suite**: "NavigationViewModel"
**Tests**: 22

| Test | Purpose |
|------|---------|
| initSetsCurrentURL | Starting URL is standardized |
| initDefaultsToHome | Default init uses home directory |
| navigatePushesToBackStack | Old URL pushed to backStack |
| navigateClearsForwardStack | ForwardStack cleared on navigate |
| navigateUpdatesCurrentURL | currentURL changes to target |
| navigateToSameURLIsNoOp | No change if navigating to current |
| goBackPopsBackStack | BackStack shrinks by one |
| goBackPushesToForwardStack | Current pushed to forwardStack |
| goBackUpdatesCurrentURL | Returns to previous URL |
| goBackWhenEmptyIsNoOp | No-op with empty backStack |
| goForwardPopsForwardStack | ForwardStack shrinks by one |
| goForwardPushesToBackStack | Current pushed to backStack |
| goForwardUpdatesCurrentURL | Moves to next URL |
| goForwardWhenEmptyIsNoOp | No-op with empty forwardStack |
| goUpNavigatesToParent | currentURL becomes parent dir |
| goUpAtRootIsNoOp | Root can't go up further |
| canGoBackReflectsBackStack | Boolean tracks backStack state |
| canGoForwardReflectsForwardStack | Boolean tracks forwardStack state |
| canGoUpTrueForNonRoot | True for non-root, false for root |
| pathComponentsFromRootToCurrentURL | Correct breadcrumb array |
| navigateToPathComponentDelegatesToNavigate | Breadcrumb click navigates |
| multipleNavigationsAndBackForward | Full back/forward scenario |

**Coverage**: Init, navigate, goBack, goForward, goUp, computed properties, breadcrumbs, complex scenarios.

### 10. FormatHelpersTests (FormatHelpersTests.swift)
**Suite**: "FormatHelpers"
**Tests**: 11

| Test | Purpose |
|------|---------|
| formatFileSizeZeroBytes | Zero bytes formatting |
| formatFileSizeKilobytes | KB range formatting |
| formatFileSizeMegabytes | MB range formatting |
| formatFileSizeGigabytes | GB range formatting |
| formatDateRecent | Relative format within 7 days |
| formatDateOld | Absolute format for old dates |
| formatDateFuture | Future dates use absolute format |
| fileKindDescriptionForDirectory | Temp dir returns "Folder" |
| fileKindDescriptionForTextFile | .txt returns non-empty kind |
| fileKindDescriptionForUnknownExtension | Unknown ext returns non-empty |
| fileKindDescriptionForNoExtension | No extension returns "Document" |

**Coverage**: File size formatting, date formatting (relative/absolute threshold), file kind description fallback chain.

### 11. ViewModeTests (ViewModeTests.swift)
**Suite**: "ViewMode"
**Tests**: 5

| Test | Purpose |
|------|---------|
| listSystemImage | .list → "list.bullet" |
| iconSystemImage | .icon → "square.grid.2x2" |
| listLabel | .list → "List" |
| iconLabel | .icon → "Icons" |
| allCasesHasTwoElements | CaseIterable count == 2 |

**Coverage**: All ViewMode properties and CaseIterable conformance.

### 12. FileSortDescriptorTests (FileSortDescriptorTests.swift)
**Suite**: "FileSortDescriptor"
**Tests**: 15

| Test | Purpose |
|------|---------|
| defaultFieldIsName | Default field is .name |
| defaultOrderIsAscending | Default order is .ascending |
| compareByNameAscending | Name ascending comparison |
| compareByNameDescending | Name descending comparison |
| compareByNameCaseInsensitive | Case-insensitive name comparison |
| compareBySizeAscending | Size ascending comparison |
| compareBySizeDescending | Size descending comparison |
| compareByDateAscending | Date ascending comparison |
| compareByDateDescending | Date descending comparison |
| compareByKindAscending | Kind ascending comparison |
| directoriesAlwaysBeforeFiles | Directories sort first for all field/order combos |
| codableRoundTrip | JSON encode → decode preserves field + order |
| sortFieldLabelsCorrect | SortField.label values correct |
| sortOrderToggledValues | SortOrder.toggled returns opposite |
| equalityCheck | Equatable conformance (== and !=) |

**Coverage**: All sort fields, both orders, case insensitivity, directory-first invariant, Codable round-trip, label accessors, toggle helper, equality.

### 13. FileItemTests (FileItemTests.swift)
**Suite**: "FileItem"
**Tests**: 12

| Test | Purpose |
|------|---------|
| identifiableIDIsURL | id == url |
| equalitySameURL | Same URL = equal regardless of other properties |
| equalityDifferentURL | Different URLs = not equal |
| hashableSameURL | Same URL = same hash |
| comparableDirectoriesBeforeFiles | Directories sort before files |
| comparableAlphabeticalWithinFiles | Alphabetical within same type |
| comparableAlphabeticalWithinDirectories | Alphabetical within directories |
| comparableCaseInsensitive | Case-insensitive comparison |
| fromURLValidFile | FileItem.fromURL for real file |
| fromURLDirectory | FileItem.fromURL for directory |
| fromURLNonexistent | FileItem.fromURL returns nil for bogus path |
| initWithIcon | Custom NSImage icon parameter |

**Coverage**: Identifiable, Equatable, Hashable, Comparable conformances, fromURL factory, icon init.

### 14. TabManagerTests (TabManagerTests.swift)
**Suite**: "TabManager" | `@MainActor`
**Tests**: 15

| Test | Purpose |
|------|---------|
| initHasOneTab | Starts with exactly 1 tab |
| initActiveTabIsFirst | Active tab is the first tab |
| addTabIncreasesCount | Adding tab increases count |
| addTabActivatesNewTab | New tab becomes active |
| addTabWithURL | Tab created with specific URL |
| addTabDefaultURL | Default tab uses home directory |
| closeTabRemovesTab | Closing tab removes it from array |
| closeTabUpdatesActiveToAdjacent | Closing active tab activates adjacent |
| closeTabLastTabPrevented | Cannot close the last remaining tab |
| closeTabNonActive | Closing non-active tab preserves active |
| closeActiveTabDelegates | closeActiveTab() delegates to closeTab() |
| activeTabReturnsCorrectTab | Computed property returns correct tab |
| tabDisplayName | Display name is last path component |
| addThreeCloseMiddle | Complex: 3 tabs, close middle, verify remaining |
| closeTabUpdatesActiveToLastWhenClosingLast | Closing last tab in list activates previous |

**Coverage**: Init state, addTab (with/without URL), closeTab (active/non-active/last/middle), activeTab resolution, display name, complex multi-tab scenarios.

### 15. FavoritesManagerTests (FavoritesManagerTests.swift)
**Suite**: "FavoritesManager"
**Tests**: 15

| Test | Purpose |
|------|---------|
| initLoadsDefaults | Init populates default favorites (Desktop, Documents, etc.) |
| addFavoriteAppendsItem | Adding increases count by 1 |
| addFavoriteDuplicateRejected | Duplicate URL is rejected |
| addFavoriteSetsCorrectName | Name set from folder name |
| removeFavoriteByID | Remove by UUID works |
| removeFavoriteNonexistentIDNoOp | Removing bogus ID is no-op |
| moveFavoriteReorders | IndexSet-based reorder works |
| persistenceRoundTrip | New manager with same storage loads persisted data |
| saveFavoritesCreatesDirectory | Storage directory created if missing |
| saveFavoritesWritesFile | favorites.json file created |
| loadFavoritesEmptyFileReturnsEmpty | Corrupt JSON → empty favorites |
| addFavoriteToEmptyStorage | Add to empty list works |
| favoritesURLsAreCorrect | Stored URLs match input |
| multipleAddRemove | Add 3, remove middle, verify order |
| favoriteItemCodableRoundTrip | FavoriteItem JSON encode/decode preserves all fields |

**Coverage**: Init with defaults, add/remove/move operations, duplicate rejection, JSON persistence round-trip, storage directory creation, corrupt file handling, Codable conformance.

### 16. SidebarViewModelTests (SidebarViewModelTests.swift)
**Suite**: "SidebarViewModel"
**Tests**: 10

| Test | Purpose |
|------|---------|
| initLoadsFavorites | Init loads non-empty favorites |
| systemLocationsHasFiveItems | 5 system locations |
| systemLocationsCorrectNames | Desktop, Documents, Downloads, Home, Applications |
| systemLocationsCorrectIcons | Correct SF Symbol names |
| addFavoriteDelegatesToManager | addFavorite delegates to FavoritesManager |
| removeFavoriteDelegatesToManager | removeFavorite delegates to FavoritesManager |
| moveFavoriteReorders | Reorder via IndexSet works |
| syncFavoritesMatchesManager | VM favorites count matches manager |
| refreshVolumesPopulatesArray | refreshVolumes produces valid entries |
| volumesHaveCorrectIconTypes | Volumes use internaldrive.fill or externaldrive.fill |

**Coverage**: Init state, system locations (names + icons), favorites delegation (add/remove/move), sync consistency, volume scanning with icon validation.

### 17. DirectoryWatcherTests (DirectoryWatcherTests.swift)
**Suite**: "DirectoryWatcher"
**Tests**: 6

| Test | Purpose |
|------|---------|
| onChangeFiresOnFileCreation | Callback fires when file created in watched dir |
| stopPreventsCallback | Calling stop() prevents future callbacks |
| watchNewDirStopsOld | Watching new dir stops monitoring old dir |
| watchInvalidPathDoesNotCrash | Invalid path handled gracefully (no crash) |
| rapidChangesDebounce | 5 rapid file creates → debounced to < 5 callbacks |
| initWithOnChangeCallback | Init with closure parameter works |

**Coverage**: Core watch/stop lifecycle, directory switching, invalid path safety, debounce behavior, init variants.

---

## Testing Patterns

### 1. Real Filesystem, No Mocks
All tests use real `FileManager` operations on temp directories. No mock objects or protocol-based dependency injection overrides. This ensures tests validate actual behavior.

### 2. Injectable Dependencies for Isolation
Services accept dependencies via init parameters to enable testing:
- `DirectoryViewModel(watcher:)` — injectable watcher for testing onChange integration
- `FavoritesManager(storageDirectory:)` — injectable storage path avoids polluting real favorites
- `SidebarViewModel(favoritesManager:)` — injectable manager for isolated testing
- `ClipboardManager(fileSystemService:)` — injectable service

### 3. Temp Directory Lifecycle
```swift
let dir = try TestHelpers.makeTempDir()
defer { TestHelpers.cleanup(dir) }
```
UUID-based dirs in `.test-tmp/` prevent cross-test interference.

### 4. Synthetic FileItem Factory
`TestHelpers.makeFileItem(name:isDirectory:size:dateModified:kind:)` creates in-memory FileItems without touching the filesystem — used by FileSortDescriptorTests, FileItemTests, and any test that needs FileItem data without disk I/O.

### 5. Actor-Based Async Tracking
DirectoryWatcherTests uses a private `CallbackTracker` actor to safely count async callbacks:
```swift
private actor CallbackTracker {
    var callCount = 0
    func increment() { callCount += 1 }
}
```

### 6. Legacy Inline Helpers
Some original suites (DirectoryViewModelTests, FileMoveServiceTests, PasteboardCommandTests, SplitScreenDoubleClickTests) define their own private `makeTempDir()`, `createFile()`, `cleanup()` helpers — predating the shared TestHelpers. Functionally equivalent.

---

## Coverage Analysis

### What's Tested
| Component | Coverage |
|-----------|----------|
| DirectoryViewModel loading states | ✓ Comprehensive (7 tests) |
| DirectoryViewModel sort/filter/search | ✓ All fields, orders, combined pipeline (22 tests) |
| DirectoryViewModel selection | ✓ selectAll, clear, selectedURLs, inspectedItem |
| DirectoryViewModel watcher integration | ✓ onChange triggers reload |
| DirectoryViewModel concurrent access | ✓ TaskGroup stress test |
| FileMoveService validation | ✓ All validation paths covered |
| FileMoveService execution | ✓ Success, multi-source, conflicts |
| ClipboardManager state | ✓ Cut, copy, clear operations |
| ClipboardManager paste lifecycle | ✓ Cut/copy/idle paste, notifications, source tracking (10 tests) |
| NSPasteboard integration | ✓ Write and overwrite |
| SplitScreenManager double-click | ✓ Active/inactive/single pane |
| SplitScreenManager lifecycle | ✓ Toggle, activate, reload, state preservation (12 tests) |
| FileSystemService | ✓ Enumerate, move, copy, delete, rename, create, existence (18 tests) |
| NavigationViewModel | ✓ Navigate, back/forward, goUp, breadcrumbs, edge cases (22 tests) |
| FormatHelpers | ✓ File size, date formatting, kind description (11 tests) |
| ViewMode | ✓ All properties and cases (5 tests) |
| FileSortDescriptor | ✓ All fields, orders, directory-first, Codable, labels (15 tests) |
| FileItem | ✓ Identity, equality, hash, comparable, fromURL, icon (12 tests) |
| TabManager | ✓ Add/close/activate tabs, edge cases, display name (15 tests) |
| FavoritesManager | ✓ CRUD, persistence, defaults, corrupt file handling (15 tests) |
| SidebarViewModel | ✓ System locations, favorites delegation, volumes (10 tests) |
| DirectoryWatcher | ✓ Watch/stop lifecycle, debounce, invalid path (6 tests) |

### What's NOT Tested
| Component | Gap |
|-----------|-----|
| Views | No UI/snapshot tests (SwiftUI views) |
| Drag & drop integration | No end-to-end drag-drop workflow tests |
| PathBarView | No tests for path editing, ~ expansion, validation |
| FileSystemService.enumerate (streaming) | Only fullEnumerate tested; streaming AsyncStream variant untested |
| Error UI | No tests for user-facing error display (none exists yet) |
| Security-scoped bookmarks | FavoritesManager bookmark resolution tested indirectly via persistence round-trip |
| ExplorerApp commands | Keyboard shortcuts and menu command wiring untested |

---

## Running Tests
```bash
swift test
```
Tests create temporary files in `.test-tmp/` (gitignored). Cleanup runs via `defer` blocks but `.test-tmp/` may accumulate on test failures.
