import Testing
import Foundation
@testable import Explorer

@Suite("SplitScreenManager")
@MainActor
struct SplitScreenManagerTests {

    // MARK: - Init state

    @Test func initSinglePane() {
        let sm = SplitScreenManager()
        #expect(sm.isSplitScreen == false)
        #expect(sm.rightPane == nil)
    }

    @Test func initActivePaneIsLeft() {
        let sm = SplitScreenManager()
        #expect(sm.activePaneID == sm.leftPane.id)
    }

    // MARK: - Toggle

    @Test func toggleEnablesSplit() {
        let sm = SplitScreenManager()
        sm.toggle()
        #expect(sm.isSplitScreen == true)
        #expect(sm.rightPane != nil)
    }

    @Test func toggleActivatesRightPane() {
        let sm = SplitScreenManager()
        sm.toggle()
        #expect(sm.activePaneID == sm.rightPane!.id)
    }

    @Test func toggleBackToSingleDestroysRightPane() {
        let sm = SplitScreenManager()
        sm.toggle()
        sm.toggle()
        #expect(sm.isSplitScreen == false)
        #expect(sm.rightPane == nil)
    }

    @Test func toggleBackActivatesLeftPane() {
        let sm = SplitScreenManager()
        sm.toggle()
        sm.toggle()
        #expect(sm.activePaneID == sm.leftPane.id)
    }

    // MARK: - Activate / isActive

    @Test func activateSetsPane() {
        let sm = SplitScreenManager()
        sm.toggle()
        sm.activate(pane: sm.leftPane)
        #expect(sm.activePaneID == sm.leftPane.id)
    }

    @Test func isActiveReturnsCorrectly() {
        let sm = SplitScreenManager()
        #expect(sm.isActive(sm.leftPane) == true)

        sm.toggle()
        let right = sm.rightPane!
        #expect(sm.isActive(right) == true)
        #expect(sm.isActive(sm.leftPane) == false)
    }

    // MARK: - activePane / activeTabManager

    @Test func activePaneReturnsCorrect() {
        let sm = SplitScreenManager()
        // Single-pane: activePane is leftPane
        #expect(sm.activePane.id == sm.leftPane.id)

        // Split mode, right is active
        sm.toggle()
        #expect(sm.activePane.id == sm.rightPane!.id)

        // Switch to left
        sm.activate(pane: sm.leftPane)
        #expect(sm.activePane.id == sm.leftPane.id)
    }

    @Test func activeTabManagerMatchesActivePane() {
        let sm = SplitScreenManager()
        #expect(sm.activeTabManager === sm.activePane.tabManager)

        sm.toggle()
        #expect(sm.activeTabManager === sm.activePane.tabManager)
    }

    // MARK: - reloadAllPanes

    @Test func reloadAllPanesReloadsMatchingTabs() async throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }
        try TestHelpers.createFile("a.txt", in: dir)

        let sm = SplitScreenManager()
        sm.toggle()

        // Load the same directory in both panes
        let leftTab = sm.leftPane.tabManager.activeTab!
        let rightTab = sm.rightPane!.tabManager.activeTab!
        await leftTab.directoryVM.loadDirectory(url: dir)
        leftTab.navigationVM.navigate(to: dir)
        await rightTab.directoryVM.loadDirectory(url: dir)
        rightTab.navigationVM.navigate(to: dir)

        #expect(leftTab.directoryVM.items.count == 1)
        #expect(rightTab.directoryVM.items.count == 1)

        // navigate() resolves symlinks; use the resolved URL for reloadAllPanes
        let resolvedURL = leftTab.navigationVM.currentURL

        // Add another file and reload
        try TestHelpers.createFile("b.txt", in: dir)
        await sm.reloadAllPanes(showing: resolvedURL)

        #expect(leftTab.directoryVM.items.count == 2)
        #expect(rightTab.directoryVM.items.count == 2)
    }

    // MARK: - Left pane preservation

    @Test func togglePreservesLeftPaneState() async throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }
        try TestHelpers.createFile("keep.txt", in: dir)

        let sm = SplitScreenManager()
        let leftTab = sm.leftPane.tabManager.activeTab!
        await leftTab.directoryVM.loadDirectory(url: dir)
        let leftPaneID = sm.leftPane.id

        // Toggle on and off
        sm.toggle()
        sm.toggle()

        // Left pane identity and loaded items should survive
        #expect(sm.leftPane.id == leftPaneID)
        #expect(sm.leftPane.tabManager.activeTab!.directoryVM.items.count == 1)
    }
}
