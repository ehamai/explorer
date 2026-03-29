# Tests

## Overview
Explorer has 203 unit/integration tests across 17 test suites, using the Swift Testing framework (0.12+). Tests use real filesystem operations on temporary directories — no mocking.

## Framework
- **Swift Testing** (`@Test`, `@Suite` macros)
- **Dependency**: `swift-testing` 0.12+ from `github.com/swiftlang/swift-testing`
- **Import**: `@testable import Explorer` + `import Testing`

## Test Infrastructure

### Temp Directory Pattern
All filesystem tests use UUID-based temporary directories in `.test-tmp/` at project root (gitignored). Each test creates its own isolated directory and cleans up via `defer { TestHelpers.cleanup(dir) }`.

### Shared TestHelpers (TestHelpers.swift)
```swift
TestHelpers.makeTempDir() throws -> URL              // UUID-based temp dir
TestHelpers.createFile(_:in:content:) throws -> URL  // Writes text file
TestHelpers.createFolder(_:in:) throws -> URL        // Creates subdirectory
TestHelpers.cleanup(_:)                               // try? removeItem
TestHelpers.makeFileItem(name:isDirectory:isHidden:size:dateModified:kind:basePath:) -> FileItem
    // Synthetic FileItem for tests not needing real files
```

### Thread Safety
- Suites testing `@MainActor`-isolated types are decorated with `@MainActor`
- DirectoryWatcherTests uses a private `CallbackTracker` actor for safe async callback counting

## Test Suites

| Suite | File | @MainActor | Tests | Component |
|-------|------|:---:|:---:|-----------|
| DirectoryViewModel loading state | DirectoryViewModelTests.swift | ✓ | 7 | DirectoryViewModel |
| DirectoryViewModel sort and filter | DirectoryViewModelSortFilterTests.swift | ✓ | 22 | DirectoryViewModel |
| FileMoveService | FileMoveServiceTests.swift | — | 12 | FileMoveService |
| Pasteboard command behaviors | PasteboardCommandTests.swift | ✓ | 8 | DirectoryViewModel + ClipboardManager |
| SplitScreenManager.resolveDoubleClickTarget | SplitScreenDoubleClickTests.swift | ✓ | 3 | SplitScreenManager |
| SplitScreenManager | SplitScreenManagerTests.swift | ✓ | 12 | SplitScreenManager |
| FileSystemService | FileSystemServiceTests.swift | — | 18 | FileSystemService |
| ClipboardManager paste operations | ClipboardManagerTests.swift | ✓ | 10 | ClipboardManager |
| NavigationViewModel | NavigationViewModelTests.swift | — | 22 | NavigationViewModel |
| FormatHelpers | FormatHelpersTests.swift | — | 11 | FormatHelpers |
| ViewMode | ViewModeTests.swift | — | 5 | ViewMode |
| FileSortDescriptor | FileSortDescriptorTests.swift | — | 15 | FileSortDescriptor |
| FileItem | FileItemTests.swift | — | 12 | FileItem |
| TabManager | TabManagerTests.swift | ✓ | 15 | TabManager |
| FavoritesManager | FavoritesManagerTests.swift | — | 15 | FavoritesManager |
| SidebarViewModel | SidebarViewModelTests.swift | — | 10 | SidebarViewModel |
| DirectoryWatcher | DirectoryWatcherTests.swift | — | 6 | DirectoryWatcher |
| | **Total** | | **203** | |
