import SwiftUI
import AppKit

struct MainView: View {
    @Environment(SplitScreenManager.self) private var splitManager
    @Environment(ClipboardManager.self) private var clipboardManager
    @State private var doubleClickMonitor: Any?

    private var activeTab: BrowserTab? {
        splitManager.activeTabManager.activeTab
    }

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 300)
                .environment(splitManager.activeTabManager)
                .environment(splitManager.activePane.tabManager.activeTab?.navigationVM
                             ?? NavigationViewModel())
                .environment(splitManager.activePane.tabManager.activeTab?.directoryVM
                             ?? DirectoryViewModel())
        } detail: {
            detailContent
        }
        .toolbar { toolbarContent }
        .navigationTitle(activeTab?.navigationVM.currentURL.lastPathComponent ?? "Explorer")
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
                         isActive: splitManager.isActive(rightPane))
            }
        } else {
            PaneView(pane: splitManager.leftPane, isActive: true)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button(action: { activeTab?.navigationVM.goBack() }) {
                Image(systemName: "chevron.left")
            }
            .disabled(activeTab?.navigationVM.canGoBack != true)
            .help("Back")

            Button(action: { activeTab?.navigationVM.goForward() }) {
                Image(systemName: "chevron.right")
            }
            .disabled(activeTab?.navigationVM.canGoForward != true)
            .help("Forward")

            Button(action: { activeTab?.navigationVM.goUp() }) {
                Image(systemName: "chevron.up")
            }
            .disabled(activeTab?.navigationVM.canGoUp != true)
            .help("Enclosing Folder")
        }

        ToolbarItem(placement: .principal) {
            if let tab = activeTab {
                @Bindable var dir = tab.directoryVM
                Picker("View Mode", selection: $dir.viewMode) {
                    ForEach(ViewMode.allCases, id: \.self) { mode in
                        Label(mode.label, systemImage: mode.systemImage)
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 120)
                .help("View Mode")
            }
        }

        ToolbarItem(placement: .automatic) {
            Button(action: { splitManager.toggle() }) {
                Image(systemName: splitManager.isSplitScreen
                      ? "rectangle" : "rectangle.split.2x1")
            }
            .help(splitManager.isSplitScreen ? "Close Split" : "Split View")
        }

        ToolbarItem(placement: .automatic) {
            if let tab = activeTab {
                @Bindable var dir = tab.directoryVM
                TextField("Search", text: $dir.searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
            }
        }
    }

    // MARK: - Double-Click Handler

    private func installDoubleClickMonitor() {
        guard doubleClickMonitor == nil else { return }
        let sm = splitManager
        doubleClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            if event.clickCount == 2 {
                DispatchQueue.main.async {
                    // Check all panes for selected items (handles split-screen
                    // where the active pane may not have updated yet on double-click)
                    let panes = [sm.leftPane] + (sm.rightPane.map { [$0] } ?? [])
                    for pane in panes {
                        guard let tab = pane.tabManager.activeTab else { continue }
                        let selected = tab.directoryVM.items.filter {
                            tab.directoryVM.selectedItems.contains($0.id)
                        }
                        guard !selected.isEmpty else { continue }
                        sm.activate(pane: pane)
                        for item in selected {
                            if item.isDirectory {
                                tab.navigationVM.navigate(to: item.url)
                            } else {
                                NSWorkspace.shared.open(item.url)
                            }
                        }
                        break
                    }
                }
            }
            return event
        }
    }

    private func removeDoubleClickMonitor() {
        if let monitor = doubleClickMonitor {
            NSEvent.removeMonitor(monitor)
            doubleClickMonitor = nil
        }
    }
}
