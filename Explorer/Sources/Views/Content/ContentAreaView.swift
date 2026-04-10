import SwiftUI

struct ContentAreaView: View {
    @Environment(DirectoryViewModel.self) private var directoryVM
    @Environment(NavigationViewModel.self) private var navigationVM
    @Environment(ClipboardManager.self) private var clipboardManager
    @Environment(SplitScreenManager.self) private var splitManager

    @State private var isDropTarget = false
    @FocusState private var isContentFocused: Bool

    var body: some View {
        ZStack {
            if directoryVM.isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Loading…")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if directoryVM.items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "folder")
                        .font(.system(size: 48))
                        .foregroundStyle(.quaternary)
                    Text("Empty Folder")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .overlay {
                    if isDropTarget {
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.accentColor, lineWidth: 2)
                            .padding(2)
                            .allowsHitTesting(false)
                    }
                }
                .dropDestination(for: URL.self) { urls, _ in
                    performMove(urls, to: navigationVM.currentURL)
                } isTargeted: { targeted in
                    isDropTarget = targeted
                }
                .contextMenu { backgroundContextMenu() }
            } else {
                switch directoryVM.viewMode {
                case .list:
                    FileListView()
                case .icon:
                    IconGridView()
                case .mosaic:
                    MosaicView()
                }
            }
        }
        .focusable()
        .focused($isContentFocused)
        .focusEffectDisabled()
        .defaultFocus($isContentFocused, true)
        .onChange(of: directoryVM.items) {
            requestContentFocus()
        }
        .onChange(of: directoryVM.viewMode) {
            requestContentFocus()
        }
        .onChange(of: navigationVM.currentURL) {
            requestContentFocus()
        }
    }

    private func requestContentFocus() {
        // Delay to let the view hierarchy settle after state changes
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            isContentFocused = true
        }
    }

    private func performMove(_ urls: [URL], to destination: URL) -> Bool {
        let validURLs = FileMoveService.validURLsForBackgroundDrop(urls, destination: destination)
        guard !validURLs.isEmpty else { return false }
        let result = FileMoveService.moveItems(validURLs, to: destination)
        Task {
            await directoryVM.loadDirectory(url: destination)
            for dir in result.sourceDirs {
                await splitManager.reloadAllPanes(showing: dir)
            }
        }
        return true
    }

    @ViewBuilder
    private func backgroundContextMenu() -> some View {
        Button("Paste") {
            let url = navigationVM.currentURL
            Task {
                let sourceDir = try? await clipboardManager.paste(to: url)
                await directoryVM.loadDirectory(url: url)
                if let sourceDir { await splitManager.reloadAllPanes(showing: sourceDir) }
            }
        }
        .disabled(!clipboardManager.hasPendingOperation)

        Divider()

        Button("New Folder") {
            let currentURL = navigationVM.currentURL
            Task { await directoryVM.createNewFolder(in: currentURL) }
        }
    }
}
