import SwiftUI

struct MainView: View {
    @Environment(NavigationViewModel.self) private var navigationVM
    @Environment(DirectoryViewModel.self) private var directoryVM

    var body: some View {
        @Bindable var directoryVM = directoryVM

        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 300)
        } detail: {
            VStack(spacing: 0) {
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
                Button(action: { navigationVM.goBack() }) {
                    Image(systemName: "chevron.left")
                }
                .disabled(!navigationVM.canGoBack)
                .help("Back")

                Button(action: { navigationVM.goForward() }) {
                    Image(systemName: "chevron.right")
                }
                .disabled(!navigationVM.canGoForward)
                .help("Forward")

                Button(action: { navigationVM.goUp() }) {
                    Image(systemName: "chevron.up")
                }
                .disabled(!navigationVM.canGoUp)
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
        .navigationTitle(navigationVM.currentURL.lastPathComponent)
        .onChange(of: navigationVM.currentURL) { _, newURL in
            Task {
                await directoryVM.loadDirectory(url: newURL)
            }
        }
        .task {
            await directoryVM.loadDirectory(url: navigationVM.currentURL)
        }
    }
}
