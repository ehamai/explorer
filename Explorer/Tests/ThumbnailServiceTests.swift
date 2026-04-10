import AppKit
import Foundation
import Testing

@testable import Explorer

@Suite("ThumbnailService")
struct ThumbnailServiceTests {

    // MARK: - Helpers

    /// Create a minimal PNG file at the given URL with the specified dimensions.
    private func createPNG(at url: URL, width: Int, height: Int) throws {
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

    // MARK: - ThumbnailCacheKey

    @Test func cacheKeyWithDifferentModDatesAreDifferent() {
        let url = URL(fileURLWithPath: "/test/image.png")
        let key1 = ThumbnailCacheKey(url: url, modificationDate: Date(timeIntervalSince1970: 1000), size: 300)
        let key2 = ThumbnailCacheKey(url: url, modificationDate: Date(timeIntervalSince1970: 2000), size: 300)

        #expect(key1.diskFileName != key2.diskFileName)
    }

    @Test func cacheKeyWithDifferentSizesAreDifferent() {
        let url = URL(fileURLWithPath: "/test/image.png")
        let date = Date(timeIntervalSince1970: 1000)
        let key1 = ThumbnailCacheKey(url: url, modificationDate: date, size: 300)
        let key2 = ThumbnailCacheKey(url: url, modificationDate: date, size: 600)

        #expect(key1.diskFileName != key2.diskFileName)
    }

    @Test func cacheKeySameInputsProduceSameFileName() {
        let url = URL(fileURLWithPath: "/test/image.png")
        let date = Date(timeIntervalSince1970: 1000)
        let key1 = ThumbnailCacheKey(url: url, modificationDate: date, size: 300)
        let key2 = ThumbnailCacheKey(url: url, modificationDate: date, size: 300)

        #expect(key1.diskFileName == key2.diskFileName)
    }

    // MARK: - Disk Cache

    @Test func saveToDiskAndRetrieve() async throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }

        let cacheDir = try TestHelpers.createFolder("cache", in: dir)
        let service = ThumbnailService(cacheDirectory: cacheDir)

        let image = NSImage(size: NSSize(width: 50, height: 50))
        image.lockFocus()
        NSColor.blue.setFill()
        NSBezierPath.fill(NSRect(origin: .zero, size: image.size))
        image.unlockFocus()

        let key = ThumbnailCacheKey(
            url: URL(fileURLWithPath: "/test/photo.png"),
            modificationDate: Date(timeIntervalSince1970: 1000),
            size: 300
        )

        await service.saveToDisk(image: image, key: key)
        let retrieved = await service.getCached(key: key)

        #expect(retrieved != nil)
    }

    // MARK: - Thumbnail Loading

    @Test func loadThumbnailForImageFile() async throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }

        let cacheDir = try TestHelpers.createFolder("cache", in: dir)
        let imageURL = dir.appendingPathComponent("test.png")
        try createPNG(at: imageURL, width: 100, height: 100)

        let service = ThumbnailService(cacheDirectory: cacheDir)
        let modDate = try FileManager.default.attributesOfItem(atPath: imageURL.path)[.modificationDate] as! Date

        let thumbnail = await service.loadThumbnail(for: imageURL, modificationDate: modDate)

        #expect(thumbnail != nil)
    }

    @Test func loadThumbnailForNonexistentFileReturnsNil() async throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }

        let cacheDir = try TestHelpers.createFolder("cache", in: dir)
        let service = ThumbnailService(cacheDirectory: cacheDir)

        let bogusURL = dir.appendingPathComponent("does_not_exist.png")
        let result = await service.loadThumbnail(
            for: bogusURL,
            modificationDate: Date()
        )

        #expect(result == nil)
    }

    // MARK: - Aspect Ratio

    @Test func aspectRatioForImageFile() async throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }

        let imageURL = dir.appendingPathComponent("wide.png")
        try createPNG(at: imageURL, width: 200, height: 100)

        let service = ThumbnailService(cacheDirectory: dir.appendingPathComponent("cache"))
        let ratio = await service.aspectRatio(for: imageURL)

        #expect(ratio != nil)
        if let ratio {
            #expect(abs(ratio - 2.0) < 0.01)
        }
    }

    @Test func aspectRatioCachesResult() async throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }

        let imageURL = dir.appendingPathComponent("square.png")
        try createPNG(at: imageURL, width: 100, height: 100)

        let service = ThumbnailService(cacheDirectory: dir.appendingPathComponent("cache"))
        let first = await service.aspectRatio(for: imageURL)
        let second = await service.aspectRatio(for: imageURL)

        #expect(first != nil)
        #expect(first == second)
    }
}
