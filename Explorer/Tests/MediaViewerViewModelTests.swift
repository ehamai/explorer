import Foundation
import AppKit
import Testing
@testable import Explorer

@Suite("MediaViewerViewModel Tests")
@MainActor
struct MediaViewerViewModelTests {

    private func makeContext(
        fileURL: URL = URL(fileURLWithPath: "/tmp/photo2.jpg"),
        siblingURLs: [URL]? = nil
    ) -> MediaViewerContext {
        let siblings = siblingURLs ?? [
            URL(fileURLWithPath: "/tmp/photo1.jpg"),
            URL(fileURLWithPath: "/tmp/photo2.jpg"),
            URL(fileURLWithPath: "/tmp/photo3.jpg"),
            URL(fileURLWithPath: "/tmp/video1.mp4"),
            URL(fileURLWithPath: "/tmp/photo4.jpg"),
        ]
        return MediaViewerContext(fileURL: fileURL, siblingURLs: siblings)
    }

    // MARK: - Initialization

    @Test func initializesWithCorrectState() {
        let context = makeContext()
        let vm = MediaViewerViewModel(context: context)

        #expect(vm.currentURL == URL(fileURLWithPath: "/tmp/photo2.jpg"))
        #expect(vm.siblingURLs.count == 5)
        #expect(vm.currentIndex == 1)
    }

    @Test func initializesAtFirstWhenFileIsFirst() {
        let context = makeContext(fileURL: URL(fileURLWithPath: "/tmp/photo1.jpg"))
        let vm = MediaViewerViewModel(context: context)
        #expect(vm.currentIndex == 0)
    }

    @Test func initializesAtLastWhenFileIsLast() {
        let context = makeContext(fileURL: URL(fileURLWithPath: "/tmp/photo4.jpg"))
        let vm = MediaViewerViewModel(context: context)
        #expect(vm.currentIndex == 4)
    }

    // MARK: - Window Title & Status

    @Test func windowTitleShowsFilename() {
        let context = makeContext()
        let vm = MediaViewerViewModel(context: context)
        #expect(vm.windowTitle == "photo2.jpg")
    }

    @Test func statusTextShowsPosition() {
        let context = makeContext()
        let vm = MediaViewerViewModel(context: context)
        #expect(vm.statusText == "2 of 5")
    }

    // MARK: - Navigation

    @Test func goToNextAdvancesIndex() {
        let context = makeContext()
        let vm = MediaViewerViewModel(context: context)

        vm.goToNext()

        #expect(vm.currentIndex == 2)
        #expect(vm.currentURL == URL(fileURLWithPath: "/tmp/photo3.jpg"))
        #expect(vm.statusText == "3 of 5")
    }

    @Test func goToPreviousDecrementsIndex() {
        let context = makeContext()
        let vm = MediaViewerViewModel(context: context)

        vm.goToPrevious()

        #expect(vm.currentIndex == 0)
        #expect(vm.currentURL == URL(fileURLWithPath: "/tmp/photo1.jpg"))
        #expect(vm.statusText == "1 of 5")
    }

    @Test func goToNextWrapsToFirst() {
        let context = makeContext(fileURL: URL(fileURLWithPath: "/tmp/photo4.jpg"))
        let vm = MediaViewerViewModel(context: context)

        vm.goToNext()

        #expect(vm.currentIndex == 0)
        #expect(vm.currentURL == URL(fileURLWithPath: "/tmp/photo1.jpg"))
    }

    @Test func goToPreviousWrapsToLast() {
        let context = makeContext(fileURL: URL(fileURLWithPath: "/tmp/photo1.jpg"))
        let vm = MediaViewerViewModel(context: context)

        vm.goToPrevious()

        #expect(vm.currentIndex == 4)
        #expect(vm.currentURL == URL(fileURLWithPath: "/tmp/photo4.jpg"))
    }

    @Test func canGoNextAndPreviousWithMiddleFile() {
        let context = makeContext()
        let vm = MediaViewerViewModel(context: context)
        #expect(vm.canGoNext == true)
        #expect(vm.canGoPrevious == true)
    }

    @Test func navigateMultipleSteps() {
        let context = makeContext(fileURL: URL(fileURLWithPath: "/tmp/photo1.jpg"))
        let vm = MediaViewerViewModel(context: context)

        vm.goToNext()
        vm.goToNext()
        vm.goToNext()

        #expect(vm.currentIndex == 3)
        #expect(vm.currentURL == URL(fileURLWithPath: "/tmp/video1.mp4"))
        #expect(vm.windowTitle == "video1.mp4")
    }

