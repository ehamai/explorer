import Foundation
import UniformTypeIdentifiers

enum MediaFileType: Hashable, Sendable {
    case image
    case video
    case pdf
    case unsupported

    /// Detect whether a URL points to an image, video, PDF, or unsupported file.
    static func detect(from url: URL) -> MediaFileType {
        guard let values = try? url.resourceValues(forKeys: [.typeIdentifierKey]),
              let typeIdentifier = values.typeIdentifier,
              let utType = UTType(typeIdentifier) else {
            return fromExtension(url.pathExtension)
        }

        if utType.conforms(to: .image) { return .image }
        if utType.conforms(to: .movie) || utType.conforms(to: .video) { return .video }
        if utType.conforms(to: .pdf) { return .pdf }
        return .unsupported
    }

    /// Fallback detection using file extension when resource values aren't available.
    static func fromExtension(_ ext: String) -> MediaFileType {
        let lower = ext.lowercased()
        if imageExtensions.contains(lower) { return .image }
        if videoExtensions.contains(lower) { return .video }
        if lower == "pdf" { return .pdf }
        return .unsupported
    }

    /// True for images and videos — files viewable in the built-in media viewer.
    var isMedia: Bool { self == .image || self == .video }

    /// True for file types that support thumbnail preview generation.
    var hasThumbnail: Bool { self == .image || self == .video || self == .pdf }

    private static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "tiff", "tif", "bmp", "heic", "heif",
        "webp", "ico", "svg", "raw", "cr2", "nef", "arw", "dng"
    ]

    private static let videoExtensions: Set<String> = [
        "mp4", "mov", "m4v", "avi", "mkv", "wmv", "flv", "webm",
        "mpeg", "mpg", "3gp"
    ]
}
