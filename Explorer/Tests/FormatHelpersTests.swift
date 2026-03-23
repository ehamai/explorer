import Testing
import Foundation
@testable import Explorer

@Suite("FormatHelpers")
struct FormatHelpersTests {

    // MARK: - formatFileSize

    @Test func formatFileSizeZeroBytes() {
        let result = FormatHelpers.formatFileSize(0)
        #expect(result == "Zero KB")
    }

    @Test func formatFileSizeKilobytes() {
        let result = FormatHelpers.formatFileSize(1_500)
        #expect(result.contains("KB"))
    }

    @Test func formatFileSizeMegabytes() {
        let result = FormatHelpers.formatFileSize(2_500_000)
        #expect(result.contains("MB"))
    }

    @Test func formatFileSizeGigabytes() {
        let result = FormatHelpers.formatFileSize(3_000_000_000)
        #expect(result.contains("GB"))
    }

    // MARK: - formatDate

    @Test func formatDateRecent() {
        let twoHoursAgo = Date().addingTimeInterval(-2 * 60 * 60)
        let result = FormatHelpers.formatDate(twoHoursAgo)
        #expect(!result.isEmpty)
        // Relative format should not contain a year
        #expect(!result.contains("20"))
    }

    @Test func formatDateOld() {
        let oldDate = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        let result = FormatHelpers.formatDate(oldDate)
        let year = Calendar.current.component(.year, from: oldDate)
        #expect(result.contains(String(year)))
    }

    @Test func formatDateFuture() {
        let futureDate = Calendar.current.date(byAdding: .day, value: 30, to: Date())!
        let result = FormatHelpers.formatDate(futureDate)
        let year = Calendar.current.component(.year, from: futureDate)
        #expect(result.contains(String(year)))
    }

    // MARK: - fileKindDescription

    @Test func fileKindDescriptionForDirectory() throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }

        let kind = FormatHelpers.fileKindDescription(for: dir)
        #expect(kind.lowercased() == "folder")
    }

    @Test func fileKindDescriptionForTextFile() throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }
        let file = try TestHelpers.createFile("sample.txt", in: dir)

        let kind = FormatHelpers.fileKindDescription(for: file)
        #expect(!kind.isEmpty)
    }

    @Test func fileKindDescriptionForUnknownExtension() {
        // macOS assigns dynamic UTTypes even for unknown extensions,
        // so verify a non-empty result is returned gracefully.
        let url = URL(fileURLWithPath: "/tmp/nonexistent-\(UUID().uuidString).qzx7")
        let kind = FormatHelpers.fileKindDescription(for: url)
        #expect(!kind.isEmpty)
    }

    @Test func fileKindDescriptionForNoExtension() {
        let url = URL(fileURLWithPath: "/tmp/nonexistent-\(UUID().uuidString)")
        let kind = FormatHelpers.fileKindDescription(for: url)
        #expect(kind == "Document")
    }
}
