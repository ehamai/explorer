import Foundation
import SwiftUI
import AVKit

@MainActor
@Observable
final class MediaViewerViewModel {

    /// Posted when a media file is trashed from a viewer window.
    /// The notification object is the URL of the deleted file.
    static let mediaFileDeletedNotification = Notification.Name("MediaViewerFileDeleted")

    // MARK: - Properties

    private(set) var currentURL: URL
    private(set) var siblingURLs: [URL]
    private(set) var currentIndex: Int

    private(set) var displayImage: NSImage?
    private(set) var player: AVPlayer?
    private(set) var mediaType: MediaFileType = .unsupported
    private(set) var isLoading: Bool = false
    var errorMessage: String?

    /// Set to true when the last file is deleted and the window should close.
    private(set) var shouldDismiss: Bool = false

    var windowTitle: String { currentURL.lastPathComponent }

    var statusText: String {
        "\(currentIndex + 1) of \(siblingURLs.count)"
    }

    var canGoNext: Bool { siblingURLs.count > 1 }
    var canGoPrevious: Bool { siblingURLs.count > 1 }

    private var notificationObserver: Any?

    // MARK: - Init

    init(context: MediaViewerContext) {
        self.currentURL = context.fileURL
        self.siblingURLs = context.siblingURLs
        self.currentIndex = context.currentIndex
    }

    // MARK: - Notification Handling

    /// Start listening for deletions from other viewer windows.
    func startListeningForDeletions() {
        guard notificationObserver == nil else { return }
        notificationObserver = NotificationCenter.default.addObserver(
            forName: Self.mediaFileDeletedNotification,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard let self,
                  let deletedURL = notification.object as? URL,
                  let senderID = notification.userInfo?["senderID"] as? ObjectIdentifier,
                  senderID != ObjectIdentifier(self)
            else { return }
            Task { @MainActor [weak self] in
                self?.handleExternalDeletion(of: deletedURL)
            }
        }
    }

    /// Handle a file deleted by another viewer window.
    private func handleExternalDeletion(of deletedURL: URL) {
        guard let deletedIndex = siblingURLs.firstIndex(of: deletedURL) else { return }

        siblingURLs.remove(at: deletedIndex)

        if siblingURLs.isEmpty {
            shouldDismiss = true
            return
        }

        // If the deleted file was the one we're currently viewing, advance
        if deletedURL == currentURL {
            if currentIndex >= siblingURLs.count {
                currentIndex = 0
            }
            currentURL = siblingURLs[currentIndex]
            loadMedia()
            return
        }

        // Adjust currentIndex if the deleted file was before our current position
        if deletedIndex < currentIndex {
            currentIndex -= 1
        } else if currentIndex >= siblingURLs.count {
            currentIndex = siblingURLs.count - 1
        }
        currentURL = siblingURLs[currentIndex]
    }

    // MARK: - Media Loading

    func loadMedia() {
        isLoading = true
        errorMessage = nil
        player?.pause()
        player = nil
        displayImage = nil

        mediaType = MediaFileType.detect(from: currentURL)

        switch mediaType {
        case .image:
            if let image = NSImage(contentsOf: currentURL) {
                displayImage = image
            } else {
                errorMessage = "Could not load image"
            }

        case .video:
            let avPlayer = AVPlayer(url: currentURL)
            player = avPlayer

        case .unsupported:
            errorMessage = "Unsupported file type"
        }

        isLoading = false
    }

    // MARK: - Navigation

    func goToNext() {
        guard siblingURLs.count > 1 else { return }
        currentIndex = (currentIndex + 1) % siblingURLs.count
        currentURL = siblingURLs[currentIndex]
        loadMedia()
    }

    func goToPrevious() {
        guard siblingURLs.count > 1 else { return }
        currentIndex = (currentIndex - 1 + siblingURLs.count) % siblingURLs.count
        currentURL = siblingURLs[currentIndex]
        loadMedia()
    }

    // MARK: - Deletion

    /// Trash the current file. Returns true if the window should close (last file deleted).
    func trashCurrentFile() {
        let urlToDelete = currentURL

        // Perform the trash operation
        do {
            try FileManager.default.trashItem(at: urlToDelete, resultingItemURL: nil)
        } catch {
            errorMessage = "Could not move to trash: \(error.localizedDescription)"
            return
        }

        // Remove from siblings
        siblingURLs.remove(at: currentIndex)

        // Notify other viewer windows
        NotificationCenter.default.post(
            name: Self.mediaFileDeletedNotification,
            object: urlToDelete,
            userInfo: ["senderID": ObjectIdentifier(self)]
        )

        // If no files remain, signal window dismissal
        if siblingURLs.isEmpty {
            shouldDismiss = true
            return
        }

        // Adjust index and load next file
        if currentIndex >= siblingURLs.count {
            currentIndex = 0
        }
        currentURL = siblingURLs[currentIndex]
        loadMedia()
    }

    func cleanup() {
        player?.pause()
        player = nil
        if let observer = notificationObserver {
            NotificationCenter.default.removeObserver(observer)
            notificationObserver = nil
        }
    }
}
