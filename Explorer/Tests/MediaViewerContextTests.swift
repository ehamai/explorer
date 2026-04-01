import Foundation
import Testing
@testable import Explorer

@Suite("MediaViewerContext Tests")
struct MediaViewerContextTests {

    // MARK: - currentIndex

    @Test func currentIndexFindsCorrectPosition() {
        let urls = [
            URL(fileURLWithPath: "/tmp/a.jpg"),
            URL(fileURLWithPath: "/tmp/b.jpg"),
            URL(fileURLWithPath: "/tmp/c.jpg"),
        ]
        let context = MediaViewerContext(fileURL: urls[1], siblingURLs: urls)
        #expect(context.currentIndex == 1)
    }

    @Test func currentIndexReturnsZeroForFirstFile() {
        let urls = [URL(fileURLWithPath: "/tmp/a.jpg"), URL(fileURLWithPath: "/tmp/b.jpg")]
        let context = MediaViewerContext(fileURL: urls[0], siblingURLs: urls)
        #expect(context.currentIndex == 0)
    }

    @Test func currentIndexReturnsLastForLastFile() {
        let urls = [URL(fileURLWithPath: "/tmp/a.jpg"), URL(fileURLWithPath: "/tmp/b.jpg")]
        let context = MediaViewerContext(fileURL: urls[1], siblingURLs: urls)
        #expect(context.currentIndex == 1)
    }

    @Test func currentIndexDefaultsToZeroForMissingFile() {
        let urls = [URL(fileURLWithPath: "/tmp/a.jpg")]
        let context = MediaViewerContext(
            fileURL: URL(fileURLWithPath: "/tmp/missing.jpg"),
            siblingURLs: urls
        )
        #expect(context.currentIndex == 0)
    }

    // MARK: - Codable

    @Test func encodesAndDecodesCorrectly() throws {
        let urls = [
            URL(fileURLWithPath: "/tmp/photo1.jpg"),
            URL(fileURLWithPath: "/tmp/photo2.jpg"),
        ]
        let original = MediaViewerContext(fileURL: urls[0], siblingURLs: urls)

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(MediaViewerContext.self, from: data)

        #expect(decoded.fileURL == original.fileURL)
        #expect(decoded.siblingURLs == original.siblingURLs)
        #expect(decoded.currentIndex == original.currentIndex)
    }

    @Test func encodesWithEmptySiblings() throws {
        let context = MediaViewerContext(
            fileURL: URL(fileURLWithPath: "/tmp/a.jpg"),
            siblingURLs: []
        )

        let data = try JSONEncoder().encode(context)
        let decoded = try JSONDecoder().decode(MediaViewerContext.self, from: data)

        #expect(decoded.siblingURLs.isEmpty)
        #expect(decoded.currentIndex == 0)
    }

    // MARK: - Hashable

    @Test func equalContextsAreEqual() {
        let urls = [URL(fileURLWithPath: "/tmp/a.jpg")]
        let ctx1 = MediaViewerContext(fileURL: urls[0], siblingURLs: urls)
        let ctx2 = MediaViewerContext(fileURL: urls[0], siblingURLs: urls)

        #expect(ctx1 == ctx2)
        #expect(ctx1.hashValue == ctx2.hashValue)
    }

    @Test func differentContextsAreNotEqual() {
        let url1 = URL(fileURLWithPath: "/tmp/a.jpg")
        let url2 = URL(fileURLWithPath: "/tmp/b.jpg")
        let ctx1 = MediaViewerContext(fileURL: url1, siblingURLs: [url1])
        let ctx2 = MediaViewerContext(fileURL: url2, siblingURLs: [url2])

        #expect(ctx1 != ctx2)
    }

    @Test func worksInSet() {
        let urls = [URL(fileURLWithPath: "/tmp/a.jpg")]
        let ctx1 = MediaViewerContext(fileURL: urls[0], siblingURLs: urls)
        let ctx2 = MediaViewerContext(fileURL: urls[0], siblingURLs: urls)

        var set = Set<MediaViewerContext>()
        set.insert(ctx1)
        set.insert(ctx2)
        #expect(set.count == 1)
    }
}
