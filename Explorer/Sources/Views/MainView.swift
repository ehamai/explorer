import SwiftUI
import AppKit

struct MainView: View {
    @Environment(SplitScreenManager.self) private var splitManager
    @Environment(ClipboardManager.self) private var clipboardManager
    @Environment(\.openWindow) private var openWindow

    /// NSEvent monitor reference — stored outside @State since it's a reference type.
    /// Managed manually via install/remove lifecycle.
    private static var _doubleClickMonitor: Any?

    private var leftTab: BrowserTab? {
        splitManager.leftPane.tabManager.activeTab
    }
    private var rightTab: BrowserTab? {
        splitManager.rightPane?.tabManager.activeTab
    }

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 300)
                .environment(splitManager.activePane.tabManager)
                .environment(splitManager.activePane.tabManager.activeTab?.navigationVM
                             ?? NavigationViewModel())
                .environment(splitManager.activePane.tabManager.activeTab?.directoryVM
                             ?? DirectoryViewModel())
        } detail: {
            detailContent
        }
        .toolbar { toolbarContent }
        .navigationTitle(splitManager.isSplitScreen ? "" : (leftTab?.navigationVM.currentURL.lastPathComponent ?? "Explorer"))
        .onAppear { installDoubleClickMonitor() }
        .onDisappear { removeDoubleClickMonitor() }
    }

    // MARK: - Detail Content

    @ViewBuilder
    private var detailContent: some View {
        if splitManager.isSplitScreen, let rightPane = splitManager.rightPane {
            HSplitView {
                PaneView(pane: splitManager.leftPane,
                         isActive: splitManager.isActive(splitManager.leftPane))
                PaneView(pane: rightPane,
                         isActive: splitManager.isActive(rightPane),
                         isRightPane: true)
            }
        } else {
            PaneView(pane: splitManager.leftPane, isActive: true)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // Left pane nav buttons
        ToolbarItemGroup(placement: .navigation) {
            navButtons(for: leftTab)

            if let tab = leftTab {
                @Bindable var dir = tab.directoryVM
                Picker("View", selection: $dir.viewMode) {
                    ForEach(ViewMode.allCases, id: \.self) { mode in
                        Image(systemName: mode.systemImage).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 110)
            }
        }

        // Right pane nav buttons (right-aligned, split mode only)
        if splitManager.isSplitScreen {
            ToolbarItemGroup(placement: .primaryAction) {
                navButtons(for: rightTab)

                if let tab = rightTab {
                    @Bindable var dir = tab.directoryVM
                    Picker("View", selection: $dir.viewMode) {
                        ForEach(ViewMode.allCases, id: \.self) { mode in
                            Image(systemName: mode.systemImage).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 110)
                }
            }
        }

        // Split toggle (far right)
        ToolbarItem(placement: .primaryAction) {
            Button(action: { splitManager.toggle() }) {
                Image(systemName: splitManager.isSplitScreen
                      ? "rectangle" : "rectangle.split.2x1")
            }
            .help(splitManager.isSplitScreen ? "Close Split" : "Split View")
        }
    }

    private func navButtons(for tab: BrowserTab?) -> some View {
        HStack(spacing: 2) {
            Button(action: { tab?.navigationVM.goBack() }) {
                Image(systemName: "chevron.left")
            }
            .disabled(tab?.navigationVM.canGoBack != true)
            .help("Back")

            Button(action: { tab?.navigationVM.goForward() }) {
                Image(systemName: "chevron.right")
            }
            .disabled(tab?.navigationVM.canGoForward != true)
            .help("Forward")

            Button(action: { tab?.navigationVM.goUp() }) {
                Image(systemName: "chevron.up")
            }
            .disabled(tab?.navigationVM.canGoUp != true)
            .help("Enclosing Folder")
        }
    }

    // MARK: - Double-Click Handler

    private func installDoubleClickMonitor() {
        guard Self._doubleClickMonitor == nil else { return }
        let sm = splitManager
        let ow = openWindow
        Self._doubleClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            if event.clickCount == 2 {
                Task { @MainActor in
                    guard let (tab, selected) = sm.resolveDoubleClickTarget() else { return }
                    for item in selected {
                        if item.isDirectory {
                            tab.navigationVM.navigate(to: item.url)
                        } else if MediaFileType.detect(from: item.url).isMedia {
                            let siblings = tab.directoryVM.items
                                .filter { !$0.isDirectory && MediaFileType.detect(from: $0.url).isMedia }
                                .map(\.url)
                            let context = MediaViewerContext(fileURL: item.url, siblingURLs: siblings)
                            ow(id: "mediaViewer", value: context)
                        } else {
                            NSWorkspace.shared.open(item.url)
                        }
                    }
                }
            }
            return event
        }
    }

    private func removeDoubleClickMonitor() {
        if let monitor = Self._doubleClickMonitor {
            NSEvent.removeMonitor(monitor)
            Self._doubleClickMonitor = nil
        }
    }
}