    // MARK: - Single item

    @Test func singleItemCannotNavigate() {
        let url = URL(fileURLWithPath: "/tmp/only.jpg")
        let context = MediaViewerContext(fileURL: url, siblingURLs: [url])
        let vm = MediaViewerViewModel(context: context)

        #expect(vm.canGoNext == false)
        #expect(vm.canGoPrevious == false)
        #expect(vm.statusText == "1 of 1")

        vm.goToNext()
        #expect(vm.currentIndex == 0)
        vm.goToPrevious()
        #expect(vm.currentIndex == 0)
    }

    // MARK: - Load Media with real files

    @Test func loadMediaSetsImageForJPEG() throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }

        // Create a minimal valid PNG (1x1 pixel, red)
        let pngFile = dir.appendingPathComponent("test.png")
        let pngData = createMinimalPNG()
        try pngData.write(to: pngFile)

        let context = MediaViewerContext(fileURL: pngFile, siblingURLs: [pngFile])
        let vm = MediaViewerViewModel(context: context)

        vm.loadMedia()

        #expect(vm.mediaType == .image)
        #expect(vm.displayImage != nil)
        #expect(vm.player == nil)
        #expect(vm.errorMessage == nil)
        #expect(vm.isLoading == false)
    }

    @Test func loadMediaSetsErrorForMissingFile() {
        let fakeURL = URL(fileURLWithPath: "/nonexistent/missing.jpg")
        let context = MediaViewerContext(fileURL: fakeURL, siblingURLs: [fakeURL])
        let vm = MediaViewerViewModel(context: context)

        vm.loadMedia()

        #expect(vm.mediaType == .image)
        #expect(vm.displayImage == nil)
        #expect(vm.errorMessage == "Could not load image")
    }

    @Test func loadMediaCreatesPlayerForVideo() throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }

        let mp4File = try TestHelpers.createFile("test.mp4", in: dir, content: "fake video data")

        let context = MediaViewerContext(fileURL: mp4File, siblingURLs: [mp4File])
        let vm = MediaViewerViewModel(context: context)

        vm.loadMedia()

        #expect(vm.mediaType == .video)
        #expect(vm.player != nil)
        #expect(vm.displayImage == nil)
        #expect(vm.errorMessage == nil)
    }

    @Test func cleanupPausesPlayer() throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }

        let mp4File = try TestHelpers.createFile("test.mp4", in: dir, content: "fake")

        let context = MediaViewerContext(fileURL: mp4File, siblingURLs: [mp4File])
        let vm = MediaViewerViewModel(context: context)

        vm.loadMedia()
        #expect(vm.player != nil)

        vm.cleanup()
        #expect(vm.player == nil)
    }

    // MARK: - Deletion

    @Test func trashCurrentFileRemovesAndAdvances() throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }

        let file1 = dir.appendingPathComponent("a.png")
        try createMinimalPNG().write(to: file1)
        let file2 = dir.appendingPathComponent("b.png")
        try createMinimalPNG().write(to: file2)
        let file3 = dir.appendingPathComponent("c.png")
        try createMinimalPNG().write(to: file3)

        let context = MediaViewerContext(fileURL: file1, siblingURLs: [file1, file2, file3])
        let vm = MediaViewerViewModel(context: context)
        vm.loadMedia()

        vm.trashCurrentFile()

        #expect(vm.siblingURLs.count == 2)
        #expect(vm.currentURL == file2)
        #expect(vm.currentIndex == 0)
        #expect(vm.shouldDismiss == false)
        #expect(!FileManager.default.fileExists(atPath: file1.path))
    }

    @Test func trashLastFileSetsShouldDismiss() throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }

        let file = dir.appendingPathComponent("only.png")
        try createMinimalPNG().write(to: file)

        let context = MediaViewerContext(fileURL: file, siblingURLs: [file])
        let vm = MediaViewerViewModel(context: context)
        vm.loadMedia()

        vm.trashCurrentFile()

        #expect(vm.siblingURLs.isEmpty)
        #expect(vm.shouldDismiss == true)
    }

    @Test func trashAtEndWrapsIndex() throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }

        let file1 = dir.appendingPathComponent("a.png")
        try createMinimalPNG().write(to: file1)
        let file2 = dir.appendingPathComponent("b.png")
        try createMinimalPNG().write(to: file2)

        let context = MediaViewerContext(fileURL: file2, siblingURLs: [file1, file2])
        let vm = MediaViewerViewModel(context: context)
        vm.loadMedia()

        vm.trashCurrentFile()

        #expect(vm.siblingURLs.count == 1)
        #expect(vm.currentURL == file1)
        #expect(vm.currentIndex == 0)
    }

    @Test func handleExternalDeletionRemovesSibling() async throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }

        let file1 = dir.appendingPathComponent("a.png")
        try createMinimalPNG().write(to: file1)
        let file2 = dir.appendingPathComponent("b.png")
        try createMinimalPNG().write(to: file2)
        let file3 = dir.appendingPathComponent("c.png")
        try createMinimalPNG().write(to: file3)

        // Viewer is on file3 (index 2)
        let context = MediaViewerContext(fileURL: file3, siblingURLs: [file1, file2, file3])
        let vm = MediaViewerViewModel(context: context)
        vm.loadMedia()
        vm.startListeningForDeletions()

        // Simulate file1 deleted by a different VM (use a dummy sender ID)
        let otherSenderID = ObjectIdentifier(NSObject())
        NotificationCenter.default.post(
            name: MediaViewerViewModel.mediaFileDeletedNotification,
            object: file1,
            userInfo: ["senderID": otherSenderID]
        )

        // Allow async Task to run
        try await Task.sleep(for: .milliseconds(100))

        #expect(vm.siblingURLs.count == 2)
        #expect(vm.currentURL == file3)
        #expect(vm.currentIndex == 1) // shifted down because file1 was before us

        vm.cleanup()
    }

    @Test func handleExternalDeletionIgnoresSelf() async throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }

        let file1 = dir.appendingPathComponent("a.png")
        try createMinimalPNG().write(to: file1)
        let file2 = dir.appendingPathComponent("b.png")
        try createMinimalPNG().write(to: file2)

        let context = MediaViewerContext(fileURL: file1, siblingURLs: [file1, file2])
        let vm = MediaViewerViewModel(context: context)
        vm.loadMedia()
        vm.startListeningForDeletions()

        // Post deletion FROM THE SAME VM — should be ignored
        NotificationCenter.default.post(
            name: MediaViewerViewModel.mediaFileDeletedNotification,
            object: file1,
            userInfo: ["senderID": ObjectIdentifier(vm)]
        )

        try await Task.sleep(for: .milliseconds(100))

        // Should remain unchanged — own deletion handled by trashCurrentFile
        #expect(vm.siblingURLs.count == 2)
        #expect(vm.currentURL == file1)

        vm.cleanup()
    }

    @Test func handleExternalDeletionOfCurrentFileAdvances() async throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }

        let file1 = dir.appendingPathComponent("a.png")
        try createMinimalPNG().write(to: file1)
        let file2 = dir.appendingPathComponent("b.png")
        try createMinimalPNG().write(to: file2)
        let file3 = dir.appendingPathComponent("c.png")
        try createMinimalPNG().write(to: file3)

        // Viewing file1, another viewer deletes file1
        let context = MediaViewerContext(fileURL: file1, siblingURLs: [file1, file2, file3])
        let vm = MediaViewerViewModel(context: context)
        vm.loadMedia()
        vm.startListeningForDeletions()

        let otherSenderID = ObjectIdentifier(NSObject())
        NotificationCenter.default.post(
            name: MediaViewerViewModel.mediaFileDeletedNotification,
            object: file1,
            userInfo: ["senderID": otherSenderID]
        )

        try await Task.sleep(for: .milliseconds(100))

        #expect(vm.siblingURLs.count == 2)
        #expect(vm.currentURL == file2) // advanced to next
        #expect(vm.currentIndex == 0)

        vm.cleanup()
    }

    @Test func navigationReloadsMedia() throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }

        let pngFile = dir.appendingPathComponent("img.png")
        try createMinimalPNG().write(to: pngFile)
        let mp4File = try TestHelpers.createFile("vid.mp4", in: dir, content: "fake video")

        let context = MediaViewerContext(fileURL: pngFile, siblingURLs: [pngFile, mp4File])
        let vm = MediaViewerViewModel(context: context)

        vm.loadMedia()
        #expect(vm.mediaType == .image)
        #expect(vm.displayImage != nil)

        vm.goToNext()
        #expect(vm.mediaType == .video)
        #expect(vm.player != nil)
        #expect(vm.displayImage == nil)
    }

    // MARK: - Deletion edge cases

    @Test func trashMiddleFileKeepsCorrectPosition() throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }

        let file1 = dir.appendingPathComponent("a.png")
        try createMinimalPNG().write(to: file1)
        let file2 = dir.appendingPathComponent("b.png")
        try createMinimalPNG().write(to: file2)
        let file3 = dir.appendingPathComponent("c.png")
        try createMinimalPNG().write(to: file3)

        // Start on file2 (middle)
        let context = MediaViewerContext(fileURL: file2, siblingURLs: [file1, file2, file3])
        let vm = MediaViewerViewModel(context: context)
        vm.loadMedia()

        vm.trashCurrentFile()

        // Should advance to file3 (same index position)
        #expect(vm.siblingURLs.count == 2)
        #expect(vm.currentURL == file3)
        #expect(vm.currentIndex == 1)
        #expect(vm.shouldDismiss == false)
    }

    @Test func trashSetsErrorOnFailure() {
        // Try to trash a non-existent file
        let fakeURL = URL(fileURLWithPath: "/nonexistent/fakefile.png")
        let context = MediaViewerContext(fileURL: fakeURL, siblingURLs: [fakeURL])
        let vm = MediaViewerViewModel(context: context)

        vm.trashCurrentFile()

        #expect(vm.errorMessage != nil)
        #expect(vm.errorMessage?.contains("Could not move to trash") == true)
        #expect(vm.siblingURLs.count == 1) // unchanged
        #expect(vm.shouldDismiss == false)
    }

    @Test func trashPostsNotificationWithSenderID() throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }

        let file1 = dir.appendingPathComponent("a.png")
        try createMinimalPNG().write(to: file1)
        let file2 = dir.appendingPathComponent("b.png")
        try createMinimalPNG().write(to: file2)

        let context = MediaViewerContext(fileURL: file1, siblingURLs: [file1, file2])
        let vm = MediaViewerViewModel(context: context)
        vm.loadMedia()

        var receivedURL: URL?
        var receivedSenderID: ObjectIdentifier?
        let observer = NotificationCenter.default.addObserver(
            forName: MediaViewerViewModel.mediaFileDeletedNotification,
            object: nil,
            queue: nil
        ) { notification in
            receivedURL = notification.object as? URL
            receivedSenderID = notification.userInfo?["senderID"] as? ObjectIdentifier
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        vm.trashCurrentFile()

        #expect(receivedURL == file1)
        #expect(receivedSenderID == ObjectIdentifier(vm))
    }

    @Test func trashAllFilesOneByOneDismisses() throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }

        let file1 = dir.appendingPathComponent("a.png")
        try createMinimalPNG().write(to: file1)
        let file2 = dir.appendingPathComponent("b.png")
        try createMinimalPNG().write(to: file2)

        let context = MediaViewerContext(fileURL: file1, siblingURLs: [file1, file2])
        let vm = MediaViewerViewModel(context: context)
        vm.loadMedia()

        vm.trashCurrentFile()
        #expect(vm.shouldDismiss == false)
        #expect(vm.siblingURLs.count == 1)

        vm.trashCurrentFile()
        #expect(vm.shouldDismiss == true)
        #expect(vm.siblingURLs.isEmpty)
    }

    // MARK: - Navigation after deletion

    @Test func canNavigateAfterDeletion() throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }

        let file1 = dir.appendingPathComponent("a.png")
        try createMinimalPNG().write(to: file1)
        let file2 = dir.appendingPathComponent("b.png")
        try createMinimalPNG().write(to: file2)
        let file3 = dir.appendingPathComponent("c.png")
        try createMinimalPNG().write(to: file3)

        let context = MediaViewerContext(fileURL: file1, siblingURLs: [file1, file2, file3])
        let vm = MediaViewerViewModel(context: context)
        vm.loadMedia()

        vm.trashCurrentFile()
        // Now on file2 with [file2, file3]
        #expect(vm.currentURL == file2)

        vm.goToNext()
        #expect(vm.currentURL == file3)

        vm.goToNext()
        // Should wrap back to file2
        #expect(vm.currentURL == file2)
    }

    @Test func cannotNavigateAfterDeletionLeavesOneFile() throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }

        let file1 = dir.appendingPathComponent("a.png")
        try createMinimalPNG().write(to: file1)
        let file2 = dir.appendingPathComponent("b.png")
        try createMinimalPNG().write(to: file2)

        let context = MediaViewerContext(fileURL: file1, siblingURLs: [file1, file2])
        let vm = MediaViewerViewModel(context: context)
        vm.loadMedia()

        vm.trashCurrentFile()
        #expect(vm.siblingURLs.count == 1)
        #expect(vm.canGoNext == false)
        #expect(vm.canGoPrevious == false)
    }

    // MARK: - External deletion edge cases

    @Test func handleExternalDeletionOfFileAfterCurrentIndex() async throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }

        let file1 = dir.appendingPathComponent("a.png")
        try createMinimalPNG().write(to: file1)
        let file2 = dir.appendingPathComponent("b.png")
        try createMinimalPNG().write(to: file2)
        let file3 = dir.appendingPathComponent("c.png")
        try createMinimalPNG().write(to: file3)

        // Viewing file1 (index 0), file3 (index 2) is deleted externally
        let context = MediaViewerContext(fileURL: file1, siblingURLs: [file1, file2, file3])
        let vm = MediaViewerViewModel(context: context)
        vm.loadMedia()
        vm.startListeningForDeletions()

        let otherSenderID = ObjectIdentifier(NSObject())
        NotificationCenter.default.post(
            name: MediaViewerViewModel.mediaFileDeletedNotification,
            object: file3,
            userInfo: ["senderID": otherSenderID]
        )

        try await Task.sleep(for: .milliseconds(100))

        #expect(vm.siblingURLs.count == 2)
        #expect(vm.currentURL == file1) // unchanged
        #expect(vm.currentIndex == 0) // unchanged

        vm.cleanup()
    }

    @Test func handleExternalDeletionOfUnknownFileIsIgnored() async throws {
        let context = makeContext()
        let vm = MediaViewerViewModel(context: context)
        vm.loadMedia()
        vm.startListeningForDeletions()

        let unknownURL = URL(fileURLWithPath: "/tmp/unknown_file.jpg")
        let otherSenderID = ObjectIdentifier(NSObject())
        NotificationCenter.default.post(
            name: MediaViewerViewModel.mediaFileDeletedNotification,
            object: unknownURL,
            userInfo: ["senderID": otherSenderID]
        )

        try await Task.sleep(for: .milliseconds(100))

        #expect(vm.siblingURLs.count == 5) // unchanged

        vm.cleanup()
    }

    @Test func startListeningForDeletionsIsIdempotent() async throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }

        let file1 = dir.appendingPathComponent("a.png")
        try createMinimalPNG().write(to: file1)
        let file2 = dir.appendingPathComponent("b.png")
        try createMinimalPNG().write(to: file2)

        let context = MediaViewerContext(fileURL: file2, siblingURLs: [file1, file2])
        let vm = MediaViewerViewModel(context: context)
        vm.loadMedia()

        // Call multiple times — should not register multiple observers
        vm.startListeningForDeletions()
        vm.startListeningForDeletions()
        vm.startListeningForDeletions()

        let otherSenderID = ObjectIdentifier(NSObject())
        NotificationCenter.default.post(
            name: MediaViewerViewModel.mediaFileDeletedNotification,
            object: file1,
            userInfo: ["senderID": otherSenderID]
        )

        try await Task.sleep(for: .milliseconds(100))

        // Should only have removed file1 once (not crash or double-remove)
        #expect(vm.siblingURLs.count == 1)
        #expect(vm.currentURL == file2)

        vm.cleanup()
    }

    // MARK: - shouldDismiss initial state

    @Test func shouldDismissStartsFalse() {
        let context = makeContext()
        let vm = MediaViewerViewModel(context: context)
        #expect(vm.shouldDismiss == false)
    }

    // MARK: - Helpers

    /// Create a minimal 1x1 red PNG for testing image loading.
    private func createMinimalPNG() -> Data {
        let size = NSSize(width: 1, height: 1)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.red.drawSwatch(in: NSRect(origin: .zero, size: size))
        image.unlockFocus()
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return Data()
        }
        return pngData
    }
}
