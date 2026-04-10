import Foundation
import AppKit
import Testing

@testable import Explorer

@Suite("ThumbnailLoader")
@MainActor
struct ThumbnailLoaderTests {

    // MARK: - Helpers

    private func makeTempDir() throws -> URL {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let testTmpRoot = projectRoot.appendingPathComponent(".test-tmp")
        try FileManager.default.createDirectory(at: testTmpRoot, withIntermediateDirectories: true)
        let dir = testTmpRoot.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func createPNG(at url: URL, width: Int = 100, height: Int = 100) throws {
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        NSColor.red.setFill()
        NSBezierPath.fill(NSRect(origin: .zero, size: image.size))
        image.unlockFocus()
        let tiffData = image.tiffRepresentation!
        let rep = NSBitmapImageRep(data: tiffData)!
        let pngData = rep.representation(using: .png, properties: [:])!
        try pngData.write(to: url)
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private func makeLoader(cacheDir: URL) -> (ThumbnailLoader, ThumbnailCache) {
        let cache = ThumbnailCache()
        let service = ThumbnailService(cacheDirectory: cacheDir)
        let loader = ThumbnailLoader(service: service, cache: cache)
        return (loader, cache)
    }

    // MARK: - loadThumbnail

    @Test func loadThumbnailSkipsCachedURL() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        let cache = ThumbnailCache()
        let service = ThumbnailService(cacheDirectory: dir)
        let loader = ThumbnailLoader(service: service, cache: cache)

        let url = URL(fileURLWithPath: "/tmp/test-image.png")
        let image = NSImage(size: NSSize(width: 10, height: 10))
        cache.set(image, for: url)

        // Should not queue a load since it's already cached
        loader.loadThumbnail(for: url, modificationDate: Date())
        // No crash, no duplicate load — success
    }

    @Test func loadThumbnailSkipsDuplicateURL() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        let (loader, _) = makeLoader(cacheDir: dir)

        let url = dir.appendingPathComponent("test.png")
        try createPNG(at: url)
        let date = Date()

        loader.loadThumbnail(for: url, modificationDate: date)
        loader.loadThumbnail(for: url, modificationDate: date)
        // Second call should be a no-op (task already active)
    }

    // MARK: - awaitThumbnail

    @Test func awaitThumbnailReturnsCachedImage() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        let (loader, cache) = makeLoader(cacheDir: dir)

        let url = URL(fileURLWithPath: "/tmp/cached-test.png")
        let expected = NSImage(size: NSSize(width: 20, height: 20))
        cache.set(expected, for: url)

        let result = await loader.awaitThumbnail(for: url, modificationDate: Date())
        #expect(result === expected, "Should return cached image immediately")
    }

    @Test func awaitThumbnailLoadsAndReturnsImage() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        let (loader, _) = makeLoader(cacheDir: dir)

        let url = dir.appendingPathComponent("real.png")
        try createPNG(at: url, width: 50, height: 50)
        let modDate = try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as! Date

        let result = await loader.awaitThumbnail(for: url, modificationDate: modDate)
        #expect(result != nil, "Should load thumbnail for valid image")
    }

    // MARK: - cancelThumbnail

    @Test func cancelThumbnailRemovesFromActive() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        let (loader, _) = makeLoader(cacheDir: dir)

        let url = dir.appendingPathComponent("cancel-test.png")
        try createPNG(at: url)

        loader.loadThumbnail(for: url, modificationDate: Date())
        loader.cancelThumbnail(for: url)
        // Should be able to re-load after cancel
        loader.loadThumbnail(for: url, modificationDate: Date())
    }

    // MARK: - cancelAll

    @Test func cancelAllClearsEverything() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        let (loader, _) = makeLoader(cacheDir: dir)

        for i in 0..<10 {
            let url = dir.appendingPathComponent("file\(i).png")
            try createPNG(at: url)
            loader.loadThumbnail(for: url, modificationDate: Date())
        }

        loader.cancelAll()
        // After cancelAll, should be able to load new items
        let url = dir.appendingPathComponent("after-cancel.png")
        try createPNG(at: url)
        loader.loadThumbnail(for: url, modificationDate: Date())
    }

    // MARK: - Concurrency limiting

    @Test func pendingQueueUsedWhenMaxConcurrentReached() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        let (loader, _) = makeLoader(cacheDir: dir)

        // Load more than maxConcurrent (6) items
        for i in 0..<10 {
            let url = dir.appendingPathComponent("concurrent\(i).png")
            try createPNG(at: url)
            loader.loadThumbnail(for: url, modificationDate: Date())
        }
        // Should not crash — excess items go to pending queue
    }

    @Test func pendingItemsLoadAfterActiveComplete() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        let (loader, cache) = makeLoader(cacheDir: dir)

        var urls: [URL] = []
        for i in 0..<8 {
            let url = dir.appendingPathComponent("pending\(i).png")
            try createPNG(at: url, width: 20, height: 20)
            urls.append(url)
        }

        let modDate = Date()
        // Load all — some will be pending
        for url in urls {
            loader.loadThumbnail(for: url, modificationDate: modDate)
        }

        // Await the last one — should eventually complete even if queued
        let lastURL = urls.last!
        let result = await loader.awaitThumbnail(for: lastURL, modificationDate: modDate)
        #expect(result != nil, "Pending items should eventually load")
    }

    // MARK: - Aspect ratio loading

    @Test func loadAspectRatioSetsValueOnViewModel() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        let (loader, _) = makeLoader(cacheDir: dir)

        let url = dir.appendingPathComponent("ratio.png")
        try createPNG(at: url, width: 200, height: 100)

        let vm = DirectoryViewModel()
        loader.loadAspectRatio(for: url, into: vm)

        // Give async task time to complete
        try await Task.sleep(for: .milliseconds(500))

        let ratio = vm.aspectRatios[url]
        #expect(ratio != nil, "Aspect ratio should be set on view model")
        if let ratio {
            #expect(abs(ratio - 2.0) < 0.1, "200x100 image should have ~2.0 aspect ratio")
        }
    }

    @Test func loadAspectRatioSkipsDuplicateURL() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        let (loader, _) = makeLoader(cacheDir: dir)

        let url = dir.appendingPathComponent("dup-ratio.png")
        try createPNG(at: url)

        let vm = DirectoryViewModel()
        loader.loadAspectRatio(for: url, into: vm)
        loader.loadAspectRatio(for: url, into: vm)
        // Second call should be no-op (task already exists)
    }
}
