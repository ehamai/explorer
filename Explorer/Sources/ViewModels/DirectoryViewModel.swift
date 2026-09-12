import Foundation
import SwiftUI

@MainActor
@Observable
final class DirectoryViewModel {

    // MARK: - Properties

    private(set) var items: [FileItem] = []
    private(set) var allItems: [FileItem] = []
    var selectedItems: Set<FileItem.ID> = [] {
        didSet {
            // A single selection (click, arrow keys) becomes the shift-click anchor
            if selectedItems.count == 1 {
                selectionAnchor = selectedItems.first
            } else if selectedItems.isEmpty {
                selectionAnchor = nil
            }
        }
    }
    /// Item that shift-click ranges extend from.
    private(set) var selectionAnchor: FileItem.ID?
    var sortDescriptor: FileSortDescriptor = FileSortDescriptor(field: .name, order: .ascending) {
        didSet { applyFilter() }
    }
    var viewMode: ViewMode = .list {
        didSet { recomputeMosaicRows() }
    }
    var showHidden: Bool = false {
        didSet { applyFilter() }
    }
    var isLoading: Bool = false
    var showInspector: Bool = false
    private(set) var loadedURL: URL?
    var searchText: String = "" {
        didSet { applyFilter() }
    }

    // MARK: - Mosaic Layout

    /// Container width for mosaic layout, set by the mosaic view's size reader
    var containerWidth: CGFloat = 0 {
        didSet { recomputeMosaicRows() }
    }

    /// Zoom level for mosaic view — controls target row height (100–500px)
    static let mosaicZoomRange: ClosedRange<CGFloat> = 100...500
    var mosaicZoom: CGFloat = 200 {
        didSet {
            let clamped = min(max(mosaicZoom, Self.mosaicZoomRange.lowerBound), Self.mosaicZoomRange.upperBound)
            if mosaicZoom != clamped {
                mosaicZoom = clamped
                return
            }
            recomputeMosaicRows()
        }
    }

    /// Aspect ratios loaded async from file metadata (images/videos)
    var aspectRatios: [URL: CGFloat] = [:] {
        didSet { recomputeMosaicRows() }
    }

    /// Precomputed justified rows for the mosaic view
    private(set) var mosaicRows: [MosaicRow] = []

    private func recomputeMosaicRows() {
        guard containerWidth > 0, viewMode == .mosaic else {
            mosaicRows = []
            return
        }
        let layoutItems: [(id: URL, aspectRatio: CGFloat, hasThumbnail: Bool)] = items.map { item in
            let mediaType = MediaFileType.detect(from: item.url)
            let hasThumbnail = mediaType.hasThumbnail
            let ar = aspectRatios[item.url] ?? 1.0
            return (id: item.url, aspectRatio: ar, hasThumbnail: hasThumbnail)
        }
        mosaicRows = computeJustifiedRows(
            items: layoutItems,
            containerWidth: containerWidth,
            targetRowHeight: mosaicZoom
        )
    }

    /// Set an aspect ratio for a URL (called by ThumbnailLoader after async detection).
    func setAspectRatio(_ ratio: CGFloat, for url: URL) {
        aspectRatios[url] = ratio
    }

    // MARK: - Mosaic Keyboard Navigation

    enum MosaicNavDirection { case left, right, up, down }

