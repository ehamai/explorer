import Foundation

extension Notification.Name {
    static let clipboardStateChanged = Notification.Name("Explorer.clipboardStateChanged")
}

enum ClipboardOperation: Equatable {
    case idle
    case cut
    case copy
}

@Observable
final class ClipboardManager {
    private(set) var sourceURLs: [URL] = []
    private(set) var operation: ClipboardOperation = .idle
    /// The directory the cut/copied files came from
    private(set) var sourceDirectory: URL?

    private let fileSystemService: FileSystemService

    var hasPendingOperation: Bool {
        operation != .idle && !sourceURLs.isEmpty
    }

    var isCut: Bool {
        operation == .cut
    }

    init(fileSystemService: FileSystemService = FileSystemService()) {
        self.fileSystemService = fileSystemService
    }

    func cut(urls: [URL]) {
        sourceURLs = urls
        operation = .cut
        sourceDirectory = urls.first?.deletingLastPathComponent()
        postNotification()
    }

    func copy(urls: [URL]) {
        sourceURLs = urls
        operation = .copy
        sourceDirectory = urls.first?.deletingLastPathComponent()
        postNotification()
    }

    /// Paste and return the source directory that needs refreshing (for cut operations)
    func paste(to destination: URL) async throws -> URL? {
        guard hasPendingOperation else { return nil }

        let urls = sourceURLs
        let op = operation
        let srcDir = sourceDirectory

        switch op {
        case .cut:
            try await fileSystemService.moveItems(urls, to: destination)
            clear()
            return srcDir
        case .copy:
            try await fileSystemService.copyItems(urls, to: destination)
            return nil
        case .idle:
            return nil
        }
    }

    func clear() {
        sourceURLs = []
        operation = .idle
        postNotification()
    }

    private func postNotification() {
        NotificationCenter.default.post(name: .clipboardStateChanged, object: self)
    }
}
