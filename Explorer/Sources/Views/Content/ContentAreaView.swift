import SwiftUI

struct ContentAreaView: View {
    @Environment(DirectoryViewModel.self) private var directoryVM
    @Environment(NavigationViewModel.self) private var navigationVM
    @Environment(ClipboardManager.self) private var clipboardManager
    @Environment(TabManager.self) private var tabManager

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
                case .column:
                    ColumnBrowserView()
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
                if let sourceDir { await tabManager.reloadTabs(showing: sourceDir) }
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

// MARK: - Column Browser View

/// A single-column list view serving as the column view mode.
/// Navigating into folders replaces the list content via the NavigationViewModel.
private struct ColumnBrowserView: View {
    @Environment(DirectoryViewModel.self) private var directoryVM
    @Environment(NavigationViewModel.self) private var navigationVM
    @Environment(ClipboardManager.self) private var clipboardManager
    @Environment(FavoritesManager.self) private var favoritesManager

    var body: some View {
        @Bindable var directoryVM = directoryVM

        List(selection: $directoryVM.selectedItems) {
            ForEach(directoryVM.items) { item in
                HStack(spacing: 8) {
                    FileIconView(item: item, size: 18)

                    Text(item.name)
                        .lineLimit(1)

                    Spacer()

                    if item.isDirectory {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .opacity(isCut(item) ? 0.4 : 1.0)
                .tag(item.id)
                .contextMenu {
                    Button("Open") { open(item) }
                    Divider()
                    Button("Cut") { clipboardManager.cut(urls: [item.url]) }
                    Button("Copy") { clipboardManager.copy(urls: [item.url]) }
                    Divider()
                    Button("Properties") {
                        directoryVM.selectedItems = [item.id]
                        directoryVM.showInspector = true
                    }
                    Divider()
                    Button("Move to Trash", role: .destructive) {
                        try? FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
                        let url = navigationVM.currentURL
                        Task { await directoryVM.loadDirectory(url: url) }
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    private func isCut(_ item: FileItem) -> Bool {
        clipboardManager.isCut && clipboardManager.sourceURLs.contains(item.url)
    }

    private func open(_ item: FileItem) {
        if item.isDirectory {
            navigationVM.navigate(to: item.url)
        } else {
            NSWorkspace.shared.open(item.url)
        }
    }
}
