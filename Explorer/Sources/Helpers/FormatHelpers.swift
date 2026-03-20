import Foundation
import UniformTypeIdentifiers

enum FormatHelpers {
    private static let byteCountFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    private static let absoluteDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter
    }()

    static func formatFileSize(_ bytes: Int64) -> String {
        byteCountFormatter.string(fromByteCount: bytes)
    }

    static func formatDate(_ date: Date) -> String {
        let now = Date()
        let interval = now.timeIntervalSince(date)

        // Show relative date if within the last 7 days
        if interval < 7 * 24 * 60 * 60 && interval >= 0 {
            return relativeDateFormatter.localizedString(for: date, relativeTo: now)
        }

        return absoluteDateFormatter.string(from: date)
    }

    static func fileKindDescription(for url: URL) -> String {
        if let typeIdentifier = try? url.resourceValues(forKeys: [.typeIdentifierKey]).typeIdentifier,
           let utType = UTType(typeIdentifier) {
            return utType.localizedDescription ?? utType.identifier
        }

        if let contentType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
            return contentType.localizedDescription ?? contentType.identifier
        }

        let pathExtension = url.pathExtension.lowercased()
        if pathExtension.isEmpty {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                return "Folder"
            }
            return "Document"
        }

        if let utType = UTType(filenameExtension: pathExtension) {
            return utType.localizedDescription ?? utType.identifier
        }

        return "\(pathExtension.uppercased()) File"
    }
}
