import Foundation
import AppKit

@MainActor
@Observable
final class ThumbnailCache {
    // NSCache for auto-eviction under memory pressure
    private let cache = NSCache<NSString, NSImage>()

    // Tracks which URLs have loaded thumbnails — drives SwiftUI view updates
    private(set) var loadedURLs: Set<URL> = []

    init(countLimit: Int = 2000, totalCostLimitMB: Int = 200) {
        cache.countLimit = countLimit
        cache.totalCostLimit = totalCostLimitMB * 1024 * 1024
    }

    func get(for url: URL) -> NSImage? {
        cache.object(forKey: url.absoluteString as NSString)
    }

    func set(_ image: NSImage, for url: URL) {
        let cost = estimatedCost(of: image)
        cache.setObject(image, forKey: url.absoluteString as NSString, cost: cost)
        loadedURLs.insert(url)
    }

    func clear() {
        cache.removeAllObjects()
        loadedURLs.removeAll()
    }

    private func estimatedCost(of image: NSImage) -> Int {
        guard let rep = image.representations.first else { return 0 }
        return rep.pixelsWide * rep.pixelsHigh * 4
    }
}
