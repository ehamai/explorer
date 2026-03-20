import SwiftUI
import AppKit

struct MainView: View {
    @Environment(TabManager.self) private var tabManager
    @Environment(ClipboardManager.self) private var clipboardManager
    @State private var doubleClickMonitor: Any?

    var body: some View {
        if let tab = tabManager.activeTab {
            mainContent(tab: tab)
                .environment(tab.navigationVM)
                .environment(tab.directoryVM)
        }
    }

    @ViewBuilder
    private func mainContent(tab: BrowserTab) -> some View {
        @Bindable var directoryVM = tab.directoryVM

        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 300)
        } detail: {
            VStack(spacing: 0) {
                if tabManager.tabs.count > 1 {
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
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button(action: { tab.navigationVM.goBack() }) {
                    Image(systemName: "chevron.left")
                }
                .disabled(!tab.navigationVM.canGoBack)
                .help("Back")

                Button(action: { tab.navigationVM.goForward() }) {
                    Image(systemName: "chevron.right")
                }
                .disabled(!tab.navigationVM.canGoForward)
                .help("Forward")

                Button(action: { tab.navigationVM.goUp() }) {
                    Image(systemName: "chevron.up")
                }
                .disabled(!tab.navigationVM.canGoUp)
                .help("Enclosing Folder")
            }

            ToolbarItem(placement: .principal) {
                Picker("View Mode", selection: $directoryVM.viewMode) {
                    ForEach(ViewMode.allCases, id: \.self) { mode in
                        Label(mode.label, systemImage: mode.systemImage)
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 120)
                .help("View Mode")
            }

            ToolbarItem(placement: .automatic) {
                TextField("Search", text: $directoryVM.searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
            }
        }
        .navigationTitle(tab.navigationVM.currentURL.lastPathComponent)
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
        .onAppear { installDoubleClickMonitor() }
        .onDisappear { removeDoubleClickMonitor() }
    }

    // Centralized double-click handler — reads from TabManager dynamically
    // so it always operates on the active tab regardless of tab switches.
    private func installDoubleClickMonitor() {
        guard doubleClickMonitor == nil else { return }
        let tm = tabManager
        doubleClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            if event.clickCount == 2 {
                DispatchQueue.main.async {
                    guard let tab = tm.activeTab else { return }
                    let selected = tab.directoryVM.items.filter {
                        tab.directoryVM.selectedItems.contains($0.id)
                    }
                    for item in selected {
                        if item.isDirectory {
                            tab.navigationVM.navigate(to: item.url)
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
        if let monitor = doubleClickMonitor {
            NSEvent.removeMonitor(monitor)
            doubleClickMonitor = nil
        }
    }
}
