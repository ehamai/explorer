import SwiftUI
import AppKit

struct FileListView: View {
    @Environment(DirectoryViewModel.self) private var directoryVM
    @Environment(NavigationViewModel.self) private var navigationVM
    @Environment(ClipboardManager.self) private var clipboardManager
    @Environment(FavoritesManager.self) private var favoritesManager
    @Environment(SplitScreenManager.self) private var splitManager

    @State private var itemToRename: FileItem?
    @State private var renameName = ""
    @State private var showRenameAlert = false
    @State private var dropTargetID: FileItem.ID?
    @State private var isBackgroundDropTarget = false

    var body: some View {
        @Bindable var directoryVM = directoryVM

        Table(of: FileItem.self, selection: $directoryVM.selectedItems) {
            TableColumn("Name") { (item: FileItem) in
                if item.isDirectory {
                    HStack(spacing: 6) {
                        FileIconView(item: item, size: 16)
                        Text(item.name)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(dropTargetID == item.id ? Color.accentColor.opacity(0.2) : Color.clear)
                            .padding(-4)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(dropTargetID == item.id ? Color.accentColor : Color.clear, lineWidth: 2)
                            .padding(-4)
                    )
                    .opacity(isCut(item) ? 0.4 : 1.0)
                    .dropDestination(for: URL.self) { urls, _ in
                        guard !urls.contains(item.url) else { return false }
                        performMove(urls, to: item.url)
                        return true
                    } isTargeted: { isTargeted in
                        dropTargetID = isTargeted ? item.id : nil
                    }
                } else {
                    HStack(spacing: 6) {
                        FileIconView(item: item, size: 16)
                        Text(item.name)
                            .lineLimit(1)
                    }
                    .opacity(isCut(item) ? 0.4 : 1.0)
                }
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
                    .draggable(item.url)
                    .contextMenu {
                        fileContextMenu(for: item)
                    }
            }
        }
        .onKeyPress(.return) {
            openSelectedItems()
            return .handled
        }
        .overlay {
            if isBackgroundDropTarget {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .padding(2)
                    .allowsHitTesting(false)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            performMoveToCurrentDir(urls)
        } isTargeted: { targeted in
            isBackgroundDropTarget = targeted
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
        Button("Copy Path") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(item.url.path, forType: .string)
        }

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
            if let sourceDir { await splitManager.reloadAllPanes(showing: sourceDir) }
        }
    }

    private func performMove(_ urls: [URL], to destination: URL) {
        let validURLs = FileMoveService.validURLsForFolderDrop(urls, destination: destination)
        guard !validURLs.isEmpty else { return }
        let currentURL = navigationVM.currentURL
        FileMoveService.moveItems(validURLs, to: destination)
        Task {
            await directoryVM.loadDirectory(url: currentURL)
            await splitManager.reloadAllPanes(showing: destination)
        }
    }

    private func performMoveToCurrentDir(_ urls: [URL]) -> Bool {
        let destination = navigationVM.currentURL
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
}
