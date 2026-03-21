import SwiftUI

struct ContentAreaView: View {
    @Environment(DirectoryViewModel.self) private var directoryVM
    @Environment(NavigationViewModel.self) private var navigationVM
    @Environment(ClipboardManager.self) private var clipboardManager
    @Environment(SplitScreenManager.self) private var splitManager

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
                .contextMenu { backgroundContextMenu() }
            } else {
                switch directoryVM.viewMode {
                case .list:
                    FileListView()
                case .icon:
                    IconGridView()
                }
            }
        }
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
            var folderURL = currentURL.appendingPathComponent("untitled folder")
            var counter = 1
            while FileManager.default.fileExists(atPath: folderURL.path) {
                folderURL = currentURL.appendingPathComponent("untitled folder \(counter)")
                counter += 1
            }
            try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: false)
            Task { await directoryVM.loadDirectory(url: currentURL) }
        }
    }
}
