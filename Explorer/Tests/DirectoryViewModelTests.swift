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
        #expect(vm.selectedItems.isEmpty, "loadDirectory should clear selection")
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
}
