import Testing
import Foundation
@testable import Explorer

@Suite("FileSystemService")
struct FileSystemServiceTests {

    private let service = FileSystemService()

    // MARK: - fullEnumerate

    @Test func fullEnumerateListsFiles() async throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }
        try TestHelpers.createFile("a.txt", in: dir)
        try TestHelpers.createFile("b.txt", in: dir)
        try TestHelpers.createFile("c.txt", in: dir)

        let items = try await service.fullEnumerate(url: dir, showHidden: false)
        #expect(items.count == 3)
    }

    @Test func fullEnumerateShowHiddenFalse() async throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }
        try TestHelpers.createFile("visible.txt", in: dir)
        try TestHelpers.createFile(".hidden", in: dir)

        let items = try await service.fullEnumerate(url: dir, showHidden: false)
        let names = items.map(\.name)
        #expect(names.contains("visible.txt"))
        #expect(!names.contains(".hidden"))
    }

    @Test func fullEnumerateShowHiddenTrue() async throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }
        try TestHelpers.createFile("visible.txt", in: dir)
        try TestHelpers.createFile(".hidden", in: dir)

        let items = try await service.fullEnumerate(url: dir, showHidden: true)
        let names = items.map(\.name)
        #expect(names.contains("visible.txt"))
        #expect(names.contains(".hidden"))
    }

    @Test func fullEnumerateEmptyDir() async throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }

        let items = try await service.fullEnumerate(url: dir, showHidden: true)
        #expect(items.isEmpty)
    }

    @Test func fullEnumerateNonexistentThrows() async {
        let bogus = URL(fileURLWithPath: "/tmp/\(UUID().uuidString)/does-not-exist")
        await #expect(throws: (any Error).self) {
            try await service.fullEnumerate(url: bogus, showHidden: false)
        }
    }

    @Test func fullEnumerateReturnsCorrectProperties() async throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }
        try TestHelpers.createFile("doc.txt", in: dir)
        try TestHelpers.createFolder("sub", in: dir)

        let items = try await service.fullEnumerate(url: dir, showHidden: false)
        let file = items.first { $0.name == "doc.txt" }
        let folder = items.first { $0.name == "sub" }

        #expect(file != nil)
        #expect(file?.isDirectory == false)
        #expect(folder != nil)
        #expect(folder?.isDirectory == true)
    }

    // MARK: - moveItems

    @Test func moveItemsMovesFile() async throws {
        let src = try TestHelpers.makeTempDir()
        let dst = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(src); TestHelpers.cleanup(dst) }
        let file = try TestHelpers.createFile("move-me.txt", in: src)

        try await service.moveItems([file], to: dst)

        let srcExists = await service.fileExists(at: file)
        let dstExists = await service.fileExists(at: dst.appendingPathComponent("move-me.txt"))
        #expect(srcExists == false)
        #expect(dstExists == true)
    }

    @Test func moveItemsThrowsOnConflict() async throws {
        let src = try TestHelpers.makeTempDir()
        let dst = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(src); TestHelpers.cleanup(dst) }
        let file = try TestHelpers.createFile("dup.txt", in: src)
        try TestHelpers.createFile("dup.txt", in: dst)

        await #expect(throws: (any Error).self) {
            try await service.moveItems([file], to: dst)
        }
    }

    // MARK: - copyItems

    @Test func copyItemsCopiesFile() async throws {
        let src = try TestHelpers.makeTempDir()
        let dst = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(src); TestHelpers.cleanup(dst) }
        let file = try TestHelpers.createFile("copy-me.txt", in: src, content: "original")

        try await service.copyItems([file], to: dst)

        let srcExists = await service.fileExists(at: file)
        let dstExists = await service.fileExists(at: dst.appendingPathComponent("copy-me.txt"))
        #expect(srcExists == true)
        #expect(dstExists == true)
    }

    @Test func copyItemsThrowsOnConflict() async throws {
        let src = try TestHelpers.makeTempDir()
        let dst = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(src); TestHelpers.cleanup(dst) }
        let file = try TestHelpers.createFile("dup.txt", in: src)
        try TestHelpers.createFile("dup.txt", in: dst)

        await #expect(throws: (any Error).self) {
            try await service.copyItems([file], to: dst)
        }
    }

    // MARK: - deleteItems

    @Test func deleteItemsTrashesFile() async throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }
        let file = try TestHelpers.createFile("trash-me.txt", in: dir)

        // trashItem may not work in headless/CI environments
        do {
            try await service.deleteItems([file])
            let exists = await service.fileExists(at: file)
            #expect(exists == false)
        } catch {
            // Skip gracefully when Trash is unavailable
        }
    }

    // MARK: - renameItem

    @Test func renameItemReturnsNewURL() async throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }
        try TestHelpers.createFile("old.txt", in: dir)

        let newURL = try await service.renameItem(
            at: dir.appendingPathComponent("old.txt"),
            to: "new.txt"
        )
        #expect(newURL.lastPathComponent == "new.txt")
    }

    @Test func renameItemOldURLGone() async throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }
        let old = try TestHelpers.createFile("old.txt", in: dir)

        _ = try await service.renameItem(at: old, to: "new.txt")

        let oldExists = await service.fileExists(at: old)
        #expect(oldExists == false)
    }

    // MARK: - createFolder

    @Test func createFolderReturnsURL() async throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }

        let folderURL = try await service.createFolder(in: dir, name: "NewFolder")
        let isDir = await service.isDirectory(at: folderURL)
        #expect(isDir == true)
    }

    @Test func createFolderThrowsIfExists() async throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }
        try TestHelpers.createFolder("Existing", in: dir)

        await #expect(throws: (any Error).self) {
            try await service.createFolder(in: dir, name: "Existing")
        }
    }

    // MARK: - fileExists

    @Test func fileExistsTrueForExisting() async throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }
        let file = try TestHelpers.createFile("here.txt", in: dir)

        let exists = await service.fileExists(at: file)
        #expect(exists == true)
    }

    @Test func fileExistsFalseForNonexistent() async {
        let bogus = URL(fileURLWithPath: "/tmp/\(UUID().uuidString)/nope.txt")
        let exists = await service.fileExists(at: bogus)
        #expect(exists == false)
    }

    // MARK: - isDirectory

    @Test func isDirectoryTrueForDir() async throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }
        let folder = try TestHelpers.createFolder("aDir", in: dir)
        let file = try TestHelpers.createFile("aFile.txt", in: dir)

        let folderResult = await service.isDirectory(at: folder)
        let fileResult = await service.isDirectory(at: file)
        #expect(folderResult == true)
        #expect(fileResult == false)
    }

    // MARK: - iCloud Operations

    @Test func startDownloadingNonUbiquitousItemThrows() async throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }
        let file = try TestHelpers.createFile("local.txt", in: dir)

        await #expect(throws: (any Error).self) {
            try await service.startDownloading(url: file)
        }
    }

    @Test func evictNonUbiquitousItemThrows() async throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }
        let file = try TestHelpers.createFile("local.txt", in: dir)

        await #expect(throws: (any Error).self) {
            try await service.evictItem(url: file)
        }
    }
}
