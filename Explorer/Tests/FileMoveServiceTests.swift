import Testing
import Foundation
@testable import Explorer

@Suite("FileMoveService")
struct FileMoveServiceTests {

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

    private func createFolder(_ name: String, in dir: URL) throws -> URL {
        let folder = dir.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Folder Drop Validation

    @Test func folderDropAcceptsFileFromDifferentDir() throws {
        let src = try makeTempDir()
        let dst = try makeTempDir()
        defer { cleanup(src); cleanup(dst) }

        let file = try createFile("report.pdf", in: src)
        let target = try createFolder("Projects", in: dst)

        let valid = FileMoveService.validURLsForFolderDrop([file], destination: target)
        #expect(valid.count == 1)
        #expect(valid[0] == file)
    }

    @Test func folderDropRejectsDestinationItself() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        let folder = try createFolder("Projects", in: dir)

        let valid = FileMoveService.validURLsForFolderDrop([folder], destination: folder)
        #expect(valid.isEmpty, "Should not allow dropping a folder into itself")
    }

    @Test func folderDropRejectsParentIntoSubtree() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        let parent = try createFolder("Parent", in: dir)
        let child = try createFolder("Child", in: parent)

        let valid = FileMoveService.validURLsForFolderDrop([parent], destination: child)
        #expect(valid.isEmpty, "Should not allow dropping a parent into its own subtree")
    }

    @Test func folderDropAllowsSiblingFolder() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        let folderA = try createFolder("FolderA", in: dir)
        let folderB = try createFolder("FolderB", in: dir)

        let valid = FileMoveService.validURLsForFolderDrop([folderA], destination: folderB)
        #expect(valid.count == 1, "Should allow dropping sibling folders")
    }

    // MARK: - Background Drop Validation

    @Test func backgroundDropRejectsFilesAlreadyInDestination() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        let file = try createFile("notes.txt", in: dir)

        let valid = FileMoveService.validURLsForBackgroundDrop([file], destination: dir)
        #expect(valid.isEmpty, "Should reject files already in the destination directory")
    }

    @Test func backgroundDropAcceptsFilesFromDifferentDir() throws {
        let src = try makeTempDir()
        let dst = try makeTempDir()
        defer { cleanup(src); cleanup(dst) }
        let file = try createFile("notes.txt", in: src)

        let valid = FileMoveService.validURLsForBackgroundDrop([file], destination: dst)
        #expect(valid.count == 1)
    }

    @Test func backgroundDropRejectsDestinationItself() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        let valid = FileMoveService.validURLsForBackgroundDrop([dir], destination: dir)
        #expect(valid.isEmpty)
    }

    @Test func backgroundDropRejectsParentIntoSubtree() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        let parent = try createFolder("Parent", in: dir)
        let child = try createFolder("Child", in: parent)

        let valid = FileMoveService.validURLsForBackgroundDrop([parent], destination: child)
        #expect(valid.isEmpty)
    }

    @Test func backgroundDropFiltersMixedURLs() throws {
        let src = try makeTempDir()
        let dst = try makeTempDir()
        defer { cleanup(src); cleanup(dst) }

        let externalFile = try createFile("external.txt", in: src)
        let localFile = try createFile("local.txt", in: dst)

        let valid = FileMoveService.validURLsForBackgroundDrop(
            [externalFile, localFile], destination: dst
        )
        #expect(valid.count == 1, "Should accept external file but reject local file")
        #expect(valid[0] == externalFile)
    }

    // MARK: - Move Execution

    @Test func moveItemsMovesFileToDestination() throws {
        let src = try makeTempDir()
        let dst = try makeTempDir()
        defer { cleanup(src); cleanup(dst) }

        let file = try createFile("report.pdf", in: src)
        let result = FileMoveService.moveItems([file], to: dst)

        #expect(result.movedCount == 1)
        #expect(!FileManager.default.fileExists(atPath: file.path), "Source file should be gone")
        #expect(FileManager.default.fileExists(atPath: dst.appendingPathComponent("report.pdf").path),
                "File should exist in destination")
    }

    @Test func moveItemsTracksSourceDirs() throws {
        let srcA = try makeTempDir()
        let srcB = try makeTempDir()
        let dst = try makeTempDir()
        defer { cleanup(srcA); cleanup(srcB); cleanup(dst) }

        let fileA = try createFile("a.txt", in: srcA)
        let fileB = try createFile("b.txt", in: srcB)

        let result = FileMoveService.moveItems([fileA, fileB], to: dst)
        #expect(result.movedCount == 2)
        #expect(result.sourceDirs.count == 2, "Should track both source directories")
    }

    @Test func moveItemsHandlesNameConflictGracefully() throws {
        let src = try makeTempDir()
        let dst = try makeTempDir()
        defer { cleanup(src); cleanup(dst) }

        let file = try createFile("conflict.txt", in: src)
        _ = try createFile("conflict.txt", in: dst) // pre-existing file with same name

        let result = FileMoveService.moveItems([file], to: dst)
        #expect(result.movedCount == 0, "Should fail gracefully on name conflict")
        #expect(FileManager.default.fileExists(atPath: file.path), "Source should still exist")
    }
}
