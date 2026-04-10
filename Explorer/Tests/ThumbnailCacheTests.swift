import AppKit
import Foundation
import Testing

@testable import Explorer

@Suite("ThumbnailCache")
struct ThumbnailCacheTests {

    // MARK: - Helpers

    private func makeImage(width: Int = 10, height: Int = 10, color: NSColor = .red) -> NSImage {
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        color.setFill()
        NSBezierPath.fill(NSRect(origin: .zero, size: image.size))
        image.unlockFocus()
        return image
    }

    // MARK: - Tests

    @MainActor @Test func getReturnsNilForUnknownURL() {
        let cache = ThumbnailCache()
        let url = URL(fileURLWithPath: "/nonexistent/file.png")

        #expect(cache.get(for: url) == nil)
    }

    @MainActor @Test func setAndGetRoundTrip() {
        let cache = ThumbnailCache()
        let url = URL(fileURLWithPath: "/test/image.png")
        let image = makeImage()

        cache.set(image, for: url)
        let retrieved = cache.get(for: url)

        #expect(retrieved != nil)
        #expect(retrieved === image)
    }

    @MainActor @Test func loadedURLsTracksInserts() {
        let cache = ThumbnailCache()
        let url = URL(fileURLWithPath: "/test/photo.png")

        #expect(cache.loadedURLs.isEmpty)

        cache.set(makeImage(), for: url)

        #expect(cache.loadedURLs.contains(url))
    }

    @MainActor @Test func clearRemovesEverything() {
        let cache = ThumbnailCache()
        let url = URL(fileURLWithPath: "/test/pic.png")

        cache.set(makeImage(), for: url)
        #expect(cache.get(for: url) != nil)
        #expect(!cache.loadedURLs.isEmpty)

        cache.clear()

        #expect(cache.get(for: url) == nil)
        #expect(cache.loadedURLs.isEmpty)
    }

    @MainActor @Test func differentURLsStoredIndependently() {
        let cache = ThumbnailCache()
        let url1 = URL(fileURLWithPath: "/test/a.png")
        let url2 = URL(fileURLWithPath: "/test/b.png")
        let image1 = makeImage(color: .red)
        let image2 = makeImage(color: .blue)

        cache.set(image1, for: url1)
        cache.set(image2, for: url2)

        #expect(cache.get(for: url1) === image1)
        #expect(cache.get(for: url2) === image2)
    }

    @MainActor @Test func overwriteExistingURL() {
        let cache = ThumbnailCache()
        let url = URL(fileURLWithPath: "/test/image.png")
        let original = makeImage(color: .green)
        let replacement = makeImage(color: .yellow)

        cache.set(original, for: url)
        #expect(cache.get(for: url) === original)

        cache.set(replacement, for: url)
        #expect(cache.get(for: url) === replacement)
    }
}
