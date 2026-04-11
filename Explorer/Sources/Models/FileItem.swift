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
    var iCloudStatus: ICloudStatus

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
        icon: NSImage? = nil,
        iCloudStatus: ICloudStatus = .local
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
        self.iCloudStatus = iCloudStatus
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

    static let iCloudResourceKeys: Set<URLResourceKey> = [
        .nameKey,
        .localizedNameKey,
        .fileSizeKey,
        .contentModificationDateKey,
        .typeIdentifierKey,
        .isDirectoryKey,
        .isHiddenKey,
        .isPackageKey,
        .ubiquitousItemDownloadingStatusKey,
        .ubiquitousItemIsDownloadingKey,
        .ubiquitousItemIsUploadedKey,
        .ubiquitousItemIsUploadingKey
    ]

    static func fromURL(_ url: URL) -> FileItem? {
        // Detect .icloud placeholder stubs (e.g. ".MyFile.txt.icloud")
        let fileName = url.lastPathComponent
        var displayURL = url
        var placeholderDetected = false

        if fileName.hasPrefix(".") && fileName.hasSuffix(".icloud") && fileName.count > 8 {
            let realName = String(fileName.dropFirst().dropLast(7))
            displayURL = url.deletingLastPathComponent().appendingPathComponent(realName)
            placeholderDetected = true
        }

        do {
            let values = try url.resourceValues(forKeys: iCloudResourceKeys)
            let name: String
            if placeholderDetected {
                name = displayURL.lastPathComponent
            } else {
                name = values.localizedName ?? values.name ?? url.lastPathComponent
            }
            let size = Int64(values.fileSize ?? 0)
            let dateModified = values.contentModificationDate ?? Date.distantPast
            let isDirectory = values.isDirectory ?? false
            let isHidden = values.isHidden ?? false
            let isPackage = values.isPackage ?? false

            let kind: String
            if placeholderDetected {
                if let utType = UTType(filenameExtension: displayURL.pathExtension) {
                    kind = utType.localizedDescription ?? utType.identifier
                } else {
                    kind = "Document"
                }
            } else if let typeIdentifier = values.typeIdentifier,
               let utType = UTType(typeIdentifier) {
                kind = utType.localizedDescription ?? utType.identifier
            } else if isDirectory {
                kind = "Folder"
            } else {
                kind = "Document"
            }

            // Derive iCloud status
            let iCloudStatus: ICloudStatus
            if placeholderDetected {
                iCloudStatus = .cloudOnly
            } else if let downloadingStatus = values.ubiquitousItemDownloadingStatus {
                if values.ubiquitousItemIsDownloading == true {
                    iCloudStatus = .downloading(progress: 0)
                } else if downloadingStatus == URLUbiquitousItemDownloadingStatus.current {
                    if values.ubiquitousItemIsUploading == true {
                        iCloudStatus = .uploading(progress: 0)
                    } else {
                        iCloudStatus = .current
                    }
                } else {
                    iCloudStatus = .cloudOnly
                }
            } else {
                iCloudStatus = .local
            }

            let icon = NSWorkspace.shared.icon(forFile: placeholderDetected ? displayURL.path : url.path)

            return FileItem(
                url: placeholderDetected ? displayURL : url,
                name: name,
                size: size,
                dateModified: dateModified,
                kind: kind,
                isDirectory: isDirectory,
                isHidden: isHidden,
                isPackage: isPackage,
                icon: icon,
                iCloudStatus: iCloudStatus
            )
        } catch {
            return nil
        }
    }
}
