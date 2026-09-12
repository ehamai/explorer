import Testing
import Foundation
@testable import Explorer

@Suite("DirectoryViewModel loading state")
@MainActor
struct DirectoryViewModelTests {

    // MARK: - Helpers

    private func makeTempDir() throws -> URL {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Tests/
            .deletingLastPathComponent() // Explorer/
            .deletingLastPathComponent() // project root
        let testTmpRoot = projectRoot.appendingPathComponent(".test-tmp")
        try FileManager.default.createDirectory(at: testTmpRoot, withIntermediateDirectories: true)
        let dir = testTmpRoot.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func createFile(_ name: String, in dir: URL) throws -> URL {
        let file = dir.appendingPathComponent(name)
        try "test".write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Tests

    @Test func isLoadingFalseAfterLoadDirectory() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        _ = try createFile("a.txt", in: dir)

        let vm = DirectoryViewModel()
        #expect(vm.isLoading == false, "Should start not loading")

        await vm.loadDirectory(url: dir)

        #expect(vm.isLoading == false, "isLoading must be false after loadDirectory completes")
        #expect(vm.items.count == 1)
    }

    @Test func isLoadingFalseAfterReloadCurrentDirectory() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        _ = try createFile("a.txt", in: dir)

        let vm = DirectoryViewModel()
        await vm.loadDirectory(url: dir)
        #expect(vm.isLoading == false)

        // Add a second file and reload
        _ = try createFile("b.txt", in: dir)
        await vm.reloadCurrentDirectory()

        #expect(vm.isLoading == false, "isLoading must remain false after reloadCurrentDirectory")
        #expect(vm.items.count == 2)
    }

    @Test func isLoadingFalseAfterConcurrentLoadAndReload() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        _ = try createFile("a.txt", in: dir)

        let vm = DirectoryViewModel()

        // Simulate the race: fire loadDirectory and reloadCurrentDirectory concurrently
        // With @MainActor, these serialize on the main actor — no data race
        await vm.loadDirectory(url: dir)

        async let load: Void = vm.loadDirectory(url: dir)
        async let reload: Void = vm.reloadCurrentDirectory()
        await load
        await reload

