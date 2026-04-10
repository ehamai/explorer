import Testing
import Foundation
@testable import Explorer

@Suite("SplitScreenManager.resolveDoubleClickTarget")
@MainActor
struct SplitScreenDoubleClickTests {

    // MARK: - Helpers

    /// Create a temp directory with a file and a subfolder inside it.
    private func makeTempDir() throws -> (dir: URL, file: URL, folder: URL) {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Tests/
            .deletingLastPathComponent() // Explorer/
            .deletingLastPathComponent() // project root
        let testTmpRoot = projectRoot.appendingPathComponent(".test-tmp")
        try FileManager.default.createDirectory(at: testTmpRoot, withIntermediateDirectories: true)

        let dir = testTmpRoot.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let file = dir.appendingPathComponent("testfile.txt")
        try "hello".write(to: file, atomically: true, encoding: .utf8)

        let folder = dir.appendingPathComponent("testfolder")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        return (dir, file, folder)
    }

    private func removeTempDir(_ dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - Tests

    /// Left pane has file selected, right pane is active with folder selected.
    /// Should return right pane's folder, not left pane's file.
    @Test func doubleClickUsesActivePane() async throws {
        let (leftDir, _, _) = try makeTempDir()
        let (rightDir, _, _) = try makeTempDir()
        defer { removeTempDir(leftDir); removeTempDir(rightDir) }

        let sm = SplitScreenManager()

        // Load left pane's directory and select the file
        let leftTab = sm.leftPane.tabManager.activeTab!
        await leftTab.directoryVM.loadDirectory(url: leftDir)
        let leftFile = leftTab.directoryVM.items.first { $0.name == "testfile.txt" }!
        leftTab.directoryVM.selectedItems = [leftFile.id]

        // Enable split screen (creates and activates right pane)
        sm.toggle()
        let rightTab = sm.rightPane!.tabManager.activeTab!
        await rightTab.directoryVM.loadDirectory(url: rightDir)
        let rightFolder = rightTab.directoryVM.items.first { $0.name == "testfolder" }!
        rightTab.directoryVM.selectedItems = [rightFolder.id]

        // Right pane is active (set by toggle)
        let result = sm.resolveDoubleClickTarget()

        #expect(result != nil, "Should resolve a target")
        let (tab, items) = result!
        #expect(tab.id == rightTab.id, "Should use the active (right) pane's tab")
        #expect(items.count == 1)
        #expect(items[0].isDirectory, "Should return the folder from the right pane")
        #expect(items[0].name == "testfolder")
    }

    /// Active pane has no selection, inactive pane has selection.
    /// Should return nil — must not act on the inactive pane.
    @Test func doubleClickIgnoresInactivePaneSelection() async throws {
        let (leftDir, _, _) = try makeTempDir()
        let (rightDir, _, _) = try makeTempDir()
        defer { removeTempDir(leftDir); removeTempDir(rightDir) }

        let sm = SplitScreenManager()

        let leftTab = sm.leftPane.tabManager.activeTab!
        await leftTab.directoryVM.loadDirectory(url: leftDir)
        let leftFile = leftTab.directoryVM.items.first { $0.name == "testfile.txt" }!
        leftTab.directoryVM.selectedItems = [leftFile.id]

        sm.toggle()
        let rightTab = sm.rightPane!.tabManager.activeTab!
        await rightTab.directoryVM.loadDirectory(url: rightDir)
        // Right pane auto-selects first item, clear it to test no-selection case
        rightTab.directoryVM.selectedItems.removeAll()

        let result = sm.resolveDoubleClickTarget()

        #expect(result == nil, "Should return nil when active pane has no selection")
    }

    /// Single pane mode — returns active pane's selection normally.
    @Test func doubleClickSinglePane() async throws {
        let (dir, _, _) = try makeTempDir()
        defer { removeTempDir(dir) }

        let sm = SplitScreenManager()

        let tab = sm.leftPane.tabManager.activeTab!
        await tab.directoryVM.loadDirectory(url: dir)
        let fileItem = tab.directoryVM.items.first { $0.name == "testfile.txt" }!
        tab.directoryVM.selectedItems = [fileItem.id]

        let result = sm.resolveDoubleClickTarget()

        #expect(result != nil, "Should resolve a target in single-pane mode")
        let (resolvedTab, items) = result!
        #expect(resolvedTab.id == tab.id)
        #expect(items.count == 1)
        #expect(items[0].name == "testfile.txt")
    }
}
