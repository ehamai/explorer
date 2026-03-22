import Foundation

/// Encapsulates file-move validation and execution for drag-and-drop operations.
enum FileMoveService {

    /// Result of a move operation.
    struct MoveResult {
        let movedCount: Int
        let sourceDirs: Set<URL>
    }

    /// Filters URLs that are valid for moving into a specific subfolder.
    /// Rejects: the destination itself, or a parent of the destination (subtree move).
    static func validURLsForFolderDrop(_ urls: [URL], destination: URL) -> [URL] {
        urls.filter { url in
            url != destination
            && !destination.path.hasPrefix(url.path + "/")
        }
    }

    /// Filters URLs that are valid for moving into the current directory background.
    /// Additionally rejects files already residing in the destination directory.
    static func validURLsForBackgroundDrop(_ urls: [URL], destination: URL) -> [URL] {
        let destPath = destination.standardizedFileURL.path
        return urls.filter { url in
            let parentPath = url.deletingLastPathComponent().standardizedFileURL.path
            return parentPath != destPath
                && url.path != destination.path
                && !destPath.hasPrefix(url.path + "/")
        }
    }

    /// Move the given URLs into the destination directory. Returns the count of
    /// moved items and the set of source directories that need refreshing.
    @discardableResult
    static func moveItems(_ urls: [URL], to destination: URL) -> MoveResult {
        var sourceDirs = Set<URL>()
        var movedCount = 0
        for url in urls {
            sourceDirs.insert(url.deletingLastPathComponent())
            let dest = destination.appendingPathComponent(url.lastPathComponent)
            do {
                try FileManager.default.moveItem(at: url, to: dest)
                movedCount += 1
            } catch {
                // Skip items that fail to move (e.g., name conflict)
            }
        }
        return MoveResult(movedCount: movedCount, sourceDirs: sourceDirs)
    }
}
