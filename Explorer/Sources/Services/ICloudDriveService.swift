import Foundation
import AppKit

/// Provides a Finder-like merged view of iCloud Drive by combining user files
/// from `com~apple~CloudDocs` with app-specific container folders that have
/// a `Documents/` subfolder. Uses `localizedNameKey` for friendly display names.
@MainActor
@Observable
final class ICloudDriveService {

    // MARK: - Properties

    /// Whether iCloud Drive is available on this system.
    private(set) var isAvailable: Bool = false

    /// The CloudDocs directory (user's iCloud Drive files).
    private(set) var cloudDocsURL: URL?

    /// The Mobile Documents root (contains all iCloud containers).
    private(set) var mobileDocsURL: URL?

    private let fileManager = FileManager.default

    // MARK: - Init

    init() {
        let home = fileManager.homeDirectoryForCurrentUser
        let mobileDocs = home.appendingPathComponent("Library/Mobile Documents")
        let cloudDocs = mobileDocs.appendingPathComponent("com~apple~CloudDocs")

        if fileManager.fileExists(atPath: cloudDocs.path) {
            mobileDocsURL = mobileDocs
            cloudDocsURL = cloudDocs
            isAvailable = true
        }
    }

    // MARK: - Public API

    /// Check if a URL is the iCloud Drive root (the CloudDocs directory).
    func isICloudDriveRoot(_ url: URL) -> Bool {
        guard let cloudDocsURL else { return false }
        return url.standardizedFileURL == cloudDocsURL.standardizedFileURL
    }

    /// Enumerate the virtual iCloud Drive root by merging:
    /// 1. All items from `com~apple~CloudDocs/` (user files)
    /// 2. App container folders with `Documents/` subfolders (shown with localized names)
    func enumerateICloudDriveRoot(showHidden: Bool) -> [FileItem] {
        guard let cloudDocsURL, let mobileDocsURL else { return [] }

        var items: [FileItem] = []

        // 1. Enumerate user files from CloudDocs
        let cloudDocsItems = enumerateDirectory(cloudDocsURL, showHidden: showHidden)
        items.append(contentsOf: cloudDocsItems)

        // 2. Find app containers with Documents/ subfolders
        let appFolderItems = enumerateAppContainers(in: mobileDocsURL, showHidden: showHidden)
        items.append(contentsOf: appFolderItems)

        return items
    }

    // MARK: - Private

    /// Enumerate a directory and return FileItems, using localizedNameKey for display names.
    private func enumerateDirectory(_ url: URL, showHidden: Bool) -> [FileItem] {
        var options: FileManager.DirectoryEnumerationOptions = [
            .skipsSubdirectoryDescendants,
            .skipsPackageDescendants
        ]
        if !showHidden {
            options.insert(.skipsHiddenFiles)
        }

        guard let contents = try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: Array(FileItem.iCloudResourceKeys),
            options: options
        ) else {
            return []
        }

        return contents.compactMap { FileItem.fromURL($0) }
    }

    /// Scan Mobile Documents for app containers that have a Documents/ subfolder.
    /// Returns FileItems with:
    ///  - URL pointing to `<container>/Documents/` (for navigation)
    ///  - Display name from `localizedNameKey` (e.g., "Pages" instead of "com~apple~Pages")
    private func enumerateAppContainers(in mobileDocsURL: URL, showHidden: Bool) -> [FileItem] {
        guard let containers = try? fileManager.contentsOfDirectory(
            at: mobileDocsURL,
            includingPropertiesForKeys: [.localizedNameKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var items: [FileItem] = []

        for containerURL in containers {
            let rawName = containerURL.lastPathComponent

            // Skip CloudDocs (already enumerated as user files)
            if rawName == "com~apple~CloudDocs" { continue }

            // Check if this container has a Documents/ subfolder
            let documentsURL = containerURL.appendingPathComponent("Documents")
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: documentsURL.path, isDirectory: &isDir),
                  isDir.boolValue else {
                continue
            }

            // Get the localized display name for the container
            let localizedName = (try? containerURL.resourceValues(
                forKeys: [.localizedNameKey]
            ))?.localizedName ?? rawName

            // Create a FileItem that points to the Documents/ subfolder
            // but displays the container's localized name
            let icon = NSWorkspace.shared.icon(forFile: documentsURL.path)
            let dateModified = (try? documentsURL.resourceValues(
                forKeys: [.contentModificationDateKey]
            ))?.contentModificationDate ?? Date.distantPast

            let item = FileItem(
                url: documentsURL,
                name: localizedName,
                size: 0,
                dateModified: dateModified,
                kind: "Folder",
                isDirectory: true,
                isHidden: false,
                isPackage: false,
                icon: icon
            )
            items.append(item)
        }

        return items
    }
}
