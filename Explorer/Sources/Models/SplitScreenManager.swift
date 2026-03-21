import Foundation
import SwiftUI

struct PaneState: Identifiable {
    let id: UUID
    let tabManager: TabManager

    init() {
        self.id = UUID()
        self.tabManager = TabManager()
    }
}

@Observable
final class SplitScreenManager {
    var isSplitScreen: Bool = false
    let leftPane: PaneState
    var rightPane: PaneState?
    var activePaneID: UUID

    var activePane: PaneState {
        if let right = rightPane, activePaneID == right.id {
            return right
        }
        return leftPane
    }

    var activeTabManager: TabManager {
        activePane.tabManager
    }

    init() {
        let left = PaneState()
        self.leftPane = left
        self.activePaneID = left.id
    }

    func toggle() {
        isSplitScreen.toggle()
        if isSplitScreen {
            if rightPane == nil {
                let right = PaneState()
                rightPane = right
                activePaneID = right.id
                Task { await right.tabManager.activeTab?.directoryVM.loadDirectory(
                    url: right.tabManager.activeTab?.navigationVM.currentURL
                          ?? FileManager.default.homeDirectoryForCurrentUser
                )}
            }
        } else {
            rightPane = nil
            activePaneID = leftPane.id
        }
    }

    func activate(pane: PaneState) {
        activePaneID = pane.id
    }

    func isActive(_ pane: PaneState) -> Bool {
        activePaneID == pane.id
    }

    /// Reload tabs in ALL panes that are showing the given directory
    func reloadAllPanes(showing url: URL) async {
        await leftPane.tabManager.reloadTabs(showing: url)
        await rightPane?.tabManager.reloadTabs(showing: url)
    }
}
