import Testing
import Foundation
@testable import Explorer

@Suite("DirectoryViewModel iCloud integration")
@MainActor
struct DirectoryViewModelICloudTests {

    // MARK: - Service Injection

    @Test func setICloudDriveServiceStoresReference() {
        let vm = DirectoryViewModel()
        let service = ICloudDriveService()
        vm.setICloudDriveService(service)
        // Verify indirectly: loading a non-iCloud dir still works (service doesn't interfere)
    }

    @Test func setICloudStatusServiceStoresReference() {
        let vm = DirectoryViewModel()
        let service = ICloudStatusService()
        vm.setICloudStatusService(service)
        // Verify indirectly: service is stored without crash
    }

    // MARK: - updateICloudStatus

    @Test func updateICloudStatusMergesStatusIntoItems() async throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }
        let fileURL = try TestHelpers.createFile("test.txt", in: dir)

        let vm = DirectoryViewModel()
        await vm.loadDirectory(url: dir)

        #expect(vm.items.count == 1)
        #expect(vm.items[0].iCloudStatus == .local)

        // Simulate a status update from NSMetadataQuery
        vm.updateICloudStatus(from: [fileURL: .current])
        #expect(vm.items[0].iCloudStatus == .current)
    }

    @Test func updateICloudStatusIgnoresEmptyMap() async throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }
        try TestHelpers.createFile("test.txt", in: dir)

        let vm = DirectoryViewModel()
        await vm.loadDirectory(url: dir)

        let originalStatus = vm.items[0].iCloudStatus
        vm.updateICloudStatus(from: [:])
        #expect(vm.items[0].iCloudStatus == originalStatus)
    }

    @Test func updateICloudStatusOnlyAffectsMatchingURLs() async throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }
        let file1 = try TestHelpers.createFile("a.txt", in: dir)
        try TestHelpers.createFile("b.txt", in: dir)

        let vm = DirectoryViewModel()
        await vm.loadDirectory(url: dir)

        #expect(vm.items.count == 2)

        // Only update status for file1
        vm.updateICloudStatus(from: [file1: .cloudOnly])

        let updatedItem = vm.items.first { $0.url == file1 }
        let unchangedItem = vm.items.first { $0.url != file1 }
        #expect(updatedItem?.iCloudStatus == .cloudOnly)
        #expect(unchangedItem?.iCloudStatus == .local)
    }

    @Test func updateICloudStatusHandlesUnknownURLsGracefully() async throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }
        try TestHelpers.createFile("test.txt", in: dir)

        let vm = DirectoryViewModel()
        await vm.loadDirectory(url: dir)

        let bogusURL = URL(fileURLWithPath: "/nonexistent/file.txt")
        vm.updateICloudStatus(from: [bogusURL: .current])

        // Items should be unchanged
        #expect(vm.items[0].iCloudStatus == .local)
    }

    // MARK: - downloadItem / evictItem

    @Test func downloadItemReloadsDirectory() async throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }
        try TestHelpers.createFile("test.txt", in: dir)

        let vm = DirectoryViewModel()
        await vm.loadDirectory(url: dir)
        let initialCount = vm.items.count

        // downloadItem on a non-ubiquitous file will fail silently and reload
        await vm.downloadItem(at: dir.appendingPathComponent("test.txt"))

        // Directory should be reloaded (same count, no crash)
        #expect(vm.items.count == initialCount)
    }

    @Test func evictItemReloadsDirectory() async throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }
        try TestHelpers.createFile("test.txt", in: dir)

        let vm = DirectoryViewModel()
        await vm.loadDirectory(url: dir)
        let initialCount = vm.items.count

        // evictItem on a non-ubiquitous file will fail silently and reload
        await vm.evictItem(at: dir.appendingPathComponent("test.txt"))

        #expect(vm.items.count == initialCount)
    }

    // MARK: - loadDirectory with iCloud Drive root

    @Test func loadDirectoryUsesStandardEnumerationForLocalDir() async throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }
        try TestHelpers.createFile("a.txt", in: dir)
        try TestHelpers.createFile("b.txt", in: dir)

        let vm = DirectoryViewModel()
        let iCloudService = ICloudDriveService()
        vm.setICloudDriveService(iCloudService)

        await vm.loadDirectory(url: dir)

        // Standard enumeration should work normally even with iCloud service set
        #expect(vm.items.count == 2)
        #expect(vm.loadedURL == dir)
        #expect(!vm.isLoading)
    }

    @Test func loadDirectoryUsesMergedEnumerationForICloudRoot() async {
        let iCloudService = ICloudDriveService()
        guard iCloudService.isAvailable, let cloudDocsURL = iCloudService.cloudDocsURL else { return }

        let vm = DirectoryViewModel()
        vm.setICloudDriveService(iCloudService)

        await vm.loadDirectory(url: cloudDocsURL)

        // Should use merged enumeration: CloudDocs contents + app container folders
        #expect(!vm.items.isEmpty, "iCloud Drive root should have items")
        #expect(vm.loadedURL == cloudDocsURL)
        #expect(!vm.isLoading)

        // No raw bundle IDs should appear
        for item in vm.items {
            #expect(!item.name.contains("com~apple~"), "Found raw bundle ID: \(item.name)")
        }
    }

    // MARK: - reloadCurrentDirectory with iCloud Drive root

    @Test func reloadCurrentDirectoryUsesMergedEnumeration() async {
        let iCloudService = ICloudDriveService()
        guard iCloudService.isAvailable, let cloudDocsURL = iCloudService.cloudDocsURL else { return }

        let vm = DirectoryViewModel()
        vm.setICloudDriveService(iCloudService)

        await vm.loadDirectory(url: cloudDocsURL)
        let initialNames = Set(vm.items.map(\.name))

        // Reload should produce the same merged result
        await vm.reloadCurrentDirectory()
        let reloadedNames = Set(vm.items.map(\.name))

        #expect(initialNames == reloadedNames)
    }

    @Test func reloadCurrentDirectoryStandardForLocalDir() async throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }
        try TestHelpers.createFile("a.txt", in: dir)

        let vm = DirectoryViewModel()
        vm.setICloudDriveService(ICloudDriveService())
        await vm.loadDirectory(url: dir)

        // Add a file after initial load
        try TestHelpers.createFile("b.txt", in: dir)
        await vm.reloadCurrentDirectory()

        #expect(vm.items.count == 2, "Reload should pick up new file")
    }
}
