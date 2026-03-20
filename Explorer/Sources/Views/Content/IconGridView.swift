import SwiftUI
import AppKit

struct IconGridView: View {
    @Environment(DirectoryViewModel.self) private var directoryVM
    @Environment(NavigationViewModel.self) private var navigationVM
    @Environment(ClipboardManager.self) private var clipboardManager
    @Environment(FavoritesManager.self) private var favoritesManager

    @State private var itemToRename: FileItem?
    @State private var renameName = ""
    @State private var showRenameAlert = false
    @State private var lastClickItem: FileItem.ID?
    @State private var lastClickTime: Date?

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 16)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(directoryVM.items) { item in
                    IconCell(
                        item: item,
                        isSelected: directoryVM.selectedItems.contains(item.id),
                        isCut: isCut(item)
                    )
                    .onTapGesture {
                        handleClick(item)
                    }
                    .contextMenu {
                        fileContextMenu(for: item)
                    }
                }
            }
            .padding(16)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .contentShape(Rectangle())
        .onTapGesture {
            directoryVM.selectedItems.removeAll()
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

    private func handleClick(_ item: FileItem) {
        let now = Date()

        // Detect double-click: same item clicked within 0.4s
        if let lastItem = lastClickItem, let lastTime = lastClickTime,
           lastItem == item.id, now.timeIntervalSince(lastTime) < 0.4 {
            openItem(item)
            lastClickItem = nil
            lastClickTime = nil
            return
        }

        // Single click — select
        lastClickItem = item.id
        lastClickTime = now

        if NSEvent.modifierFlags.contains(.command) {
            if directoryVM.selectedItems.contains(item.id) {
                directoryVM.selectedItems.remove(item.id)
            } else {
                directoryVM.selectedItems.insert(item.id)
            }
        } else {
            directoryVM.selectedItems = [item.id]
        }
    }

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
}

// MARK: - Icon Cell

private struct IconCell: View {
    let item: FileItem
    let isSelected: Bool
    let isCut: Bool

    var body: some View {
        VStack(spacing: 6) {
            FileIconView(item: item, size: 64)

            Text(item.name)
                .font(.callout)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 90)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1.5)
        )
        .opacity(isCut ? 0.4 : 1.0)
        .contentShape(Rectangle())
    }
}
