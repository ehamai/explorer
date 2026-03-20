import SwiftUI
import AppKit

struct FileListView: View {
    @Environment(DirectoryViewModel.self) private var directoryVM
    @Environment(NavigationViewModel.self) private var navigationVM
    @Environment(ClipboardManager.self) private var clipboardManager
    @Environment(FavoritesManager.self) private var favoritesManager
    @Environment(TabManager.self) private var tabManager

    @State private var itemToRename: FileItem?
    @State private var renameName = ""
    @State private var showRenameAlert = false

    var body: some View {
        @Bindable var directoryVM = directoryVM

        Table(of: FileItem.self, selection: $directoryVM.selectedItems) {
            TableColumn("Name") { (item: FileItem) in
                HStack(spacing: 6) {
                    FileIconView(item: item, size: 16)
                    Text(item.name)
                        .lineLimit(1)
                }
                .opacity(isCut(item) ? 0.4 : 1.0)
            }
            .width(min: 180, ideal: 300)

            TableColumn("Date Modified") { (item: FileItem) in
                Text(FormatHelpers.formatDate(item.dateModified))
                    .foregroundStyle(.secondary)
                    .opacity(isCut(item) ? 0.4 : 1.0)
            }
            .width(min: 120, ideal: 160)

            TableColumn("Size") { (item: FileItem) in
                Text(item.isDirectory ? "--" : FormatHelpers.formatFileSize(item.size))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .opacity(isCut(item) ? 0.4 : 1.0)
            }
            .width(min: 70, ideal: 90)

            TableColumn("Kind") { (item: FileItem) in
                Text(item.kind)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .opacity(isCut(item) ? 0.4 : 1.0)
            }
            .width(min: 80, ideal: 120)
        } rows: {
            ForEach(directoryVM.items) { item in
                TableRow(item)
                    .contextMenu {
                        fileContextMenu(for: item)
                    }
            }
        }
        .onKeyPress(.return) {
            openSelectedItems()
            return .handled
        }
        .contextMenu {
            Button("Paste") { performPaste() }
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
        .alert("Rename", isPresented: $showRenameAlert) {
            TextField("Name", text: $renameName)
            Button("Cancel", role: .cancel) { }
            Button("Rename") {
                performRename()
            }
        } message: {
            if let item = itemToRename {
                Text("Enter a new name for \"\(item.name)\"")
            }
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func fileContextMenu(for item: FileItem) -> some View {
        Button("Open") {
            openItem(item)
        }

        Divider()

        Button("Cut") {
            clipboardManager.cut(urls: selectedOrSingle(item))
        }
        Button("Copy") {
            clipboardManager.copy(urls: selectedOrSingle(item))
        }
        Button("Paste") { performPaste() }
        .disabled(!clipboardManager.hasPendingOperation)

        Divider()

        Button("Rename…") {
            itemToRename = item
            renameName = item.name
            showRenameAlert = true
        }

        Button("Pin to Favorites") {
            if item.isDirectory {
                favoritesManager.addFavorite(url: item.url)
            }
        }
        .disabled(!item.isDirectory)

        Divider()

        Button("Properties") {
            directoryVM.selectedItems = [item.id]
            directoryVM.showInspector = true
        }

        Divider()

        Button("Move to Trash", role: .destructive) {
            moveToTrash(selectedOrSingle(item))
        }
    }

    // MARK: - Actions

    private func openItem(_ item: FileItem) {
        if item.isDirectory {
            navigationVM.navigate(to: item.url)
        } else {
            NSWorkspace.shared.open(item.url)
        }
    }

    private func openSelectedItems() {
        let selected = directoryVM.items.filter { directoryVM.selectedItems.contains($0.id) }
        for item in selected {
            openItem(item)
        }
    }

    private func isCut(_ item: FileItem) -> Bool {
        clipboardManager.isCut && clipboardManager.sourceURLs.contains(item.url)
    }

    private func selectedOrSingle(_ item: FileItem) -> [URL] {
        if directoryVM.selectedItems.contains(item.id) {
            return directoryVM.selectedURLs
        }
        return [item.url]
    }

    private func performRename() {
        guard let item = itemToRename, !renameName.isEmpty, renameName != item.name else { return }
        let newURL = item.url.deletingLastPathComponent().appendingPathComponent(renameName)
        try? FileManager.default.moveItem(at: item.url, to: newURL)
        let currentURL = navigationVM.currentURL
        Task { await directoryVM.loadDirectory(url: currentURL) }
    }

    private func moveToTrash(_ urls: [URL]) {
        for url in urls {
            try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
        }
        let currentURL = navigationVM.currentURL
        Task { await directoryVM.loadDirectory(url: currentURL) }
    }

    private func performPaste() {
        let url = navigationVM.currentURL
        Task {
            let sourceDir = try? await clipboardManager.paste(to: url)
            await directoryVM.loadDirectory(url: url)
            if let sourceDir { await tabManager.reloadTabs(showing: sourceDir) }
        }
    }
}
