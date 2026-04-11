import SwiftUI
import AppKit

struct MosaicView: View {
    @Environment(DirectoryViewModel.self) private var directoryVM
    @Environment(NavigationViewModel.self) private var navigationVM
    @Environment(ClipboardManager.self) private var clipboardManager
    @Environment(FavoritesManager.self) private var favoritesManager
    @Environment(SplitScreenManager.self) private var splitManager
    @Environment(ThumbnailCache.self) private var thumbnailCache
    @Environment(ThumbnailLoader.self) private var thumbnailLoader
    @Environment(\.openWindow) private var openWindow

    @State private var itemToRename: FileItem?
    @State private var renameName = ""
    @State private var showRenameAlert = false
    @State private var lastClickItem: FileItem.ID?
    @State private var lastClickTime: Date?
    @State private var isBackgroundDropTarget = false

    var body: some View {
        @Bindable var directoryVM = directoryVM
        GeometryReader { geo in // lint:allow — required for justified row layout
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(directoryVM.mosaicRows) { row in
                        HStack(spacing: 2) {
                            ForEach(row.items) { layoutItem in
                                if let fileItem = itemLookup(layoutItem.id) {
                                    MosaicThumbnailView(
                                        layoutItem: layoutItem,
                                        fileItem: fileItem,
                                        isSelected: directoryVM.selectedItems.contains(fileItem.id),
                                        isCut: isCut(fileItem)
                                    )
                                    .frame(width: layoutItem.width, height: layoutItem.height)
                                    .clipped()
                                    .draggable(fileItem.url)
                                    .onTapGesture { handleClick(fileItem) }
                                    .contextMenu { fileContextMenu(for: fileItem) }
                                }
                            }
                        }
                    }
                }
                .padding(2)
                .animation(.easeInOut(duration: 0.2), value: directoryVM.mosaicZoom)
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .background {
                KeyCaptureView(onKeyDown: { keyCode in
                    handleKeyCode(keyCode)
                })
            }
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
            .pinchToZoom($directoryVM.mosaicZoom, range: DirectoryViewModel.mosaicZoomRange)
            .onChange(of: geo.size.width, initial: true) { _, newWidth in
                directoryVM.containerWidth = newWidth - 4
            }
            .onChange(of: directoryVM.items) {
                loadAspectRatiosForVisibleItems()
            }
            .onAppear {
                loadAspectRatiosForVisibleItems()
            }
            .onDisappear {
                thumbnailLoader.cancelAll()
            }
        }
        .alert("Rename", isPresented: $showRenameAlert) {
            TextField("Name", text: $renameName)
            Button("Cancel", role: .cancel) { }
            Button("Rename") { performRename() }
        } message: {
            if let item = itemToRename {
                Text("Enter a new name for \"\(item.name)\"")
            }
        }
    }

    // MARK: - Helpers

    private func itemLookup(_ id: URL) -> FileItem? {
        directoryVM.items.first { $0.id == id }
    }

    private func loadAspectRatiosForVisibleItems() {
        thumbnailLoader.loadAspectRatios(for: directoryVM.items, into: directoryVM)
    }

    // MARK: - Keyboard Handling

    private func handleKeyCode(_ keyCode: UInt16) -> Bool {
        switch keyCode {
        case 36: // Return
            openSelectedItems()
            return true
        case 123: directoryVM.navigateMosaicSelection(direction: .left); return true
        case 124: directoryVM.navigateMosaicSelection(direction: .right); return true
        case 125: directoryVM.navigateMosaicSelection(direction: .down); return true
        case 126: directoryVM.navigateMosaicSelection(direction: .up); return true
        default: return false
        }
    }

    private func openSelectedItems() {
        let selected = directoryVM.items.filter { directoryVM.selectedItems.contains($0.id) }
        for item in selected { openItem(item) }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func fileContextMenu(for item: FileItem) -> some View {
        Button("Open") { openItem(item) }

        Divider()

        Button("Cut") { clipboardManager.cut(urls: selectedOrSingle(item)) }
        Button("Copy") { clipboardManager.copy(urls: selectedOrSingle(item)) }
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
            if item.isDirectory { favoritesManager.addFavorite(url: item.url) }
        }
        .disabled(!item.isDirectory)

        Divider()

        Button("Properties") {
            directoryVM.selectedItems = [item.id]
            directoryVM.showInspector = true
        }

        Divider()

        if item.iCloudStatus.canDownload {
            Button("Download Now") {
                Task { await directoryVM.downloadItem(at: item.url) }
            }
        }
        if item.iCloudStatus.canEvict {
            Button("Remove Download") {
                Task { await directoryVM.evictItem(at: item.url) }
            }
        }

        Button("Move to Trash", role: .destructive) {
            moveToTrash(selectedOrSingle(item))
        }
    }

    // MARK: - Actions

    private func handleClick(_ item: FileItem) {
        let now = Date()
        if let lastItem = lastClickItem, let lastTime = lastClickTime,
           lastItem == item.id, now.timeIntervalSince(lastTime) < 0.4 {
            openItem(item)
            lastClickItem = nil
            lastClickTime = nil
            return
        }

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

    private func isCut(_ item: FileItem) -> Bool {
        clipboardManager.isCut && clipboardManager.sourceURLs.contains(item.url)
    }

    private func selectedOrSingle(_ item: FileItem) -> [URL] {
        if directoryVM.selectedItems.contains(item.id) { return directoryVM.selectedURLs }
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
