import Foundation
import AppKit

@MainActor
@Observable
final class ThumbnailLoader {
    private let service: ThumbnailService
    private let cache: ThumbnailCache
    private var activeTasks: [URL: Task<Void, Never>] = [:]
    private var activeCount = 0
    private let maxConcurrent = 6
    private var pendingQueue: [(url: URL, modificationDate: Date)] = []
    private var waiters: [URL: [CheckedContinuation<NSImage?, Never>]] = [:]

    init(service: ThumbnailService = ThumbnailService(), cache: ThumbnailCache) {
        self.service = service
        self.cache = cache
    }

    /// Fire-and-forget thumbnail load. Use `awaitThumbnail` for async waiting.
    func loadThumbnail(for url: URL, modificationDate: Date) {
        if activeTasks[url] != nil { return }
        if cache.get(for: url) != nil { return }

        if activeCount < maxConcurrent {
            startLoad(for: url, modificationDate: modificationDate)
        } else {
            pendingQueue.removeAll { $0.url == url }
            pendingQueue.append((url: url, modificationDate: modificationDate))
        }
    }

    /// Async thumbnail load that returns the image when ready.
    /// Checks cache first, then queues generation and awaits the result.
    func awaitThumbnail(for url: URL, modificationDate: Date) async -> NSImage? {
        // Fast path: already cached
        if let cached = cache.get(for: url) { return cached }

        // Ensure loading is in progress
        loadThumbnail(for: url, modificationDate: modificationDate)

        // Wait for completion via continuation
        return await withCheckedContinuation { continuation in
            if waiters[url] != nil {
                waiters[url]!.append(continuation)
            } else {
                waiters[url] = [continuation]
            }
        }
    }

    func cancelThumbnail(for url: URL) {
        activeTasks[url]?.cancel()
        if activeTasks.removeValue(forKey: url) != nil {
            activeCount -= 1
            processNext()
        }
        pendingQueue.removeAll { $0.url == url }
        resumeWaiters(for: url, with: nil)
    }

    func cancelAll() {
        for task in activeTasks.values {
            task.cancel()
        }
        activeTasks.removeAll()
        activeCount = 0
        pendingQueue.removeAll()
        for task in aspectRatioTasks.values {
            task.cancel()
        }
        aspectRatioTasks.removeAll()
        // Resume all waiters with nil
        for (_, continuations) in waiters {
            for c in continuations { c.resume(returning: nil) }
        }
        waiters.removeAll()
    }

    private var aspectRatioTasks: [URL: Task<Void, Never>] = [:]

    func loadAspectRatio(for url: URL, into viewModel: DirectoryViewModel) {
        guard aspectRatioTasks[url] == nil else { return }
        let task = Task {
            let ratio = await service.aspectRatio(for: url)
            if !Task.isCancelled, let ratio {
                viewModel.setAspectRatio(ratio, for: url)
            }
            aspectRatioTasks.removeValue(forKey: url)
        }
        aspectRatioTasks[url] = task
    }

    func loadAspectRatios(for items: [FileItem], into viewModel: DirectoryViewModel) {
        for item in items {
            let mediaType = MediaFileType.detect(from: item.url)
            guard mediaType.isMedia, viewModel.aspectRatios[item.url] == nil else { continue }
            loadAspectRatio(for: item.url, into: viewModel)
        }
    }

    // MARK: - Private

    private func startLoad(for url: URL, modificationDate: Date) {
        activeCount += 1
        let task = Task {
            var loadedImage: NSImage?
            do {
                let image = try await service.generateThumbnail(for: url, modificationDate: modificationDate)
                if !Task.isCancelled {
                    cache.set(image, for: url)
                    loadedImage = image
                }
            } catch {
                // Thumbnail generation failed
            }
            activeTasks.removeValue(forKey: url)
            activeCount -= 1
            resumeWaiters(for: url, with: loadedImage)
            processNext()
        }
        activeTasks[url] = task
    }

    private func resumeWaiters(for url: URL, with image: NSImage?) {
        guard let continuations = waiters.removeValue(forKey: url) else { return }
        for continuation in continuations {
            continuation.resume(returning: image)
        }
    }

    private func processNext() {
        while activeCount < maxConcurrent, !pendingQueue.isEmpty {
            let next = pendingQueue.removeFirst()
            if cache.get(for: next.url) != nil { continue }
            if activeTasks[next.url] != nil { continue }
            startLoad(for: next.url, modificationDate: next.modificationDate)
        }
    }
}