    func navigateMosaicSelection(direction: MosaicNavDirection) {
        guard !mosaicRows.isEmpty else { return }

        let selectedID = selectedItems.first
        var currentRow = 0
        var currentCol = 0
        var found = false

        if let selectedID {
            for (r, row) in mosaicRows.enumerated() {
                for (c, item) in row.items.enumerated() {
                    if item.id == selectedID {
                        currentRow = r
                        currentCol = c
                        found = true
                        break
                    }
                }
                if found { break }
            }
        }

        if !found {
            if let firstItem = mosaicRows.first?.items.first {
                selectedItems = [firstItem.id]
            }
            return
        }

        let targetRow: Int
        let targetCol: Int

        switch direction {
        case .left:
            if currentCol > 0 {
                targetRow = currentRow
                targetCol = currentCol - 1
            } else if currentRow > 0 {
                targetRow = currentRow - 1
                targetCol = mosaicRows[currentRow - 1].items.count - 1
            } else { return }
        case .right:
            if currentCol < mosaicRows[currentRow].items.count - 1 {
                targetRow = currentRow
                targetCol = currentCol + 1
            } else if currentRow < mosaicRows.count - 1 {
                targetRow = currentRow + 1
                targetCol = 0
            } else { return }
        case .up:
            guard currentRow > 0 else { return }
            targetRow = currentRow - 1
            targetCol = min(currentCol, mosaicRows[currentRow - 1].items.count - 1)
        case .down:
            guard currentRow < mosaicRows.count - 1 else { return }
            targetRow = currentRow + 1
            targetCol = min(currentCol, mosaicRows[currentRow + 1].items.count - 1)
        }

        selectedItems = [mosaicRows[targetRow].items[targetCol].id]
    }

    // MARK: - Grid Keyboard Navigation

    func navigateGridSelection(direction: MosaicNavDirection, columnCount: Int) {
        guard !items.isEmpty, columnCount > 0 else { return }

        let selectedID = selectedItems.first

        guard let selectedID,
              let currentIndex = items.firstIndex(where: { $0.id == selectedID }) else {
            // Nothing selected — select first item
            if let first = items.first {
                selectedItems = [first.id]
            }
            return
        }

        let targetIndex: Int
        switch direction {
        case .left:
            targetIndex = currentIndex - 1
        case .right:
            targetIndex = currentIndex + 1
        case .up:
            targetIndex = currentIndex - columnCount
        case .down:
            targetIndex = currentIndex + columnCount
        }

        guard targetIndex >= 0, targetIndex < items.count else { return }
        selectedItems = [items[targetIndex].id]
    }

    // MARK: - Computed Properties

    var itemCount: Int { items.count }
    var selectedCount: Int { selectedItems.count }

    var selectedURLs: [URL] {
        allItems
            .filter { selectedItems.contains($0.id) }
            .map(\.url)
    }

    /// The first selected item, used for inspector/properties panel
    var inspectedItem: FileItem? {
        guard let firstID = selectedItems.first else { return nil }
        return items.first { $0.id == firstID }
    }

    // MARK: - Dependencies

    private let fileSystemService: FileSystemService
    private let watcher: DirectoryWatcher
    private var iCloudStatusService: ICloudStatusService?
    private var iCloudDriveService: ICloudDriveService?

    // MARK: - Init

    nonisolated init(fileSystemService: FileSystemService = FileSystemService(), watcher: DirectoryWatcher = DirectoryWatcher()) {
        self.fileSystemService = fileSystemService
        self.watcher = watcher
        watcher.onChange = { [weak self] in
            guard let self else { return }
            Task { await self.reloadCurrentDirectory() }
        }
    }

    // MARK: - Directory Loading

    /// Load directory contents from the file system service and apply current sort/filter.
    func loadDirectory(url: URL) async {
        isLoading = true
        loadedURL = url
        selectedItems.removeAll()

        // Use merged enumeration for iCloud Drive root, standard enumeration otherwise
        if let iCloudService = iCloudDriveService, iCloudService.isICloudDriveRoot(url) {
            let loadedItems = iCloudService.enumerateICloudDriveRoot(showHidden: true)
            allItems = loadedItems
            applyFilter()
            // Watch the CloudDocs directory for changes
            watcher.watch(url: url)
        } else {
            do {
                let loadedItems = try await fileSystemService.fullEnumerate(url: url, showHidden: true)
                allItems = loadedItems
                applyFilter()
                watcher.watch(url: url)
            } catch {
                allItems = []
                items = []
            }
        }

        // Start iCloud monitoring if browsing an iCloud-managed directory
        if let service = iCloudStatusService, service.isInsideICloudDrive(url) {
            service.startMonitoring(directory: url)
        } else {
            iCloudStatusService?.stopMonitoring()
        }

        // Auto-select first item for immediate keyboard navigation
        if let firstItem = items.first {
            selectedItems = [firstItem.id]
        }

        isLoading = false
    }

