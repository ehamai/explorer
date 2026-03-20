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
        postNotification()
    }

    func copy(urls: [URL]) {
        sourceURLs = urls
        operation = .copy
        postNotification()
    }

    func paste(to destination: URL) async throws {
        guard hasPendingOperation else { return }

        let urls = sourceURLs
        let op = operation

        switch op {
        case .cut:
            try await fileSystemService.moveItems(urls, to: destination)
            clear()
        case .copy:
            try await fileSystemService.copyItems(urls, to: destination)
            // Keep clipboard after copy so user can paste again
        case .idle:
            break
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