        #expect(vm.isLoading == false,
                "isLoading must be false after concurrent load + reload")
    }

    @Test func isLoadingFalseAfterMultipleConcurrentLoads() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        _ = try createFile("a.txt", in: dir)

        let vm = DirectoryViewModel()
        await vm.loadDirectory(url: dir)

        // Fire several loads concurrently
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<5 {
                group.addTask { await vm.loadDirectory(url: dir) }
            }
        }

        #expect(vm.isLoading == false,
                "isLoading must be false after multiple concurrent loadDirectory calls")
        #expect(!vm.items.isEmpty)
    }

    @Test func loadDirectoryForNonexistentDirSetsLoadingFalse() async throws {
        let vm = DirectoryViewModel()
        let bogus = URL(fileURLWithPath: "/nonexistent-dir-\(UUID().uuidString)")

        await vm.loadDirectory(url: bogus)

        #expect(vm.isLoading == false,
                "isLoading must be false even when directory doesn't exist")
        #expect(vm.items.isEmpty)
    }

    @Test func loadDirectoryClearsSelection() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        let file = try createFile("a.txt", in: dir)

        let vm = DirectoryViewModel()
        await vm.loadDirectory(url: dir)

        let fileItem = vm.items.first { $0.name == "a.txt" }!
        vm.selectedItems = [fileItem.id]
        #expect(vm.selectedItems.count == 1)

        await vm.loadDirectory(url: dir)
        #expect(vm.selectedItems.count == 1, "loadDirectory should auto-select first item")

        // Set a different selection, then reload — should reset to first item
        vm.selectedItems = [vm.items.last!.id]
        await vm.loadDirectory(url: dir)
        #expect(vm.selectedItems.count == 1, "loadDirectory should reset selection to first item")
    }

    @Test func reloadCurrentDirectoryPreservesSelection() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        _ = try createFile("a.txt", in: dir)

        let vm = DirectoryViewModel()
        await vm.loadDirectory(url: dir)

        let fileItem = vm.items.first { $0.name == "a.txt" }!
        vm.selectedItems = [fileItem.id]

        await vm.reloadCurrentDirectory()
        #expect(vm.selectedItems.count == 1,
                "reloadCurrentDirectory should preserve selection")
    }

    @Test func mosaicZoomClampedToRange() {
        let vm = DirectoryViewModel()
        vm.mosaicZoom = 50
        #expect(vm.mosaicZoom == DirectoryViewModel.mosaicZoomRange.lowerBound)
        vm.mosaicZoom = 999
        #expect(vm.mosaicZoom == DirectoryViewModel.mosaicZoomRange.upperBound)
    }

    @Test func mosaicZoomDefaultIs200() {
        let vm = DirectoryViewModel()
        #expect(vm.mosaicZoom == 200)
    }

    // MARK: - Mosaic Layout

    @Test func recomputeMosaicRowsRequiresMosaicMode() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        _ = try createFile("image.png", in: dir)

        let vm = DirectoryViewModel()
        await vm.loadDirectory(url: dir)

        vm.containerWidth = 800
        vm.viewMode = .list
        #expect(vm.mosaicRows.isEmpty, "Rows should be empty in list mode")

        vm.viewMode = .mosaic
        #expect(!vm.mosaicRows.isEmpty, "Rows should be computed in mosaic mode")
    }

    @Test func recomputeMosaicRowsRequiresContainerWidth() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        _ = try createFile("image.png", in: dir)

        let vm = DirectoryViewModel()
        await vm.loadDirectory(url: dir)

        vm.viewMode = .mosaic
        vm.containerWidth = 0
        #expect(vm.mosaicRows.isEmpty, "Rows should be empty with zero container width")

        vm.containerWidth = 500
        #expect(!vm.mosaicRows.isEmpty, "Rows should be computed with positive container width")
    }

    @Test func setAspectRatioUpdatesDict() {
        let vm = DirectoryViewModel()
        let url = URL(fileURLWithPath: "/tmp/test.png")

        vm.setAspectRatio(1.5, for: url)
        #expect(vm.aspectRatios[url] == 1.5)
    }

    @Test func mosaicZoomAffectsRowHeight() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        for i in 0..<5 {
            _ = try createFile("file\(i).txt", in: dir)
        }

        let vm = DirectoryViewModel()
        await vm.loadDirectory(url: dir)
        vm.viewMode = .mosaic
        vm.containerWidth = 800
        vm.mosaicZoom = 150

        let smallRows = vm.mosaicRows
        vm.mosaicZoom = 400

        let bigRows = vm.mosaicRows
        // With larger zoom (target height), we expect fewer items per row
        #expect(bigRows.count >= smallRows.count,
                "Larger zoom should produce at least as many rows (fewer items per row)")
    }

    // MARK: - Mosaic Navigation

    @Test func navigateMosaicNoRowsIsNoOp() {
        let vm = DirectoryViewModel()
        vm.navigateMosaicSelection(direction: .right)
        #expect(vm.selectedItems.isEmpty)
    }

    @Test func navigateMosaicNoSelectionSelectsFirst() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        _ = try createFile("a.txt", in: dir)
        _ = try createFile("b.txt", in: dir)

        let vm = DirectoryViewModel()
        await vm.loadDirectory(url: dir)
        vm.viewMode = .mosaic
        vm.containerWidth = 800

        vm.selectedItems.removeAll()
        vm.navigateMosaicSelection(direction: .right)
        #expect(vm.selectedItems.count == 1, "Should select first item when nothing selected")
    }

    @Test func navigateMosaicRightMovesToNextItem() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        _ = try createFile("a.txt", in: dir)
        _ = try createFile("b.txt", in: dir)
        _ = try createFile("c.txt", in: dir)

        let vm = DirectoryViewModel()
        await vm.loadDirectory(url: dir)
        vm.viewMode = .mosaic
        vm.containerWidth = 800

        let firstID = vm.mosaicRows.first!.items.first!.id
        vm.selectedItems = [firstID]

        vm.navigateMosaicSelection(direction: .right)
        #expect(vm.selectedItems.count == 1)
        #expect(vm.selectedItems.first != firstID, "Should move to next item")
    }

    @Test func navigateMosaicLeftAtStartIsNoOp() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        _ = try createFile("a.txt", in: dir)
        _ = try createFile("b.txt", in: dir)

        let vm = DirectoryViewModel()
        await vm.loadDirectory(url: dir)
        vm.viewMode = .mosaic
        vm.containerWidth = 800

        let firstID = vm.mosaicRows.first!.items.first!.id
        vm.selectedItems = [firstID]

        vm.navigateMosaicSelection(direction: .left)
        #expect(vm.selectedItems.first == firstID, "Should stay at first item")
    }

    @Test func navigateMosaicUpAtFirstRowIsNoOp() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        _ = try createFile("a.txt", in: dir)

        let vm = DirectoryViewModel()
        await vm.loadDirectory(url: dir)
        vm.viewMode = .mosaic
        vm.containerWidth = 800

        let firstID = vm.mosaicRows.first!.items.first!.id
        vm.selectedItems = [firstID]

        vm.navigateMosaicSelection(direction: .up)
        #expect(vm.selectedItems.first == firstID, "Should stay at first item on up at first row")
    }

    @Test func navigateMosaicDownMovesToNextRow() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        // Create enough files to span multiple rows with small container
        for i in 0..<10 {
            _ = try createFile("file\(i).txt", in: dir)
        }

        let vm = DirectoryViewModel()
        await vm.loadDirectory(url: dir)
        vm.viewMode = .mosaic
        vm.containerWidth = 300  // Small width to force multiple rows
        vm.mosaicZoom = 100

        guard vm.mosaicRows.count > 1 else { return }  // Need multiple rows

        let firstID = vm.mosaicRows[0].items[0].id
        vm.selectedItems = [firstID]

        vm.navigateMosaicSelection(direction: .down)
        let newID = vm.selectedItems.first
        #expect(newID != firstID, "Should move to next row")

        // Verify the new selection is in the second row
        let isInSecondRow = vm.mosaicRows[1].items.contains { $0.id == newID }
        #expect(isInSecondRow, "New selection should be in second row")
    }

    // MARK: - Grid Keyboard Navigation

    @Test @MainActor func navigateGridNoItemsIsNoOp() {
        let vm = DirectoryViewModel()
        vm.navigateGridSelection(direction: .right, columnCount: 3)
        #expect(vm.selectedItems.isEmpty)
    }

    @Test @MainActor func navigateGridNoSelectionSelectsFirst() async throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }
        _ = try TestHelpers.createFile("a.txt", in: dir)
        _ = try TestHelpers.createFile("b.txt", in: dir)

        let vm = DirectoryViewModel()
        await vm.loadDirectory(url: dir)
        vm.selectedItems.removeAll()

        vm.navigateGridSelection(direction: .right, columnCount: 3)
        #expect(vm.selectedItems.count == 1)
        #expect(vm.selectedItems.first == vm.items.first?.id)
    }

    @Test @MainActor func navigateGridRightMovesToNext() async throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }
        _ = try TestHelpers.createFile("a.txt", in: dir)
        _ = try TestHelpers.createFile("b.txt", in: dir)
        _ = try TestHelpers.createFile("c.txt", in: dir)

        let vm = DirectoryViewModel()
        await vm.loadDirectory(url: dir)

        vm.selectedItems = [vm.items[0].id]
        vm.navigateGridSelection(direction: .right, columnCount: 3)
        #expect(vm.selectedItems.first == vm.items[1].id)
    }

    @Test @MainActor func navigateGridLeftAtStartIsNoOp() async throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }
        _ = try TestHelpers.createFile("a.txt", in: dir)

        let vm = DirectoryViewModel()
        await vm.loadDirectory(url: dir)

        let firstID = vm.items[0].id
        vm.selectedItems = [firstID]
        vm.navigateGridSelection(direction: .left, columnCount: 3)
        #expect(vm.selectedItems.first == firstID)
    }

    @Test @MainActor func navigateGridDownMovesToNextRow() async throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }
        for i in 0..<6 {
            _ = try TestHelpers.createFile("file\(i).txt", in: dir)
        }

        let vm = DirectoryViewModel()
        await vm.loadDirectory(url: dir)

        // Select first item, navigate down with 3 columns → should jump to index 3
        vm.selectedItems = [vm.items[0].id]
        vm.navigateGridSelection(direction: .down, columnCount: 3)
        #expect(vm.selectedItems.first == vm.items[3].id)
    }

    @Test @MainActor func navigateGridUpMovesToPreviousRow() async throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }
        for i in 0..<6 {
            _ = try TestHelpers.createFile("file\(i).txt", in: dir)
        }

        let vm = DirectoryViewModel()
        await vm.loadDirectory(url: dir)

        // Select item at index 3, navigate up with 3 columns → should jump to index 0
        vm.selectedItems = [vm.items[3].id]
        vm.navigateGridSelection(direction: .up, columnCount: 3)
        #expect(vm.selectedItems.first == vm.items[0].id)
    }

    @Test @MainActor func navigateGridDownBeyondEndIsNoOp() async throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }
        _ = try TestHelpers.createFile("a.txt", in: dir)
        _ = try TestHelpers.createFile("b.txt", in: dir)

        let vm = DirectoryViewModel()
        await vm.loadDirectory(url: dir)

        let lastID = vm.items.last!.id
        vm.selectedItems = [lastID]
        vm.navigateGridSelection(direction: .down, columnCount: 3)
        #expect(vm.selectedItems.first == lastID)
    }
}