    /// Reload the current directory without clearing selection (used by file watcher).
    func reloadCurrentDirectory() async {
        guard let url = loadedURL else { return }

        // Use merged enumeration for iCloud Drive root, standard enumeration otherwise
        if let iCloudService = iCloudDriveService, iCloudService.isICloudDriveRoot(url) {
            let loadedItems = iCloudService.enumerateICloudDriveRoot(showHidden: true)
            allItems = loadedItems
            applyFilter()
        } else {
            do {
                let loadedItems = try await fileSystemService.fullEnumerate(url: url, showHidden: true)
                allItems = loadedItems
                applyFilter()
            } catch {
                allItems = []
                items = []
            }
        }
    }

    // MARK: - Sorting

    /// Sort by the given descriptor directly.
    func sort(by descriptor: FileSortDescriptor) {
        sortDescriptor = descriptor
    }

    /// Sort by the given field. If already sorting by that field, toggle direction;
    /// otherwise switch to the new field with ascending order.
    func sort(by field: SortField) {
        if sortDescriptor.field == field {
            let newOrder: SortOrder = sortDescriptor.order == .ascending ? .descending : .ascending
            sortDescriptor = FileSortDescriptor(field: field, order: newOrder)
        } else {
            sortDescriptor = FileSortDescriptor(field: field, order: .ascending)
        }
    }

    // MARK: - Filtering

    /// Toggle hidden file visibility and reapply the filter.
    func toggleHidden() {
        showHidden.toggle()
    }

    /// Re-derive `items` from `allItems` using current showHidden, searchText, and sortDescriptor.
    func applyFilter() {
        var filtered = allItems

        // Filter hidden files
        if !showHidden {
            filtered = filtered.filter { !$0.isHidden }
        }

        // Filter by search text
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            filtered = filtered.filter { $0.name.lowercased().contains(query) }
        }

        // Sort using the sort descriptor's compare method
        filtered.sort { sortDescriptor.compare($0, $1) }

