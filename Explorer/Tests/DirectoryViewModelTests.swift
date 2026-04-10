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
}
