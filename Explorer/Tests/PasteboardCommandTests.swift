import Testing
import Foundation
import AppKit
@testable import Explorer

@Suite("Pasteboard command behaviors")
@MainActor
struct PasteboardCommandTests {

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

    // MARK: - Select All

    @Test func selectAllSelectsAllVisibleItems() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        _ = try createFile("a.txt", in: dir)
        _ = try createFile("b.txt", in: dir)
        _ = try createFile("c.txt", in: dir)

        let vm = DirectoryViewModel()
        await vm.loadDirectory(url: dir)
        #expect(vm.selectedItems.count == 1, "loadDirectory auto-selects first item")

        vm.selectAll()

        #expect(vm.selectedItems.count == 3, "Select All should select all visible items")
    }

    @Test func selectAllRespectsSearchFilter() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        _ = try createFile("report.pdf", in: dir)
        _ = try createFile("notes.txt", in: dir)
        _ = try createFile("readme.txt", in: dir)

        let vm = DirectoryViewModel()
        await vm.loadDirectory(url: dir)

        vm.searchText = "txt"
        vm.selectAll()

        #expect(vm.selectedItems.count == 2,
                "Select All should only select filtered items")
    }

    @Test func clearSelectionDeselectsAll() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        _ = try createFile("a.txt", in: dir)

        let vm = DirectoryViewModel()
        await vm.loadDirectory(url: dir)
        vm.selectAll()
        #expect(vm.selectedItems.count == 1)

        vm.clearSelection()
        #expect(vm.selectedItems.isEmpty)
    }

    // MARK: - Copy Path to Pasteboard

    @Test func copyPathWritesCorrectPathToPasteboard() throws {
        let url = URL(fileURLWithPath: "/Users/test/Documents/report.pdf")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.path, forType: .string)

        let pasted = NSPasteboard.general.string(forType: .string)
        #expect(pasted == "/Users/test/Documents/report.pdf",
                "Copy Path should write the full file path as a string")
    }

    @Test func copyPathOverwritesPreviousPasteboardContent() throws {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("old content", forType: .string)

        let url = URL(fileURLWithPath: "/tmp/new-file.txt")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.path, forType: .string)

        let pasted = NSPasteboard.general.string(forType: .string)
        #expect(pasted == "/tmp/new-file.txt")
    }

    // MARK: - Clipboard Manager Cut/Copy

    @Test func clipboardCutSetsOperationAndURLs() throws {
        let cm = ClipboardManager()
        let urls = [
            URL(fileURLWithPath: "/tmp/a.txt"),
            URL(fileURLWithPath: "/tmp/b.txt")
        ]

        cm.cut(urls: urls)

        #expect(cm.isCut == true)
        #expect(cm.hasPendingOperation == true)
        #expect(cm.sourceURLs == urls)
    }

    @Test func clipboardCopySetsOperationAndURLs() throws {
        let cm = ClipboardManager()
        let urls = [URL(fileURLWithPath: "/tmp/a.txt")]

        cm.copy(urls: urls)

        #expect(cm.isCut == false)
        #expect(cm.hasPendingOperation == true)
        #expect(cm.sourceURLs == urls)
    }

    @Test func clipboardClearResetsState() throws {
        let cm = ClipboardManager()
        cm.cut(urls: [URL(fileURLWithPath: "/tmp/a.txt")])
        #expect(cm.hasPendingOperation == true)

        cm.clear()

        #expect(cm.hasPendingOperation == false)
        #expect(cm.sourceURLs.isEmpty)
    }
}