@Suite("DirectoryViewModel drag & click selection")
@MainActor
struct DirectoryViewModelDragSelectionTests {

    private func loadedVM(fileCount: Int) async throws -> (DirectoryViewModel, URL) {
        let dir = try TestHelpers.makeTempDir()
        for i in 0..<fileCount {
            try TestHelpers.createFile("file\(i).txt", in: dir)
        }
        let vm = DirectoryViewModel()
        await vm.loadDirectory(url: dir)
        return (vm, dir)
    }

    @Test func dragURLsReturnsWholeSelectionWhenItemIsSelected() async throws {
        let (vm, dir) = try await loadedVM(fileCount: 3)
        defer { TestHelpers.cleanup(dir) }

        vm.selectedItems = [vm.items[0].id, vm.items[2].id]
        let urls = vm.dragURLs(for: vm.items[2])
        #expect(Set(urls) == [vm.items[0].url, vm.items[2].url])
    }

    @Test func dragURLsReturnsOnlyItemWhenNotSelected() async throws {
        let (vm, dir) = try await loadedVM(fileCount: 3)
        defer { TestHelpers.cleanup(dir) }

        vm.selectedItems = [vm.items[0].id, vm.items[2].id]
        #expect(vm.dragURLs(for: vm.items[1]) == [vm.items[1].url])
    }

