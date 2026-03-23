import Testing
import Foundation
@testable import Explorer

@Suite("ClipboardManager paste operations")
@MainActor
struct ClipboardManagerTests {

    // MARK: - Paste cut

    @Test func pasteCutMovesFiles() async throws {
        let src = try TestHelpers.makeTempDir()
        let dst = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(src); TestHelpers.cleanup(dst) }
        let file = try TestHelpers.createFile("cut.txt", in: src)

        let cm = ClipboardManager()
        cm.cut(urls: [file])
        _ = try await cm.paste(to: dst)

        let srcExists = FileManager.default.fileExists(atPath: file.path)
        let dstExists = FileManager.default.fileExists(
            atPath: dst.appendingPathComponent("cut.txt").path
        )
        #expect(srcExists == false)
        #expect(dstExists == true)
    }

    @Test func pasteCutReturnsSourceDir() async throws {
        let src = try TestHelpers.makeTempDir()
        let dst = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(src); TestHelpers.cleanup(dst) }
        let file = try TestHelpers.createFile("cut2.txt", in: src)

        let cm = ClipboardManager()
        cm.cut(urls: [file])
        let result = try await cm.paste(to: dst)

        // deletingLastPathComponent adds trailing slash; compare paths
        #expect(result?.path == src.path)
    }

    @Test func pasteCutClearsState() async throws {
        let src = try TestHelpers.makeTempDir()
        let dst = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(src); TestHelpers.cleanup(dst) }
        let file = try TestHelpers.createFile("cut3.txt", in: src)

        let cm = ClipboardManager()
        cm.cut(urls: [file])
        _ = try await cm.paste(to: dst)

        #expect(cm.operation == .idle)
        #expect(cm.sourceURLs.isEmpty)
        #expect(cm.hasPendingOperation == false)
    }

    // MARK: - Paste copy

    @Test func pasteCopyLeavesSource() async throws {
        let src = try TestHelpers.makeTempDir()
        let dst = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(src); TestHelpers.cleanup(dst) }
        let file = try TestHelpers.createFile("copy.txt", in: src)

        let cm = ClipboardManager()
        cm.copy(urls: [file])
        _ = try await cm.paste(to: dst)

        let srcExists = FileManager.default.fileExists(atPath: file.path)
        let dstExists = FileManager.default.fileExists(
            atPath: dst.appendingPathComponent("copy.txt").path
        )
        #expect(srcExists == true)
        #expect(dstExists == true)
    }

    @Test func pasteCopyReturnsNil() async throws {
        let src = try TestHelpers.makeTempDir()
        let dst = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(src); TestHelpers.cleanup(dst) }
        let file = try TestHelpers.createFile("copy2.txt", in: src)

        let cm = ClipboardManager()
        cm.copy(urls: [file])
        let result = try await cm.paste(to: dst)

        #expect(result == nil)
    }

    // MARK: - Idle paste

    @Test func pasteIdleReturnsNil() async throws {
        let dst = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dst) }

        let cm = ClipboardManager()
        let result = try await cm.paste(to: dst)
        #expect(result == nil)
    }

    // MARK: - Notifications

    @Test func cutPostsNotification() throws {
        let cm = ClipboardManager()
        var received = false
        let token = NotificationCenter.default.addObserver(
            forName: .clipboardStateChanged, object: cm, queue: nil
        ) { _ in received = true }
        defer { NotificationCenter.default.removeObserver(token) }

        cm.cut(urls: [URL(fileURLWithPath: "/tmp/a.txt")])
        #expect(received == true)
    }

    @Test func copyPostsNotification() throws {
        let cm = ClipboardManager()
        var received = false
        let token = NotificationCenter.default.addObserver(
            forName: .clipboardStateChanged, object: cm, queue: nil
        ) { _ in received = true }
        defer { NotificationCenter.default.removeObserver(token) }

        cm.copy(urls: [URL(fileURLWithPath: "/tmp/a.txt")])
        #expect(received == true)
    }

    @Test func clearPostsNotification() throws {
        let cm = ClipboardManager()
        var received = false
        let token = NotificationCenter.default.addObserver(
            forName: .clipboardStateChanged, object: cm, queue: nil
        ) { _ in received = true }
        defer { NotificationCenter.default.removeObserver(token) }

        cm.clear()
        #expect(received == true)
    }

    // MARK: - Source directory tracking

    @Test func sourceDirectoryTracked() throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }
        let file = try TestHelpers.createFile("file.txt", in: dir)

        let cm = ClipboardManager()
        cm.cut(urls: [file])
        // deletingLastPathComponent adds trailing slash; compare paths
        #expect(cm.sourceDirectory?.path == dir.path)
    }
}
