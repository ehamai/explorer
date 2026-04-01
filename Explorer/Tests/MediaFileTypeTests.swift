import Foundation
import Testing
@testable import Explorer

@Suite("MediaFileType Tests")
struct MediaFileTypeTests {

    // MARK: - Extension-based detection

    @Test func imageExtensionsDetectedCorrectly() {
        let imageExts = ["jpg", "jpeg", "png", "gif", "tiff", "tif", "bmp",
                         "heic", "heif", "webp", "ico", "svg", "raw", "cr2",
                         "nef", "arw", "dng"]
        for ext in imageExts {
            let result = MediaFileType.fromExtension(ext)
            #expect(result == .image, "Expected .image for extension '\(ext)', got \(result)")
        }
    }

    @Test func videoExtensionsDetectedCorrectly() {
        let videoExts = ["mp4", "mov", "m4v", "avi", "mkv", "wmv", "flv",
                         "webm", "mpeg", "mpg", "3gp"]
        for ext in videoExts {
            let result = MediaFileType.fromExtension(ext)
            #expect(result == .video, "Expected .video for extension '\(ext)', got \(result)")
        }
    }

    @Test func unsupportedExtensionsReturnUnsupported() {
        let unsupported = ["txt", "pdf", "doc", "swift", "json", "zip", ""]
        for ext in unsupported {
            let result = MediaFileType.fromExtension(ext)
            #expect(result == .unsupported, "Expected .unsupported for extension '\(ext)', got \(result)")
        }
    }

    @Test func extensionDetectionIsCaseInsensitive() {
        #expect(MediaFileType.fromExtension("JPG") == .image)
        #expect(MediaFileType.fromExtension("Png") == .image)
        #expect(MediaFileType.fromExtension("MP4") == .video)
        #expect(MediaFileType.fromExtension("Mov") == .video)
    }

    @Test func isMediaProperty() {
        #expect(MediaFileType.image.isMedia == true)
        #expect(MediaFileType.video.isMedia == true)
        #expect(MediaFileType.unsupported.isMedia == false)
    }

    // MARK: - URL-based detection with real files

    @Test func detectImageFromRealFile() throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }

        let jpgFile = try TestHelpers.createFile("photo.jpg", in: dir)
        let pngFile = try TestHelpers.createFile("icon.png", in: dir)

        // Real file detection uses UTType which may return image or fall back to extension
        let jpgType = MediaFileType.detect(from: jpgFile)
        let pngType = MediaFileType.detect(from: pngFile)

        #expect(jpgType == .image)
        #expect(pngType == .image)
    }

    @Test func detectVideoFromRealFile() throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }

        let mp4File = try TestHelpers.createFile("video.mp4", in: dir)
        let movFile = try TestHelpers.createFile("clip.mov", in: dir)

        let mp4Type = MediaFileType.detect(from: mp4File)
        let movType = MediaFileType.detect(from: movFile)

        #expect(mp4Type == .video)
        #expect(movType == .video)
    }

    @Test func detectUnsupportedFromRealFile() throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }

        let txtFile = try TestHelpers.createFile("readme.txt", in: dir)
        let result = MediaFileType.detect(from: txtFile)
        #expect(result == .unsupported)
    }

    @Test func detectDirectoryReturnsUnsupported() throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }

        let folder = try TestHelpers.createFolder("subdir", in: dir)
        let result = MediaFileType.detect(from: folder)
        #expect(result == .unsupported)
    }

    @Test func detectNonExistentFileUsesExtensionFallback() {
        let fakeURL = URL(fileURLWithPath: "/nonexistent/photo.jpg")
        let result = MediaFileType.detect(from: fakeURL)
        #expect(result == .image)
    }
}