    @Test func mouseDownOnUnselectedItemSelectsOnlyIt() async throws {
        let (vm, dir) = try await loadedVM(fileCount: 3)
        defer { TestHelpers.cleanup(dir) }

        vm.selectedItems = [vm.items[0].id, vm.items[2].id]
        vm.handleMouseDown(on: vm.items[1].id, command: false, shift: false)
        #expect(vm.selectedItems == [vm.items[1].id])
    }

    @Test func mouseDownOnSelectedItemKeepsSelectionForDrag() async throws {
        let (vm, dir) = try await loadedVM(fileCount: 3)
        defer { TestHelpers.cleanup(dir) }

        vm.selectedItems = [vm.items[0].id, vm.items[2].id]
        vm.handleMouseDown(on: vm.items[2].id, command: false, shift: false)
        #expect(vm.selectedItems == [vm.items[0].id, vm.items[2].id])
    }

    @Test func commandMouseDownTogglesItem() async throws {
        let (vm, dir) = try await loadedVM(fileCount: 3)
        defer { TestHelpers.cleanup(dir) }

        vm.selectedItems = [vm.items[0].id]
        vm.handleMouseDown(on: vm.items[1].id, command: true, shift: false)
        #expect(vm.selectedItems == [vm.items[0].id, vm.items[1].id])

        vm.handleMouseDown(on: vm.items[0].id, command: true, shift: false)
        #expect(vm.selectedItems == [vm.items[1].id])
    }

