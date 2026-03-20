import Foundation

actor FileSystemService {
    private let fileManager = FileManager.default

    private static let resourceKeys: [URLResourceKey] = [
        .nameKey,
        .fileSizeKey,
        .contentModificationDateKey,
        .typeIdentifierKey,
        .isDirectoryKey,
        .isHiddenKey,
        .isPackageKey
    ]

    private static let resourceKeySet = Set(resourceKeys)

    func enumerate(url: URL) -> AsyncStream<[FileItem]> {
        AsyncStream { continuation in
            let task = Task.detached { [fileManager] in
                guard let enumerator = fileManager.enumerator(
                    at: url,
                    includingPropertiesForKeys: FileSystemService.resourceKeys,
                    options: [.skipsSubdirectoryDescendants, .skipsPackageDescendants]
                ) else {
                    continuation.finish()
                    return
                }

                var batch: [FileItem] = []
                batch.reserveCapacity(500)

                for case let fileURL as URL in enumerator {
                    if Task.isCancelled { break }

                    if let item = FileItem.fromURL(fileURL) {
                        batch.append(item)

                        if batch.count >= 500 {
                            continuation.yield(batch)
                            batch.removeAll(keepingCapacity: true)
                        }
                    }
                }

                if !batch.isEmpty {
                    continuation.yield(batch)
                }
                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func fullEnumerate(url: URL, showHidden: Bool) async throws -> [FileItem] {
        let resourceKeys = FileSystemService.resourceKeys
        var options: FileManager.DirectoryEnumerationOptions = [
            .skipsSubdirectoryDescendants,
            .skipsPackageDescendants
        ]
        if !showHidden {
            options.insert(.skipsHiddenFiles)
        }

        let contents = try fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: resourceKeys,
            options: options
        )

        var items: [FileItem] = []
        items.reserveCapacity(contents.count)

        for fileURL in contents {
            if let item = FileItem.fromURL(fileURL) {
                items.append(item)
            }
        }

        return items
    }

    func moveItems(_ urls: [URL], to destination: URL) async throws {
        for sourceURL in urls {
            let destinationURL = destination.appendingPathComponent(sourceURL.lastPathComponent)
            try fileManager.moveItem(at: sourceURL, to: destinationURL)
        }
    }

    func copyItems(_ urls: [URL], to destination: URL) async throws {
        for sourceURL in urls {
            let destinationURL = destination.appendingPathComponent(sourceURL.lastPathComponent)
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
        }
    }

    func deleteItems(_ urls: [URL]) async throws {
        for url in urls {
            try fileManager.trashItem(at: url, resultingItemURL: nil)
        }
    }

    func renameItem(at url: URL, to newName: String) async throws -> URL {
        let newURL = url.deletingLastPathComponent().appendingPathComponent(newName)
        try fileManager.moveItem(at: url, to: newURL)
        return newURL
    }

    func createFolder(in directory: URL, name: String) async throws -> URL {
        let folderURL = directory.appendingPathComponent(name)
        try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: false)
        return folderURL
    }

    func fileExists(at url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path)
    }

    func isDirectory(at url: URL) -> Bool {
        var isDir: ObjCBool = false
        let exists = fileManager.fileExists(atPath: url.path, isDirectory: &isDir)
        return exists && isDir.boolValue
    }
}
