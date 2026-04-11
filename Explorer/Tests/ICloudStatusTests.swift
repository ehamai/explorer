import Testing
import Foundation
@testable import Explorer

@Suite("ICloudStatus")
struct ICloudStatusTests {

    // MARK: - Symbol Names

    @Test func localHasNoSymbol() {
        #expect(ICloudStatus.local.symbolName == nil)
    }

    @Test func allNonLocalCasesHaveSymbols() {
        let cases: [ICloudStatus] = [
            .current, .cloudOnly,
            .downloading(progress: 0), .uploading(progress: 0),
            .error("test")
        ]
        for status in cases {
            #expect(status.symbolName != nil)
        }
    }

    // MARK: - Labels

    @Test func localHasEmptyLabel() {
        #expect(ICloudStatus.local.label == "")
    }

    @Test func currentLabel() {
        #expect(ICloudStatus.current.label == "Downloaded")
    }

    @Test func cloudOnlyLabel() {
        #expect(ICloudStatus.cloudOnly.label == "In iCloud")
    }

    @Test func downloadingLabelShowsProgress() {
        let status = ICloudStatus.downloading(progress: 0.5)
        #expect(status.label.contains("50%"))
    }

    @Test func uploadingLabelShowsProgress() {
        let status = ICloudStatus.uploading(progress: 0.75)
        #expect(status.label.contains("75%"))
    }

    @Test func errorLabelShowsMessage() {
        let status = ICloudStatus.error("Disk full")
        #expect(status.label.contains("Disk full"))
    }

    // MARK: - Availability

    @Test func localIsAvailableLocally() {
        #expect(ICloudStatus.local.isAvailableLocally)
    }

    @Test func currentIsAvailableLocally() {
        #expect(ICloudStatus.current.isAvailableLocally)
    }

    @Test func uploadingIsAvailableLocally() {
        #expect(ICloudStatus.uploading(progress: 0.5).isAvailableLocally)
    }

    @Test func cloudOnlyIsNotAvailableLocally() {
        #expect(!ICloudStatus.cloudOnly.isAvailableLocally)
    }

    @Test func downloadingIsNotAvailableLocally() {
        #expect(!ICloudStatus.downloading(progress: 0.5).isAvailableLocally)
    }

    @Test func errorIsNotAvailableLocally() {
        #expect(!ICloudStatus.error("test").isAvailableLocally)
    }

    // MARK: - Actions

    @Test func cloudOnlyCanDownload() {
        #expect(ICloudStatus.cloudOnly.canDownload)
    }

    @Test func nonCloudOnlyCannotDownload() {
        #expect(!ICloudStatus.local.canDownload)
        #expect(!ICloudStatus.current.canDownload)
        #expect(!ICloudStatus.downloading(progress: 0).canDownload)
        #expect(!ICloudStatus.uploading(progress: 0).canDownload)
        #expect(!ICloudStatus.error("x").canDownload)
    }

    @Test func currentCanEvict() {
        #expect(ICloudStatus.current.canEvict)
    }

    @Test func nonCurrentCannotEvict() {
        #expect(!ICloudStatus.local.canEvict)
        #expect(!ICloudStatus.cloudOnly.canEvict)
        #expect(!ICloudStatus.downloading(progress: 0).canEvict)
        #expect(!ICloudStatus.uploading(progress: 0).canEvict)
        #expect(!ICloudStatus.error("x").canEvict)
    }

    // MARK: - Equality

    @Test func equalityForSimpleCases() {
        #expect(ICloudStatus.local == ICloudStatus.local)
        #expect(ICloudStatus.current == ICloudStatus.current)
        #expect(ICloudStatus.cloudOnly == ICloudStatus.cloudOnly)
        #expect(ICloudStatus.local != ICloudStatus.current)
    }

    @Test func equalityForAssociatedValues() {
        #expect(ICloudStatus.downloading(progress: 0.5) == ICloudStatus.downloading(progress: 0.5))
        #expect(ICloudStatus.downloading(progress: 0.5) != ICloudStatus.downloading(progress: 0.7))
        #expect(ICloudStatus.uploading(progress: 1.0) == ICloudStatus.uploading(progress: 1.0))
        #expect(ICloudStatus.error("a") == ICloudStatus.error("a"))
        #expect(ICloudStatus.error("a") != ICloudStatus.error("b"))
    }

    // MARK: - Hashable

    @Test func hashableWorksInSets() {
        let set: Set<ICloudStatus> = [.local, .current, .cloudOnly, .local]
        #expect(set.count == 3)
    }
}
