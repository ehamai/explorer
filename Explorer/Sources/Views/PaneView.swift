import SwiftUI
import AppKit

/// A single file-browser pane with its own tab bar, path bar, content area, and status bar.
/// In split-screen mode, two PaneViews sit side by side.
struct PaneView: View {
    let pane: PaneState
    let isActive: Bool

    @Environment(SplitScreenManager.self) private var splitManager
    @Environment(ClipboardManager.self) private var clipboardManager

    var body: some View {
        if let tab = pane.tabManager.activeTab {
            paneContent(tab: tab)
                .environment(pane.tabManager)
                .environment(tab.navigationVM)
                .environment(tab.directoryVM)
        }
    }

    @ViewBuilder
    private func paneContent(tab: BrowserTab) -> some View {
        @Bindable var directoryVM = tab.directoryVM

        VStack(spacing: 0) {
            if pane.tabManager.tabs.count > 1 {
                TabBarView()
                Divider()
            }

            PathBarView()
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.bar)

            Divider()

            ContentAreaView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            StatusBarView()
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(.bar)
        }
        .inspector(isPresented: $directoryVM.showInspector) {
            InspectorView()
                .inspectorColumnWidth(min: 220, ideal: 260, max: 360)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(
                    isActive && splitManager.isSplitScreen
                        ? Color.accentColor.opacity(0.5)
                        : Color.clear,
                    lineWidth: 2
                )
        )
        .contentShape(Rectangle())
        .onTapGesture {
            splitManager.activate(pane: pane)
        }
        .onChange(of: tab.navigationVM.currentURL) { _, newURL in
            if tab.directoryVM.loadedURL != newURL {
                Task { await tab.directoryVM.loadDirectory(url: newURL) }
            }
        }
        .task {
            if tab.directoryVM.allItems.isEmpty {
                await tab.directoryVM.loadDirectory(url: tab.navigationVM.currentURL)
            }
        }
    }
}
