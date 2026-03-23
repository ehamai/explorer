import Testing
import Foundation
@testable import Explorer

@Suite("DirectoryViewModel sort and filter")
@MainActor
struct DirectoryViewModelSortFilterTests {

    // MARK: - Sort by Name

    @Test func sortByNameAscending() async throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }
        _ = try TestHelpers.createFile("cherry.txt", in: dir)
        _ = try TestHelpers.createFile("apple.txt", in: dir)
        _ = try TestHelpers.createFile("banana.txt", in: dir)

        let vm = DirectoryViewModel()
        await vm.loadDirectory(url: dir)
        vm.sort(by: FileSortDescriptor(field: .name, order: .ascending))

        let names = vm.items.map(\.name)
        #expect(names == ["apple.txt", "banana.txt", "cherry.txt"])
    }

    @Test func sortByNameDescending() async throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }
        _ = try TestHelpers.createFile("cherry.txt", in: dir)
        _ = try TestHelpers.createFile("apple.txt", in: dir)
        _ = try TestHelpers.createFile("banana.txt", in: dir)

        let vm = DirectoryViewModel()
        await vm.loadDirectory(url: dir)
        vm.sort(by: FileSortDescriptor(field: .name, order: .descending))

        let names = vm.items.map(\.name)
        #expect(names == ["cherry.txt", "banana.txt", "apple.txt"])
    }

    @Test func sortByFieldTogglesSameField() async throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }
        _ = try TestHelpers.createFile("a.txt", in: dir)

        let vm = DirectoryViewModel()
        await vm.loadDirectory(url: dir)

        // Default is name ascending; sorting by name again should toggle to descending
        vm.sort(by: .name)
        #expect(vm.sortDescriptor.field == .name)
        #expect(vm.sortDescriptor.order == .descending)
    }

    @Test func sortByDifferentFieldResetsToAscending() async throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }
        _ = try TestHelpers.createFile("a.txt", in: dir)

        let vm = DirectoryViewModel()
        await vm.loadDirectory(url: dir)
        vm.sort(by: FileSortDescriptor(field: .name, order: .descending))

        vm.sort(by: .size)
        #expect(vm.sortDescriptor.field == .size)
        #expect(vm.sortDescriptor.order == .ascending)
    }

    @Test func sortBySizeAscending() async throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }
        _ = try TestHelpers.createFile("small.txt", in: dir, content: "a")
        _ = try TestHelpers.createFile("medium.txt", in: dir, content: String(repeating: "b", count: 100))
        _ = try TestHelpers.createFile("large.txt", in: dir, content: String(repeating: "c", count: 1000))

        let vm = DirectoryViewModel()
        await vm.loadDirectory(url: dir)
        vm.sort(by: FileSortDescriptor(field: .size, order: .ascending))

        let names = vm.items.map(\.name)
        #expect(names == ["small.txt", "medium.txt", "large.txt"])
    }

    @Test func sortByDateAscending() async throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }

        let file1 = try TestHelpers.createFile("oldest.txt", in: dir)
        let file2 = try TestHelpers.createFile("middle.txt", in: dir)
        let file3 = try TestHelpers.createFile("newest.txt", in: dir)

        let now = Date()
        try FileManager.default.setAttributes(
            [.modificationDate: now.addingTimeInterval(-200)], ofItemAtPath: file1.path)
        try FileManager.default.setAttributes(
            [.modificationDate: now.addingTimeInterval(-100)], ofItemAtPath: file2.path)
        try FileManager.default.setAttributes(
            [.modificationDate: now], ofItemAtPath: file3.path)

        let vm = DirectoryViewModel()
        await vm.loadDirectory(url: dir)
        vm.sort(by: FileSortDescriptor(field: .dateModified, order: .ascending))

        let names = vm.items.map(\.name)
        #expect(names == ["oldest.txt", "middle.txt", "newest.txt"])
    }

    // MARK: - Hidden Files

    @Test func showHiddenFalseFiltersHidden() async throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }
        _ = try TestHelpers.createFile("visible.txt", in: dir)
        _ = try TestHelpers.createFile(".hidden", in: dir)

        let vm = DirectoryViewModel()
        await vm.loadDirectory(url: dir)
        // showHidden defaults to false

        let names = vm.items.map(\.name)
        #expect(names.contains("visible.txt"))
        #expect(!names.contains(".hidden"))
        // Verify hidden file IS in allItems (loaded but filtered)
        #expect(vm.allItems.contains { $0.name == ".hidden" })
    }

    @Test func showHiddenTrueShowsAll() async throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }
        _ = try TestHelpers.createFile("visible.txt", in: dir)
        _ = try TestHelpers.createFile(".hidden", in: dir)

        let vm = DirectoryViewModel()
        vm.showHidden = true
        await vm.loadDirectory(url: dir)

        let names = vm.items.map(\.name)
        #expect(names.contains("visible.txt"))
        #expect(names.contains(".hidden"))
    }

    @Test func toggleHiddenFlipsFlag() {
        let vm = DirectoryViewModel()
        #expect(vm.showHidden == false)
        vm.toggleHidden()
        #expect(vm.showHidden == true)
        vm.toggleHidden()
        #expect(vm.showHidden == false)
    }

    // MARK: - Search

    @Test func searchTextFiltersItems() async throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }
        _ = try TestHelpers.createFile("report.txt", in: dir)
        _ = try TestHelpers.createFile("readme.md", in: dir)
        _ = try TestHelpers.createFile("data.csv", in: dir)

        let vm = DirectoryViewModel()
        await vm.loadDirectory(url: dir)
        vm.searchText = "re"

        let names = vm.items.map(\.name)
        #expect(names.contains("report.txt"))
        #expect(names.contains("readme.md"))
        #expect(!names.contains("data.csv"))
    }

    @Test func searchTextCaseInsensitive() async throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }
        _ = try TestHelpers.createFile("file.txt", in: dir)

        let vm = DirectoryViewModel()
        await vm.loadDirectory(url: dir)
        vm.searchText = "TXT"

        #expect(vm.items.count == 1)
        #expect(vm.items.first?.name == "file.txt")
    }

    @Test func clearSearchTextShowsAll() async throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }
        _ = try TestHelpers.createFile("alpha.txt", in: dir)
        _ = try TestHelpers.createFile("beta.txt", in: dir)

        let vm = DirectoryViewModel()
        await vm.loadDirectory(url: dir)
        vm.searchText = "alpha"
        #expect(vm.items.count == 1)

        vm.searchText = ""
        #expect(vm.items.count == 2)
    }

    @Test func combinedFilterSortSearch() async throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }
        _ = try TestHelpers.createFile("apple.txt", in: dir)
        _ = try TestHelpers.createFile("avocado.txt", in: dir)
        _ = try TestHelpers.createFile(".apricot", in: dir)
        _ = try TestHelpers.createFile("banana.txt", in: dir)

        let vm = DirectoryViewModel()
        await vm.loadDirectory(url: dir)
        // showHidden defaults to false — .apricot is filtered
        vm.searchText = "a"
        vm.sort(by: FileSortDescriptor(field: .name, order: .descending))

        let names = vm.items.map(\.name)
        // All visible files contain "a": banana, avocado, apple — sorted descending
        #expect(names == ["banana.txt", "avocado.txt", "apple.txt"])
    }

    // MARK: - Selection

    @Test func selectAllSelectsVisibleItems() async throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }
        _ = try TestHelpers.createFile("a.txt", in: dir)
        _ = try TestHelpers.createFile("b.txt", in: dir)
        _ = try TestHelpers.createFile(".hidden", in: dir)

        let vm = DirectoryViewModel()
        await vm.loadDirectory(url: dir)
        // showHidden defaults to false — 2 visible items

        vm.selectAll()
        #expect(vm.selectedItems.count == vm.items.count)
        #expect(vm.selectedItems.count == 2)
    }

    @Test func clearSelectionEmptiesSet() async throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }
        _ = try TestHelpers.createFile("a.txt", in: dir)

        let vm = DirectoryViewModel()
        await vm.loadDirectory(url: dir)
        vm.selectAll()
        #expect(!vm.selectedItems.isEmpty)

        vm.clearSelection()
        #expect(vm.selectedItems.isEmpty)
    }

    @Test func selectedURLsMapsCorrectly() async throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }
        _ = try TestHelpers.createFile("a.txt", in: dir)
        _ = try TestHelpers.createFile("b.txt", in: dir)

        let vm = DirectoryViewModel()
        await vm.loadDirectory(url: dir)

        let item = vm.items.first { $0.name == "a.txt" }!
        vm.selectedItems = [item.id]

        let urls = vm.selectedURLs
        #expect(urls.count == 1)
        #expect(urls.first == item.url)
    }

    @Test func inspectedItemReturnsFirstSelected() async throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }
        _ = try TestHelpers.createFile("a.txt", in: dir)

        let vm = DirectoryViewModel()
        await vm.loadDirectory(url: dir)

        let item = vm.items.first!
        vm.selectedItems = [item.id]

        #expect(vm.inspectedItem?.id == item.id)
    }

    @Test func inspectedItemNilWhenNoSelection() {
        let vm = DirectoryViewModel()
        #expect(vm.inspectedItem == nil)
    }

    // MARK: - View Mode

    @Test func viewModeDefaultIsList() {
        let vm = DirectoryViewModel()
        #expect(vm.viewMode == .list)
    }

    // MARK: - Counts

    @Test func itemCountMatchesItemsCount() async throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }
        _ = try TestHelpers.createFile("a.txt", in: dir)
        _ = try TestHelpers.createFile("b.txt", in: dir)

        let vm = DirectoryViewModel()
        await vm.loadDirectory(url: dir)

        #expect(vm.itemCount == vm.items.count)
        #expect(vm.itemCount == 2)
    }

    @Test func selectedCountMatchesSelectionCount() async throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }
        _ = try TestHelpers.createFile("a.txt", in: dir)
        _ = try TestHelpers.createFile("b.txt", in: dir)

        let vm = DirectoryViewModel()
        await vm.loadDirectory(url: dir)
        vm.selectAll()

        #expect(vm.selectedCount == vm.selectedItems.count)
        #expect(vm.selectedCount == 2)
    }

    // MARK: - Watcher Integration

    @Test func watcherOnChangeTriggersReload() async throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }
        _ = try TestHelpers.createFile("initial.txt", in: dir)

        let watcher = DirectoryWatcher()
        let vm = DirectoryViewModel(watcher: watcher)
        await vm.loadDirectory(url: dir)
        #expect(vm.items.count == 1)

        // Add a new file and simulate watcher firing onChange (wired up by init)
        _ = try TestHelpers.createFile("added.txt", in: dir)
        watcher.onChange?()

        // Wait for the async reload Task to complete
        try await Task.sleep(for: .seconds(1))

        #expect(vm.items.contains { $0.name == "added.txt" })
        #expect(vm.items.count >= 2)
    }
}
