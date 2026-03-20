import SwiftUI
import AppKit

struct FileListView: View {
    @Environment(DirectoryViewModel.self) private var directoryVM
    @Environment(NavigationViewModel.self) private var navigationVM
    @Environment(ClipboardManager.self) private var clipboardManager
    @Environment(FavoritesManager.self) private var favoritesManager

    @State private var sortOrder = [KeyPathComparator(\FileItem.name)]
    @State private var itemToRename: FileItem?
    @State private var renameName = ""
    @State private var showRenameAlert = false

    var body: some View {
        @Bindable var directoryVM = directoryVM

        Table(of: FileItem.self, selection: $directoryVM.selectedItems, sortOrder: $sortOrder) {
            TableColumn("Name", value: \.name) { item in
                HStack(spacing: 6) {
                    FileIconView(item: item, size: 16)
                    Text(item.name)
                        .lineLimit(1)
                }
                .opacity(isCut(item) ? 0.4 : 1.0)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    openItem(item)
                }
            }
            .width(min: 180, ideal: 300)

            TableColumn("Date Modified", value: \.dateModified) { item in
                Text(FormatHelpers.formatDate(item.dateModified))
                    .foregroundStyle(.secondary)
                    .opacity(isCut(item) ? 0.4 : 1.0)
            }
            .width(min: 120, ideal: 160)

            TableColumn("Size", value: \.size) { item in
                Text(item.isDirectory ? "--" : FormatHelpers.formatFileSize(item.size))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .opacity(isCut(item) ? 0.4 : 1.0)
            }
            .width(min: 70, ideal: 90)

            TableColumn("Kind", value: \.kind) { item in
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
        .onChange(of: sortOrder) { _, newOrder in
            applySort(newOrder)
        }
        .onKeyPress(.return) {
            openSelectedItems()
            return .handled
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
        Button("Paste") {
            let url = navigationVM.currentURL
            Task {
                try? await clipboardManager.paste(to: url)
                await directoryVM.loadDirectory(url: url)
            }
        }
        .disabled(clipboardManager.sourceURLs.isEmpty)

        Divider()

        Button("Rename") {
            itemToRename = item
            renameName = item.name
            showRenameAlert = true
        }

        Button("Pin to Favorites") {
            favoritesManager.addFavorite(url: item.url)
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

    private func applySort(_ comparators: [KeyPathComparator<FileItem>]) {
        guard let comparator = comparators.first else { return }
        let field: SortField
        if comparator.keyPath == \FileItem.name {
            field = .name
        } else if comparator.keyPath == \FileItem.dateModified {
            field = .dateModified
        } else if comparator.keyPath == \FileItem.size {
            field = .size
        } else if comparator.keyPath == \FileItem.kind {
            field = .kind
        } else {
            return
        }
        let order: SortOrder = comparator.order == .forward ? .ascending : .descending
        directoryVM.sortDescriptor = FileSortDescriptor(field: field, order: order)
    }
}
