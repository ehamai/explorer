import AppKit
import AVFoundation
import Foundation
import ImageIO
import QuickLookThumbnailing
import UniformTypeIdentifiers

/// Cache key combining file identity and requested size for deterministic disk lookups.
struct ThumbnailCacheKey: Hashable {
    let url: URL
    let modificationDate: Date
    let size: CGFloat

    /// Deterministic filename derived from path, modification date, and size.
    var diskFileName: String {
        var hasher = Hasher()
        hasher.combine(url.path)
        hasher.combine(modificationDate.timeIntervalSinceReferenceDate)
        hasher.combine(size)
        let hash = hasher.finalize()
        return String(format: "%x.jpg", abs(hash))
    }
}

enum ThumbnailError: Error {
    case generationFailed
}

/// Actor providing thumbnail generation and aspect ratio detection.
///
/// Routing by `UTType`:
/// - Images → `CGImageSource` downsampling (~10x faster than NSImage resize)
/// - Videos → `AVAssetImageGenerator` (frame at 1s mark)
/// - Other  → `QLThumbnailGenerator` (PDFs, etc.)
///
/// Results are cached to disk as JPEG 80% quality with LRU eviction at 500 MB.
actor ThumbnailService {
    private let cacheDirectory: URL
    private var aspectRatioCache: [URL: CGFloat] = [:]

    private static let maxCacheSizeBytes: Int = 500 * 1024 * 1024 // 500 MB

    init(cacheDirectory: URL? = nil) {
        if let cacheDirectory {
            self.cacheDirectory = cacheDirectory
        } else {
            let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            let bundleID = Bundle.main.bundleIdentifier ?? "Explorer"
            self.cacheDirectory = base.appendingPathComponent(bundleID)
                .appendingPathComponent("Thumbnails")
        }
    }

    // MARK: - Public API

    /// Load or generate a thumbnail for the file at `url`.
    ///
    /// Checks the disk cache first; generates and caches on miss.
    func loadThumbnail(
        for url: URL,
        modificationDate: Date,
        size: CGFloat = 300
    ) async -> NSImage? {
        let key = ThumbnailCacheKey(url: url, modificationDate: modificationDate, size: size)

        if let cached = getCached(key: key) {
            return cached
        }

        guard let image = await generateThumbnail(for: url, size: size) else {
            return nil
        }

        saveToDisk(image: image, key: key)
        return image
    }

    /// Throwing convenience used by `ThumbnailLoader`.
    func generateThumbnail(for url: URL, modificationDate: Date, size: CGFloat = 300) async throws -> NSImage {
        guard let image = await loadThumbnail(for: url, modificationDate: modificationDate, size: size) else {
            throw ThumbnailError.generationFailed
        }
        return image
    }

    /// Return the aspect ratio (width / height) for the file at `url`.
    ///
    /// Uses metadata-only reads (no pixel decode). Results are cached in memory.
    func aspectRatio(for url: URL) async -> CGFloat? {
        if let cached = aspectRatioCache[url] {
            return cached
        }

        let ratio = await readAspectRatio(for: url)
        if let ratio {
            aspectRatioCache[url] = ratio
        }
        return ratio
    }

    // MARK: - Disk Cache

    func getCached(key: ThumbnailCacheKey) -> NSImage? {
        let path = cacheDirectory.appendingPathComponent(key.diskFileName)
        guard FileManager.default.fileExists(atPath: path.path) else { return nil }
        return NSImage(contentsOf: path)
    }

    func saveToDisk(image: NSImage, key: ThumbnailCacheKey) {
        let fm = FileManager.default
        if !fm.fileExists(atPath: cacheDirectory.path) {
            try? fm.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        }

        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.8])
        else { return }

        let path = cacheDirectory.appendingPathComponent(key.diskFileName)
        try? jpeg.write(to: path, options: .atomic)
    }

    /// Remove oldest files when cache exceeds 500 MB.
    func evictIfNeeded() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.contentAccessDateKey, .fileSizeKey],
            options: .skipsHiddenFiles
        ) else { return }

        var entries: [(url: URL, accessDate: Date, size: Int)] = []
        var totalSize = 0

        for file in files {
            guard let values = try? file.resourceValues(forKeys: [.contentAccessDateKey, .fileSizeKey]),
                  let size = values.fileSize
            else { continue }
            let accessDate = values.contentAccessDate ?? .distantPast
            entries.append((file, accessDate, size))
            totalSize += size
        }

        guard totalSize > Self.maxCacheSizeBytes else { return }

        // Sort oldest-accessed first for LRU eviction.
        entries.sort { $0.accessDate < $1.accessDate }

        for entry in entries {
            guard totalSize > Self.maxCacheSizeBytes else { break }
            // Cache eviction: permanently delete old cache files (not user data)
            try? fm.removeItem(at: entry.url) // lint:allow
            totalSize -= entry.size
        }
    }

    // MARK: - Thumbnail Generation (Private)

    private func generateThumbnail(for url: URL, size: CGFloat) async -> NSImage? {
        guard let uttype = UTType(filenameExtension: url.pathExtension) else {
            return await generateQuickLookThumbnail(for: url, size: size)
        }

        if uttype.conforms(to: .image) {
            return generateImageThumbnail(for: url, size: size)
        } else if uttype.conforms(to: .movie) || uttype.conforms(to: .video) {
            return await generateVideoThumbnail(for: url, size: size)
        } else {
            return await generateQuickLookThumbnail(for: url, size: size)
        }
    }

    /// Image thumbnail via `CGImageSource` downsampling with EXIF orientation.
    private func generateImageThumbnail(for url: URL, size: CGFloat) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: size,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }

        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    /// Video thumbnail via `AVAssetImageGenerator` at the 1-second mark.
    private func generateVideoThumbnail(for url: URL, size: CGFloat) async -> NSImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.maximumSize = CGSize(width: size, height: size)
        generator.appliesPreferredTrackTransform = true

        let time = CMTime(seconds: 1, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = time
        generator.requestedTimeToleranceAfter = time

        do {
            let (cgImage, _) = try await generator.image(at: time)
            return NSImage(
                cgImage: cgImage,
                size: NSSize(width: cgImage.width, height: cgImage.height)
            )
        } catch {
            return nil
        }
    }

    /// Fallback thumbnail via QuickLook for PDFs, documents, etc.
    private func generateQuickLookThumbnail(for url: URL, size: CGFloat) async -> NSImage? {
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: size, height: size),
            scale: 1.0,
            representationTypes: .thumbnail
        )

        do {
            let thumbnail = try await QLThumbnailGenerator.shared.generateBestRepresentation(
                for: request)
            return thumbnail.nsImage
        } catch {
            return nil
        }
    }

    // MARK: - Aspect Ratio Detection (Private)

    private func readAspectRatio(for url: URL) async -> CGFloat? {
        guard let uttype = UTType(filenameExtension: url.pathExtension) else { return nil }

        if uttype.conforms(to: .image) {
            return imageAspectRatio(for: url)
        } else if uttype.conforms(to: .movie) || uttype.conforms(to: .video) {
            return await videoAspectRatio(for: url)
        }
        return nil
    }

    /// Read image dimensions from metadata without decoding pixels.
    /// Handles EXIF orientation values 5–8 which swap width and height.
    private func imageAspectRatio(for url: URL) -> CGFloat? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? CGFloat,
              let height = props[kCGImagePropertyPixelHeight] as? CGFloat,
              height > 0
        else { return nil }

        let orientation = props[kCGImagePropertyOrientation] as? Int ?? 1
        // EXIF orientation 5–8 rotates 90°/270°, swapping dimensions.
        if orientation >= 5 && orientation <= 8 {
            return height / width
        }
        return width / height
    }

    /// Read video natural size and apply preferred transform for rotation.
    private func videoAspectRatio(for url: URL) async -> CGFloat? {
        let asset = AVURLAsset(url: url)

        do {
            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard let track = tracks.first else { return nil }

            let naturalSize = try await track.load(.naturalSize)
            let transform = try await track.load(.preferredTransform)

            let transformed = naturalSize.applying(transform)
            let width = abs(transformed.width)
            let height = abs(transformed.height)

            guard height > 0 else { return nil }
            return width / height
        } catch {
            return nil
        }
    }
}
