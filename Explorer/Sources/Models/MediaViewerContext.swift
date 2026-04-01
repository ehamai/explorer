import Foundation

/// Value passed to `openWindow(id:value:)` to open a media viewer window.
/// Contains the file to display and all sibling media files in the same directory.
struct MediaViewerContext: Codable, Hashable {
    let fileURL: URL
    let siblingURLs: [URL]

    var currentIndex: Int {
        siblingURLs.firstIndex(of: fileURL) ?? 0
    }
}
