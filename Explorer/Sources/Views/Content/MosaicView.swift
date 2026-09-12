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
    @State private var dropTargetID: FileItem.ID?
    @State private var isBackgroundDropTarget = false
    @State private var focusTrigger = 0

    var body: some View {
        @Bindable var directoryVM = directoryVM
        GeometryReader { geo in // lint:allow — required for justified row layout
            ScrollViewReader { scrollProxy in
                mosaicScrollContent
                    .modifier(MosaicInteractionModifiers(
                        directoryVM: directoryVM,
                        focusTrigger: $focusTrigger,
                        isBackgroundDropTarget: $isBackgroundDropTarget,
                        onKeyDown: handleKeyCode,
                        onPaste: performPaste,
                        onNewFolder: {
                            let url = navigationVM.currentURL
                            Task { await directoryVM.createNewFolder(in: url) }
                        },
                        hasPendingPaste: clipboardManager.hasPendingOperation,
                        onDrop: performMoveToCurrentDir
                    ))
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
                    .task {
                        try? await Task.sleep(for: .milliseconds(100))
                        scrollToSelection(scrollProxy)
                    }
                    .onDisappear {
                        thumbnailLoader.cancelAll()
                    }
                    .onChange(of: directoryVM.mosaicRows) {
                        scrollToSelection(scrollProxy)
                    }
                    .onChange(of: directoryVM.selectedItems) { _, _ in
                        scrollToSelection(scrollProxy)
                    }
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

    // MARK: - Scroll Content

    private var mosaicScrollContent: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(directoryVM.mosaicRows) { row in
                    HStack(spacing: 2) {
                        ForEach(row.items) { layoutItem in
                            if let fileItem = itemLookup(layoutItem.id) {
                                mosaicCell(layoutItem: layoutItem, fileItem: fileItem)
                            }
                        }
                    }
                    .id(row.id)
                }
            }
            .padding(2)
            .animation(.easeInOut(duration: 0.2), value: directoryVM.mosaicZoom)
        }
    }

    @ViewBuilder
    private func mosaicCell(layoutItem: MosaicLayoutItem, fileItem: FileItem) -> some View {
        let cell = MosaicThumbnailView(
            layoutItem: layoutItem,
            fileItem: fileItem,
            isSelected: directoryVM.selectedItems.contains(fileItem.id),
            isCut: isCut(fileItem),
            isDropTarget: dropTargetID == fileItem.id
        )
        .frame(width: layoutItem.width, height: layoutItem.height)
        .clipped()
        .overlay { dragSource(for: fileItem) }
        .contextMenu { fileContextMenu(for: fileItem) }

        if fileItem.isDirectory {
            cell.dropDestination(for: URL.self) { urls, _ in
                guard !urls.contains(fileItem.url) else { return false }
                performMove(urls, to: fileItem.url)
                return true
            } isTargeted: { isTargeted in
                dropTargetID = isTargeted ? fileItem.id : nil
            }
        } else {
            cell
        }
    }

    private func dragSource(for item: FileItem) -> FileDragSource {
        FileDragSource(
            urlsToDrag: { directoryVM.dragURLs(for: item) },
            dragImage: { url in
                thumbnailCache.get(for: url) ?? NSWorkspace.shared.icon(forFile: url.path)
            },
            onMouseDown: { clickCount, modifiers in
                guard clickCount == 1 else { return }
                directoryVM.handleMouseDown(
                    on: item.id,
                    command: modifiers.contains(.command),
                    shift: modifiers.contains(.shift)
                )
                focusTrigger += 1
            },
            onClick: { clickCount, modifiers in
                if clickCount == 2 {
                    openItem(item)
                } else if clickCount == 1 {
                    directoryVM.handleClick(
                        on: item.id,
                        command: modifiers.contains(.command),
                        shift: modifiers.contains(.shift)
                    )
                }
            }
        )
    }

    // MARK: - Helpers

    private func itemLookup(_ id: URL) -> FileItem? {
        directoryVM.items.first { $0.id == id }
    }

    private func loadAspectRatiosForVisibleItems() {
        thumbnailLoader.loadAspectRatios(for: directoryVM.items, into: directoryVM)
    }

    private func scrollToSelection(_ scrollProxy: ScrollViewProxy) {
        guard let selectedID = directoryVM.selectedItems.first,
              let row = directoryVM.mosaicRows.first(where: { row in
                  row.items.contains { $0.id == selectedID }
              }) else { return }
        scrollProxy.scrollTo(row.id, anchor: nil)
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

// MARK: - Interaction Modifiers

private struct MosaicInteractionModifiers: ViewModifier {
    let directoryVM: DirectoryViewModel
    @Binding var focusTrigger: Int
    @Binding var isBackgroundDropTarget: Bool
    let onKeyDown: (UInt16) -> Bool
    let onPaste: () -> Void
    let onNewFolder: () -> Void
    let hasPendingPaste: Bool
    let onDrop: ([URL]) -> Bool

    func body(content: Content) -> some View {
        content
            .background(Color(nsColor: .controlBackgroundColor))
            .background {
                KeyCaptureView(onKeyDown: { keyCode in
                    onKeyDown(keyCode)
                })
            }
            .background {
                ContentFocusHelper(focusTrigger: focusTrigger)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                // Clicks on cells also reach this gesture; the cell overlay handles those
                guard !FileDragSource.isEventOverDragSource(NSApp.currentEvent) else { return }
                directoryVM.selectedItems.removeAll()
                focusTrigger += 1
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
                onDrop(urls)
            } isTargeted: { targeted in
                isBackgroundDropTarget = targeted
            }
            .contextMenu {
                Button("Paste") { onPaste() }
                    .disabled(!hasPendingPaste)

                Divider()

                Button("New Folder") { onNewFolder() }
            }
    }
}
