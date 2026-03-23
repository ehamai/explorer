import Testing
import Foundation
@testable import Explorer

@Suite("TabManager")
@MainActor
struct TabManagerTests {

    // MARK: - Init

    @Test func initHasOneTab() {
        let manager = TabManager()
        #expect(manager.tabs.count == 1)
    }

    @Test func initActiveTabIsFirst() {
        let manager = TabManager()
        #expect(manager.activeTab != nil)
        #expect(manager.activeTabID == manager.tabs[0].id)
    }

    // MARK: - addTab

    @Test func addTabIncreasesCount() {
        let manager = TabManager()
        manager.addTab()
        #expect(manager.tabs.count == 2)
    }

    @Test func addTabActivatesNewTab() {
        let manager = TabManager()
        let originalID = manager.activeTabID
        manager.addTab()
        #expect(manager.activeTabID != originalID)
        #expect(manager.activeTabID == manager.tabs.last?.id)
    }

    @Test func addTabWithURL() {
        let manager = TabManager()
        let url = URL(fileURLWithPath: "/tmp")
        manager.addTab(url: url)
        let newTab = manager.tabs.last
        #expect(newTab != nil)
        #expect(newTab?.navigationVM.currentURL == url.standardizedFileURL)
    }

    @Test func addTabDefaultURL() {
        let manager = TabManager()
        manager.addTab()
        let newTab = manager.tabs.last
        let homeURL = FileManager.default.homeDirectoryForCurrentUser
        #expect(newTab?.navigationVM.currentURL == homeURL.standardizedFileURL)
    }

    // MARK: - closeTab

    @Test func closeTabRemovesTab() {
        let manager = TabManager()
        manager.addTab()
        #expect(manager.tabs.count == 2)
        let secondID = manager.tabs[1].id
        manager.closeTab(id: secondID)
        #expect(manager.tabs.count == 1)
    }

    @Test func closeTabUpdatesActiveToAdjacent() {
        let manager = TabManager()
        manager.addTab()
        manager.addTab()
        // 3 tabs: [0, 1, 2]. Activate middle.
        let middleID = manager.tabs[1].id
        manager.activeTabID = middleID
        manager.closeTab(id: middleID)
        // After closing middle (index 1), active should be valid
        #expect(manager.tabs.count == 2)
        #expect(manager.tabs.contains { $0.id == manager.activeTabID })
    }

    @Test func closeTabLastTabPrevented() {
        let manager = TabManager()
        let onlyID = manager.tabs[0].id
        manager.closeTab(id: onlyID)
        #expect(manager.tabs.count == 1, "Cannot close the last remaining tab")
        #expect(manager.tabs[0].id == onlyID)
    }

    @Test func closeTabNonActive() {
        let manager = TabManager()
        manager.addTab()
        let firstID = manager.tabs[0].id
        let secondID = manager.tabs[1].id
        manager.activeTabID = secondID
        manager.closeTab(id: firstID)
        #expect(manager.tabs.count == 1)
        #expect(manager.activeTabID == secondID, "Active tab should remain unchanged")
    }

    // MARK: - closeActiveTab

    @Test func closeActiveTabDelegates() {
        let manager = TabManager()
        manager.addTab()
        let activeID = manager.activeTabID
        manager.closeActiveTab()
        #expect(manager.tabs.count == 1)
        #expect(!manager.tabs.contains { $0.id == activeID })
    }

    // MARK: - activeTab computed property

    @Test func activeTabReturnsCorrectTab() {
        let manager = TabManager()
        manager.addTab()
        let lastTab = manager.tabs.last!
        manager.activeTabID = lastTab.id
        #expect(manager.activeTab?.id == lastTab.id)
    }

    // MARK: - displayName

    @Test func tabDisplayName() {
        let manager = TabManager()
        let url = URL(fileURLWithPath: "/tmp/SomeFolder")
        manager.addTab(url: url)
        let tab = manager.tabs.last!
        #expect(tab.displayName == "SomeFolder")
    }

    // MARK: - Complex scenarios

    @Test func addThreeCloseMiddle() {
        let manager = TabManager()
        manager.addTab()
        manager.addTab()
        #expect(manager.tabs.count == 3)

        let firstID = manager.tabs[0].id
        let middleID = manager.tabs[1].id
        let lastID = manager.tabs[2].id

        manager.activeTabID = middleID
        manager.closeTab(id: middleID)

        #expect(manager.tabs.count == 2)
        #expect(!manager.tabs.contains { $0.id == middleID })
        // Remaining tabs should be first and last
        #expect(manager.tabs.contains { $0.id == firstID })
        #expect(manager.tabs.contains { $0.id == lastID })
        // Active should be valid
        #expect(manager.tabs.contains { $0.id == manager.activeTabID })
    }

    @Test func closeTabUpdatesActiveToLastWhenClosingLast() {
        let manager = TabManager()
        manager.addTab()
        manager.addTab()
        #expect(manager.tabs.count == 3)

        let lastID = manager.tabs[2].id
        let previousID = manager.tabs[1].id
        manager.activeTabID = lastID
        manager.closeTab(id: lastID)

        #expect(manager.tabs.count == 2)
        // When closing the last tab in the list, active should move to the previous one
        #expect(manager.activeTabID == previousID)
    }
}
