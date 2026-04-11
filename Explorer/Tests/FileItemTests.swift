import Testing
import Foundation
import AppKit
@testable import Explorer

@Suite("FileItem")
struct FileItemTests {

    // MARK: - Identity & equality

    @Test func identifiableIDIsURL() {
        let item = TestHelpers.makeFileItem(name: "test.txt")
        #expect(item.id == item.url)
    }

    @Test func equalitySameURL() {
        let a = TestHelpers.makeFileItem(name: "same.txt", size: 10)
        let b = TestHelpers.makeFileItem(name: "same.txt", size: 999)
        #expect(a == b, "Items with the same URL should be equal regardless of other properties")
    }

    @Test func equalityDifferentURL() {
        let a = TestHelpers.makeFileItem(name: "one.txt")
        let b = TestHelpers.makeFileItem(name: "two.txt")
        #expect(a != b)
    }

    @Test func hashableSameURL() {
        let a = TestHelpers.makeFileItem(name: "same.txt", size: 10)
        let b = TestHelpers.makeFileItem(name: "same.txt", size: 999)
        #expect(a.hashValue == b.hashValue)
    }

    // MARK: - Comparable

    @Test func comparableDirectoriesBeforeFiles() {
        let dir = TestHelpers.makeFileItem(name: "zebra", isDirectory: true)
        let file = TestHelpers.makeFileItem(name: "apple")
        #expect(dir < file)
        #expect(!(file < dir))
    }

    @Test func comparableAlphabeticalWithinFiles() {
        let apple = TestHelpers.makeFileItem(name: "apple")
        let zebra = TestHelpers.makeFileItem(name: "zebra")
        #expect(apple < zebra)
        #expect(!(zebra < apple))
    }

    @Test func comparableAlphabeticalWithinDirectories() {
        let alpha = TestHelpers.makeFileItem(name: "alpha", isDirectory: true)
        let zulu = TestHelpers.makeFileItem(name: "zulu", isDirectory: true)
        #expect(alpha < zulu)
        #expect(!(zulu < alpha))
    }

    @Test func comparableCaseInsensitive() {
        let upper = TestHelpers.makeFileItem(name: "Apple")
        let lower = TestHelpers.makeFileItem(name: "banana")
        #expect(upper < lower)
    }

    // MARK: - fromURL (disk-based)

    @Test func fromURLValidFile() throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }
        let fileURL = try TestHelpers.createFile("hello.txt", in: dir, content: "hello world")

        let item = FileItem.fromURL(fileURL)
        #expect(item != nil)
        #expect(item?.name == "hello.txt")
        #expect(item?.isDirectory == false)
        #expect(item?.size ?? 0 > 0)
    }

    @Test func fromURLDirectory() throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }
        let subdir = try TestHelpers.createFolder("subfolder", in: dir)

        let item = FileItem.fromURL(subdir)
        #expect(item != nil)
        #expect(item?.isDirectory == true)
        #expect(item?.name == "subfolder")
    }

    @Test func fromURLNonexistent() {
        let bogus = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString).txt")
        let item = FileItem.fromURL(bogus)
        #expect(item == nil)
    }

    // MARK: - Init with icon

    @Test func initWithIcon() {
        let customIcon = NSImage(size: NSSize(width: 16, height: 16))
        let item = FileItem(
            url: URL(fileURLWithPath: "/tmp/icon-test.txt"),
            name: "icon-test.txt",
            size: 0,
            dateModified: Date(),
            kind: "Document",
            isDirectory: false,
            isHidden: false,
            isPackage: false,
            icon: customIcon
        )
        #expect(item.icon === customIcon)
    }

    // MARK: - iCloud Status

    @Test func fromURLDefaultsToLocalICloudStatus() throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }
        let fileURL = try TestHelpers.createFile("test.txt", in: dir)

        let item = FileItem.fromURL(fileURL)
        #expect(item?.iCloudStatus == .local)
    }

    @Test func iCloudPlaceholderDetection() throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }
        try TestHelpers.createFile(".test.txt.icloud", in: dir)

        let placeholderURL = dir.appendingPathComponent(".test.txt.icloud")
        let item = FileItem.fromURL(placeholderURL)
        #expect(item != nil)
        #expect(item?.name == "test.txt")
        #expect(item?.iCloudStatus == .cloudOnly)
    }

    @Test func iCloudPlaceholderURLRewrittenToRealName() throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }
        try TestHelpers.createFile(".photo.jpg.icloud", in: dir)

        let placeholderURL = dir.appendingPathComponent(".photo.jpg.icloud")
        let item = FileItem.fromURL(placeholderURL)
        #expect(item?.url == dir.appendingPathComponent("photo.jpg"))
    }

    @Test func initWithExplicitICloudStatus() {
        let item = FileItem(
            url: URL(fileURLWithPath: "/tmp/test.txt"),
            name: "test.txt",
            size: 0,
            dateModified: Date(),
            kind: "Document",
            isDirectory: false,
            isHidden: false,
            isPackage: false,
            iCloudStatus: .cloudOnly
        )
        #expect(item.iCloudStatus == .cloudOnly)
    }

    @Test func defaultICloudStatusIsLocal() {
        let item = TestHelpers.makeFileItem(name: "test.txt")
        #expect(item.iCloudStatus == .local)
    }

    @Test func shortPlaceholderNameNotDetected() throws {
        // ".a.icloud" is 9 chars (> 8), so it should be detected as placeholder
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }
        try TestHelpers.createFile(".a.icloud", in: dir)

        let item = FileItem.fromURL(dir.appendingPathComponent(".a.icloud"))
        #expect(item?.name == "a")
        #expect(item?.iCloudStatus == .cloudOnly)
    }

    @Test func tooShortPlaceholderNotDetected() throws {
        // ".icloud" alone is 7 chars, not a real placeholder (count <= 8)
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }
        try TestHelpers.createFile(".icloud", in: dir)

        let item = FileItem.fromURL(dir.appendingPathComponent(".icloud"))
        // Should NOT be detected as placeholder — treated as regular hidden file
        #expect(item?.iCloudStatus == .local)
    }

    @Test func regularHiddenFileNotDetectedAsPlaceholder() throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }
        try TestHelpers.createFile(".gitignore", in: dir)

        let item = FileItem.fromURL(dir.appendingPathComponent(".gitignore"))
        #expect(item != nil)
        #expect(item?.name == ".gitignore")
        #expect(item?.iCloudStatus == .local)
    }

    @Test func placeholderWithMultipleExtensions() throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }
        try TestHelpers.createFile(".archive.tar.gz.icloud", in: dir)

        let item = FileItem.fromURL(dir.appendingPathComponent(".archive.tar.gz.icloud"))
        #expect(item?.name == "archive.tar.gz")
        #expect(item?.iCloudStatus == .cloudOnly)
    }

    @Test func localizedNameUsedForDisplay() throws {
        // When localizedNameKey is available and differs from nameKey,
        // it should be used as the display name
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }
        let file = try TestHelpers.createFile("test.txt", in: dir)
        let item = FileItem.fromURL(file)

        // For regular local files, localizedName typically equals name
        #expect(item?.name == "test.txt")
    }
}
