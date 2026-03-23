# Test Plan

## Overview
Explorer has 29 unit/integration tests across 4 test suites, using the Swift Testing framework (0.12+). Tests use real filesystem operations on temporary directories — no mock objects or dependency injection overrides.

## Framework
- **Swift Testing** (`@Test`, `@Suite` macros) — modern replacement for XCTest
- **Package dependency**: `swift-testing` 0.12+ from `github.com/swiftlang/swift-testing`
- **Import**: `@testable import Explorer` + `import Testing`

## Test Infrastructure

### Temp Directory Pattern
All tests that touch the filesystem use UUID-based temporary directories:
```swift
func makeTempDir() throws -> URL {
    let dir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(".test-tmp")
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}
```
- Location: `.test-tmp/` at project root (gitignored)
- Isolation: UUID ensures no test interference
- Cleanup: `defer { cleanup(dir) }` in each test

### Helper Functions
```swift
func createFile(name: String, in dir: URL) throws -> URL   // Writes "test" text content
func createFolder(name: String, in dir: URL) throws -> URL  // Creates subdirectory
func cleanup(_ url: URL)                                     // try? removeItem
```

### Thread Safety
- Tests using `@MainActor`-isolated types (DirectoryViewModel, SplitScreenManager) are decorated with `@MainActor` on the `@Suite`
- This ensures main-thread serialization for all test methods in the suite

---

## Test Suites

### 1. DirectoryViewModelTests (DirectoryViewModelTests.swift)
**Suite**: "DirectoryViewModel loading state" | `@MainActor`
**Tests**: 7

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

### 2. FileMoveServiceTests (FileMoveServiceTests.swift)
**Suite**: "FileMoveService"
**Tests**: 12

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

### 3. PasteboardCommandTests (PasteboardCommandTests.swift)
**Suite**: "Pasteboard command behaviors" | `@MainActor`
**Tests**: 8

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

### 4. SplitScreenDoubleClickTests (SplitScreenDoubleClickTests.swift)
**Suite**: "SplitScreenManager.resolveDoubleClickTarget" | `@MainActor`
**Tests**: 3

| Test | Validates |
|------|-----------|
| doubleClickUsesActivePane | Returns right (active) pane's selection, not left |
| doubleClickIgnoresInactivePaneSelection | Returns nil when active pane has no selection |
| doubleClickSinglePane | Works correctly in non-split mode |

**Coverage**: Active pane priority, inactive pane isolation, single-pane fallback.

---

## Coverage Analysis

### What's Tested
| Component | Coverage |
|-----------|----------|
| DirectoryViewModel loading states | ✓ Comprehensive (7 tests) |
| DirectoryViewModel concurrent access | ✓ TaskGroup stress test |
| DirectoryViewModel selection behavior | ✓ Load clears, reload preserves |
| FileMoveService validation | ✓ All validation paths covered |
| FileMoveService execution | ✓ Success, multi-source, conflicts |
| ClipboardManager state | ✓ Cut, copy, clear operations |
| NSPasteboard integration | ✓ Write and overwrite |
| SplitScreenManager double-click | ✓ Active/inactive/single pane |
| Selection + search filter | ✓ selectAll respects search |

### What's NOT Tested
| Component | Gap |
|-----------|-----|
| NavigationViewModel | No tests for back/forward/up/breadcrumb navigation |
| SidebarViewModel | No tests for favorites add/remove/reorder or volume scanning |
| FavoritesManager | No tests for JSON persistence, bookmark resolution, staleness |
| DirectoryWatcher | No tests for FS monitoring or debounce behavior |
| FileSystemService | No direct tests (tested indirectly via DirectoryViewModel) |
| FormatHelpers | No tests for date/size/kind formatting |
| Views | No UI/snapshot tests |
| Drag & drop | No integration tests for drag-drop workflows |
| PathBarView | No tests for path editing, ~ expansion, validation |
| Error handling | No tests for permission denied, missing files, disk full |

### Recommendations
1. **NavigationViewModel tests**: Test navigate (symlink resolution, history), goBack/goForward, breadcrumb generation
2. **FavoritesManager tests**: Test persistence round-trip, stale bookmark recovery, defaults
3. **FormatHelpers tests**: Test date formatting threshold (7 days), file size edge cases, kind fallback chain
4. **FileSystemService tests**: Test enumerate batching, createFolder, renameItem
5. **Error scenario tests**: Permission denied, non-existent paths, disk space

---

## Running Tests
```bash
swift test
```
Tests create temporary files in `.test-tmp/` (gitignored). Cleanup runs via `defer` blocks but `.test-tmp/` may accumulate on test failures.
