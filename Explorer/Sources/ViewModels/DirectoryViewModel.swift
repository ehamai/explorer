import Foundation
import SwiftUI

@MainActor
@Observable
final class DirectoryViewModel {

    // MARK: - Properties

    private(set) var items: [FileItem] = []
    private(set) var allItems: [FileItem] = []
    var selectedItems: Set<FileItem.ID> = []
    var sortDescriptor: FileSortDescriptor = FileSortDescriptor(field: .name, order: .ascending) {
        didSet { applyFilter() }
    }
    var viewMode: ViewMode = .list
    var showHidden: Bool = false {
        didSet { applyFilter() }
    }
    var isLoading: Bool = false
    var showInspector: Bool = false
    private(set) var loadedURL: URL?
    var searchText: String = "" {
        didSet { applyFilter() }
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
    private let watcher = DirectoryWatcher()

    // MARK: - Init

    nonisolated init(fileSystemService: FileSystemService = FileSystemService()) {
        self.fileSystemService = fileSystemService
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

        do {
            let loadedItems = try await fileSystemService.fullEnumerate(url: url, showHidden: true)
            allItems = loadedItems
            applyFilter()
            watcher.watch(url: url)
        } catch {
            allItems = []
            items = []
        }

        isLoading = false
    }

    /// Reload the current directory without clearing selection (used by file watcher).
    func reloadCurrentDirectory() async {
        guard let url = loadedURL else { return }
        do {
            let loadedItems = try await fileSystemService.fullEnumerate(url: url, showHidden: true)
            allItems = loadedItems
            applyFilter()
        } catch {
            allItems = []
            items = []
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
}
