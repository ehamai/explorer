import Foundation
@testable import Explorer

enum TestHelpers {

    /// Create a unique temp directory under `.test-tmp/` at the project root.
    static func makeTempDir() throws -> URL {
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

    /// Create a file with the given name and optional content inside `dir`.
    @discardableResult
    static func createFile(_ name: String, in dir: URL, content: String = "test") throws -> URL {
        let file = dir.appendingPathComponent(name)
        try content.write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    /// Create a subfolder with the given name inside `dir`.
    @discardableResult
    static func createFolder(_ name: String, in dir: URL) throws -> URL {
        let folder = dir.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Remove a temp directory and all its contents.
    static func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// Build a synthetic `FileItem` for unit tests that don't need real files.
    static func makeFileItem(
        name: String,
        isDirectory: Bool = false,
        isHidden: Bool = false,
        size: Int64 = 0,
        dateModified: Date = Date(),
        kind: String = "Document",
        basePath: URL = URL(fileURLWithPath: "/tmp")
    ) -> FileItem {
        let url = basePath.appendingPathComponent(name)
        return FileItem(
            url: url,
            name: name,
            size: size,
            dateModified: dateModified,
            kind: kind,
            isDirectory: isDirectory,
            isHidden: isHidden,
            isPackage: false
        )
    }
}