    @Test func plainClickNarrowsMultiSelection() async throws {
        let (vm, dir) = try await loadedVM(fileCount: 3)
        defer { TestHelpers.cleanup(dir) }

        vm.selectedItems = [vm.items[0].id, vm.items[2].id]
        vm.handleClick(on: vm.items[2].id, command: false, shift: false)
        #expect(vm.selectedItems == [vm.items[2].id])
    }

    @Test func commandClickLeavesSelectionUnchanged() async throws {
        let (vm, dir) = try await loadedVM(fileCount: 3)
        defer { TestHelpers.cleanup(dir) }

        vm.selectedItems = [vm.items[0].id, vm.items[2].id]
        vm.handleClick(on: vm.items[2].id, command: true, shift: false)
        #expect(vm.selectedItems == [vm.items[0].id, vm.items[2].id])
    }
    // MARK: - Shift-click range

    @Test func shiftClickSelectsRangeForward() async throws {
        let (vm, dir) = try await loadedVM(fileCount: 5)
        defer { TestHelpers.cleanup(dir) }

        vm.handleMouseDown(on: vm.items[1].id, command: false, shift: false)
        vm.handleMouseDown(on: vm.items[3].id, command: false, shift: true)
        #expect(vm.selectedItems == Set(vm.items[1...3].map(\.id)))
    }

    @Test func shiftClickSelectsRangeBackward() async throws {
        let (vm, dir) = try await loadedVM(fileCount: 5)
        defer { TestHelpers.cleanup(dir) }

        vm.handleMouseDown(on: vm.items[3].id, command: false, shift: false)
        vm.handleMouseDown(on: vm.items[0].id, command: false, shift: true)
        #expect(vm.selectedItems == Set(vm.items[0...3].map(\.id)))
        #expect(vm.selectionAnchor == vm.items[3].id)
    }

    @Test func commandShiftClickAddsRange() async throws {
        let (vm, dir) = try await loadedVM(fileCount: 6)
        defer { TestHelpers.cleanup(dir) }

        vm.handleMouseDown(on: vm.items[0].id, command: false, shift: false)
        vm.handleMouseDown(on: vm.items[4].id, command: true, shift: false)
        vm.handleMouseDown(on: vm.items[5].id, command: true, shift: true)
        #expect(vm.selectedItems == [vm.items[0].id, vm.items[4].id, vm.items[5].id])
    }

    @Test func shiftClickWithoutAnchorSelectsOnlyItem() async throws {
        let (vm, dir) = try await loadedVM(fileCount: 3)
        defer { TestHelpers.cleanup(dir) }

        vm.clearSelection()
        #expect(vm.selectionAnchor == nil)
        vm.handleMouseDown(on: vm.items[2].id, command: false, shift: true)
        #expect(vm.selectedItems == [vm.items[2].id])
    }

    @Test func commandClickAddedItemBecomesAnchor() async throws {
        let (vm, dir) = try await loadedVM(fileCount: 6)
        defer { TestHelpers.cleanup(dir) }

        vm.handleMouseDown(on: vm.items[0].id, command: false, shift: false)
        vm.handleMouseDown(on: vm.items[3].id, command: true, shift: false)
        vm.handleMouseDown(on: vm.items[5].id, command: false, shift: true)
        #expect(vm.selectedItems == Set(vm.items[3...5].map(\.id)))
    }

    @Test func shiftClickUpLeavesSelectionUnchanged() async throws {
        let (vm, dir) = try await loadedVM(fileCount: 5)
        defer { TestHelpers.cleanup(dir) }

        vm.handleMouseDown(on: vm.items[1].id, command: false, shift: false)
        vm.handleMouseDown(on: vm.items[3].id, command: false, shift: true)
        vm.handleClick(on: vm.items[3].id, command: false, shift: true)
        #expect(vm.selectedItems == Set(vm.items[1...3].map(\.id)))
    }

    @Test func arrowKeySelectionSetsAnchor() async throws {
        let (vm, dir) = try await loadedVM(fileCount: 6)
        defer { TestHelpers.cleanup(dir) }

        vm.selectedItems = [vm.items[0].id]
        vm.navigateGridSelection(direction: .right, columnCount: 3)
        #expect(vm.selectionAnchor == vm.items[1].id)
    }
}