        items = filtered
        recomputeMosaicRows()
    }

    // MARK: - Selection

    /// Select all visible items.
    func selectAll() {
        selectedItems = Set(items.map(\.id))
    }

    /// Clear the selection.
    func clearSelection() {
        selectedItems.removeAll()
    }

    /// URLs to drag when a drag starts on `item`: the whole selection if the item
    /// is part of it, otherwise just the item.
    func dragURLs(for item: FileItem) -> [URL] {
        selectedItems.contains(item.id) ? selectedURLs : [item.url]
    }

    /// Finder-style mouse-down selection.
    /// - Shift: select the range from the anchor to the item (Command+Shift adds it).
    /// - Command: toggle the item; an added item becomes the anchor.
    /// - Neither: pressing an unselected item selects only it; pressing a selected
    ///   item keeps the selection so a subsequent drag carries every selected file.
    func handleMouseDown(on id: FileItem.ID, command: Bool, shift: Bool) {
        if shift {
            guard let range = selectionRange(to: id) else {
                selectedItems = [id]
                return
            }
            if command {
                selectedItems.formUnion(range)
            } else {
                selectedItems = range
            }
        } else if command {
            if selectedItems.contains(id) {
                selectedItems.remove(id)
            } else {
                selectedItems.insert(id)
                selectionAnchor = id
            }
        } else if !selectedItems.contains(id) {
            selectedItems = [id]
        }
    }

    /// Mouse-up without a drag: a plain click on an item narrows the selection to it.
    func handleClick(on id: FileItem.ID, command: Bool, shift: Bool) {
        guard !command, !shift else { return }
        selectedItems = [id]
    }

    /// IDs of visible items between the anchor and `id` (inclusive), in display order.
    private func selectionRange(to id: FileItem.ID) -> Set<FileItem.ID>? {
        guard let anchor = selectionAnchor,
              let anchorIndex = items.firstIndex(where: { $0.id == anchor }),
              let targetIndex = items.firstIndex(where: { $0.id == id }) else { return nil }
        let bounds = min(anchorIndex, targetIndex)...max(anchorIndex, targetIndex)
        return Set(items[bounds].map(\.id))
    }

    // MARK: - File Operations

    /// Create a new folder with auto-incrementing name in the given directory.
    func createNewFolder(in directory: URL) async {
        var name = "untitled folder"
        var counter = 1
        while await fileSystemService.fileExists(at: directory.appendingPathComponent(name)) {
            name = "untitled folder \(counter)"
            counter += 1
        }
        _ = try? await fileSystemService.createFolder(in: directory, name: name)
        await loadDirectory(url: directory)
    }

    /// Rename a file item and reload the directory.
    func renameItem(_ item: FileItem, to newName: String) async {
        guard !newName.isEmpty, newName != item.name else { return }
        _ = try? await fileSystemService.renameItem(at: item.url, to: newName)
        if let url = loadedURL {
            await loadDirectory(url: url)
        }
    }

    /// Move items to Trash and reload the directory.
    func trashItems(_ urls: [URL]) async {
        try? await fileSystemService.deleteItems(urls)
        if let url = loadedURL {
            await loadDirectory(url: url)
        }
    }

    /// Get item count for a folder (for inspector display).
    func folderItemCount(at url: URL) async -> Int? {
        let items = try? await fileSystemService.fullEnumerate(url: url, showHidden: false)
        return items?.count
    }

    /// Get file attributes for inspector display.
    func fileAttributes(at url: URL) -> (posixPermissions: String?, owner: String?) {
        guard let values = try? url.resourceValues(forKeys: [.fileSecurityKey]),
              let security = values.fileSecurity else { return (nil, nil) }
        var mode: mode_t = 0
        CFFileSecurityGetMode(security as CFFileSecurity, &mode)
        let posix = String(format: "%o", mode & 0o777)

        let owner: String?
        if let attrs = try? Foundation.FileManager.default.attributesOfItem(atPath: url.path),
           let name = attrs[.ownerAccountName] as? String {
            owner = name
        } else {
            owner = nil
        }
        return (posix, owner)
    }

    /// Get available disk space for the current directory.
    func availableDiskSpace() -> Int64? {
        guard let url = loadedURL else { return nil }
        if let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let capacity = values.volumeAvailableCapacityForImportantUsage {
            return capacity
        }
        return nil
    }

    // MARK: - iCloud Operations

    /// Set the iCloud status service for live sync monitoring.
    func setICloudStatusService(_ service: ICloudStatusService) {
        iCloudStatusService = service
    }

    /// Set the iCloud Drive service for merged root enumeration.
    func setICloudDriveService(_ service: ICloudDriveService) {
        iCloudDriveService = service
    }

    /// Trigger download of a cloud-only iCloud file.
    func downloadItem(at url: URL) async {
        do {
            try await fileSystemService.startDownloading(url: url)
            await reloadCurrentDirectory()
        } catch {
            // Matches existing silent-catch pattern
        }
    }

    /// Evict the local copy of an iCloud file.
    func evictItem(at url: URL) async {
        do {
            try await fileSystemService.evictItem(url: url)
            await reloadCurrentDirectory()
        } catch {
            // Matches existing silent-catch pattern
        }
    }

    /// Merge live iCloud status from NSMetadataQuery into displayed items.
    func updateICloudStatus(from statusMap: [URL: ICloudStatus]) {
        guard !statusMap.isEmpty else { return }
        for i in items.indices {
            if let status = statusMap[items[i].url] {
                items[i].iCloudStatus = status
            }
        }
    }
}
