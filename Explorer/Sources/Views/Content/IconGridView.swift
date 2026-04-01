import SwiftUI
import AppKit

struct IconGridView: View {
    @Environment(DirectoryViewModel.self) private var directoryVM
    @Environment(NavigationViewModel.self) private var navigationVM
    @Environment(ClipboardManager.self) private var clipboardManager
    @Environment(FavoritesManager.self) private var favoritesManager
    @Environment(SplitScreenManager.self) private var splitManager
    @Environment(\.openWindow) private var openWindow

    @State private var itemToRename: FileItem?
    @State private var renameName = ""
    @State private var showRenameAlert = false
    @State private var lastClickItem: FileItem.ID?
    @State private var lastClickTime: Date?
    @State private var dropTargetID: FileItem.ID?
    @State private var isBackgroundDropTarget = false

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 16)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(directoryVM.items) { item in
                    if item.isDirectory {
                        IconCell(
                            item: item,
                            isSelected: directoryVM.selectedItems.contains(item.id),
                            isCut: isCut(item),
                            isDropTarget: dropTargetID == item.id
                        )
                        .draggable(item.url)
                        .dropDestination(for: URL.self) { urls, _ in
                            guard !urls.contains(item.url) else { return false }
                            performMove(urls, to: item.url)
                            return true
                        } isTargeted: { isTargeted in
                            dropTargetID = isTargeted ? item.id : nil
                        }
                        .onTapGesture {
                            handleClick(item)
                        }
                        .contextMenu {
                            fileContextMenu(for: item)
                        }
                    } else {
                        IconCell(
                            item: item,
                            isSelected: directoryVM.selectedItems.contains(item.id),
                            isCut: isCut(item),
                            isDropTarget: false
                        )
                        .draggable(item.url)
                        .onTapGesture {
                            handleClick(item)
                        }
                        .contextMenu {
                            fileContextMenu(for: item)
                        }
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
                Task { await directoryVM.createNewFolder(in: currentURL) }
            }
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
        } else if MediaFileType.detect(from: item.url).isMedia {
            let siblings = directoryVM.items
                .filter { !$0.isDirectory && MediaFileType.detect(from: $0.url).isMedia }
                .map(\.url)
            let context = MediaViewerContext(fileURL: item.url, siblingURLs: siblings)
            openWindow(id: "mediaViewer", value: context)
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
        Task { await directoryVM.renameItem(item, to: renameName) }
    }

    private func moveToTrash(_ urls: [URL]) {
        Task { await directoryVM.trashItems(urls) }
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

// MARK: - Icon Cell

private struct IconCell: View {
    let item: FileItem
    let isSelected: Bool
    let isCut: Bool
    let isDropTarget: Bool

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
                .fill(isDropTarget ? Color.accentColor.opacity(0.3)
                      : isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isDropTarget ? Color.accentColor
                              : isSelected ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 2)
        )
        .opacity(isCut ? 0.4 : 1.0)
        .contentShape(Rectangle())
    }
}
