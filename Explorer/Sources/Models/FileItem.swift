import Foundation
import AppKit
import UniformTypeIdentifiers

struct FileItem: Identifiable, Hashable, Equatable, Comparable {
    let url: URL
    let name: String
    let size: Int64
    let dateModified: Date
    let kind: String
    let isDirectory: Bool
    let isHidden: Bool
    let isPackage: Bool

    var id: URL { url }

    private var _icon: NSImage?

    var icon: NSImage {
        if let cached = _icon { return cached }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    init(
        url: URL,
        name: String,
        size: Int64,
        dateModified: Date,
        kind: String,
        isDirectory: Bool,
        isHidden: Bool,
        isPackage: Bool,
        icon: NSImage? = nil
    ) {
        self.url = url
        self.name = name
        self.size = size
        self.dateModified = dateModified
        self.kind = kind
        self.isDirectory = isDirectory
        self.isHidden = isHidden
        self.isPackage = isPackage
        self._icon = icon
    }

    static func < (lhs: FileItem, rhs: FileItem) -> Bool {
        if lhs.isDirectory != rhs.isDirectory {
            return lhs.isDirectory
        }
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }

    static func == (lhs: FileItem, rhs: FileItem) -> Bool {
        lhs.url == rhs.url
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }

    private static let resourceKeys: Set<URLResourceKey> = [
        .nameKey,
        .fileSizeKey,
        .contentModificationDateKey,
        .typeIdentifierKey,
        .isDirectoryKey,
        .isHiddenKey,
        .isPackageKey
    ]

    static func fromURL(_ url: URL) -> FileItem? {
        do {
            let values = try url.resourceValues(forKeys: resourceKeys)
            let name = values.name ?? url.lastPathComponent
            let size = Int64(values.fileSize ?? 0)
            let dateModified = values.contentModificationDate ?? Date.distantPast
            let isDirectory = values.isDirectory ?? false
            let isHidden = values.isHidden ?? false
            let isPackage = values.isPackage ?? false

            let kind: String
            if let typeIdentifier = values.typeIdentifier,
               let utType = UTType(typeIdentifier) {
                kind = utType.localizedDescription ?? utType.identifier
            } else if isDirectory {
                kind = "Folder"
            } else {
                kind = "Document"
            }

            let icon = NSWorkspace.shared.icon(forFile: url.path)

            return FileItem(
                url: url,
                name: name,
                size: size,
                dateModified: dateModified,
                kind: kind,
                isDirectory: isDirectory,
                isHidden: isHidden,
                isPackage: isPackage,
                icon: icon
            )
        } catch {
            return nil
        }
    }
}
