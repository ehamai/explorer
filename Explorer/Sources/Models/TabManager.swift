import Foundation
import SwiftUI

struct BrowserTab: Identifiable {
    let id: UUID
    let navigationVM: NavigationViewModel
    let directoryVM: DirectoryViewModel

    init(startingURL: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.id = UUID()
        self.navigationVM = NavigationViewModel(startingURL: startingURL)
        self.directoryVM = DirectoryViewModel()
    }

    var displayName: String {
        navigationVM.currentURL.lastPathComponent
    }
}

@Observable
final class TabManager {
    var tabs: [BrowserTab]
    var activeTabID: UUID

    var activeTab: BrowserTab? {
        tabs.first { $0.id == activeTabID }
    }

    init() {
        let tab = BrowserTab()
        self.tabs = [tab]
        self.activeTabID = tab.id
    }

    func addTab(url: URL? = nil) {
        let startURL = url ?? FileManager.default.homeDirectoryForCurrentUser
        let tab = BrowserTab(startingURL: startURL)
        tabs.append(tab)
        activeTabID = tab.id
        Task { await tab.directoryVM.loadDirectory(url: startURL) }
    }

    func closeTab(id: UUID) {
        guard tabs.count > 1 else { return }
        let index = tabs.firstIndex { $0.id == id }
        tabs.removeAll { $0.id == id }
        if activeTabID == id {
            if let idx = index {
                let newIndex = min(idx, tabs.count - 1)
                activeTabID = tabs[newIndex].id
            } else {
                activeTabID = tabs[0].id
            }
        }
    }

    func closeActiveTab() {
        closeTab(id: activeTabID)
    }

    func nextTab() {
        guard let idx = tabs.firstIndex(where: { $0.id == activeTabID }) else { return }
        let next = (idx + 1) % tabs.count
        activeTabID = tabs[next].id
    }

    func previousTab() {
        guard let idx = tabs.firstIndex(where: { $0.id == activeTabID }) else { return }
        let prev = idx == 0 ? tabs.count - 1 : idx - 1
        activeTabID = tabs[prev].id
    }

    /// Reload any tabs that are currently showing the given directory
    func reloadTabs(showing url: URL) async {
        for tab in tabs where tab.navigationVM.currentURL == url {
            await tab.directoryVM.loadDirectory(url: url)
        }
    }
}
