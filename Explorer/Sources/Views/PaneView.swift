import SwiftUI
import AppKit

/// A single file-browser pane with its own tab bar, path bar, content area, and status bar.
/// In split-screen mode, two PaneViews sit side by side.
struct PaneView: View {
    let pane: PaneState
    let isActive: Bool
    var isRightPane: Bool = false

    @Environment(SplitScreenManager.self) private var splitManager
    @Environment(ClipboardManager.self) private var clipboardManager
    @Environment(ICloudDriveService.self) private var iCloudDriveService
    @Environment(ICloudStatusService.self) private var iCloudStatusService

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
            }

            Divider()

            PathBarView()
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.bar)

            Divider()
                .overlay(alignment: .bottom) {
                    if isActive && splitManager.isSplitScreen {
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.accentColor.opacity(0.6),
                                        Color.accentColor.opacity(0.0)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(height: 6)
                            .blur(radius: 3)
                    }
                }

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
        .overlay {
            if !isActive && splitManager.isSplitScreen {
                Color.black.opacity(0.18)
                    .allowsHitTesting(false)
            }
        }
        // Invisible overlay that captures clicks for pane focus
        .overlay {
            Color.clear
                .contentShape(Rectangle())
                .simultaneousGesture(
                    TapGesture().onEnded {
                        splitManager.activate(pane: pane)
                    }
                )
                .allowsHitTesting(splitManager.isSplitScreen && !isActive)
        }
        .onChange(of: tab.navigationVM.currentURL) { _, newURL in
            if tab.directoryVM.loadedURL != newURL {
                Task { await tab.directoryVM.loadDirectory(url: newURL) }
            }
        }
        .task {
            tab.directoryVM.setICloudDriveService(iCloudDriveService)
            tab.directoryVM.setICloudStatusService(iCloudStatusService)
            if tab.directoryVM.allItems.isEmpty {
                await tab.directoryVM.loadDirectory(url: tab.navigationVM.currentURL)
            }
        }
        .onChange(of: iCloudStatusService.statusMap) { _, newMap in
            tab.directoryVM.updateICloudStatus(from: newMap)
        }
    }
}
