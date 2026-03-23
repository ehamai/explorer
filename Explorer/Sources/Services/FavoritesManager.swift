import Foundation
import SwiftUI

struct FavoriteItem: Identifiable, Codable, Equatable {
    let id: UUID
    let url: URL
    let name: String
    let bookmarkData: Data

    init(id: UUID = UUID(), url: URL, name: String, bookmarkData: Data) {
        self.id = id
        self.url = url
        self.name = name
        self.bookmarkData = bookmarkData
    }
}

@Observable
final class FavoritesManager {
    var favorites: [FavoriteItem] = []

    private let storageDirectory: URL
    private var storagePath: URL {
        storageDirectory.appendingPathComponent("favorites.json")
    }

    private static var defaultStorageDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Explorer", isDirectory: true)
    }

    init(storageDirectory: URL? = nil) {
        self.storageDirectory = storageDirectory ?? Self.defaultStorageDirectory
        loadFavorites()
        if favorites.isEmpty {
            loadDefaults()
        }
    }

    func addFavorite(url: URL) {
        guard !favorites.contains(where: { $0.url == url }) else { return }

        do {
            let bookmarkData = try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            let item = FavoriteItem(
                url: url,
                name: url.lastPathComponent,
                bookmarkData: bookmarkData
            )
            favorites.append(item)
            saveFavorites()
        } catch {
            // Fall back to bookmark without security scope for non-sandboxed builds
            let bookmarkData = (try? url.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )) ?? Data()
            let item = FavoriteItem(
                url: url,
                name: url.lastPathComponent,
                bookmarkData: bookmarkData
            )
            favorites.append(item)
            saveFavorites()
        }
    }

    func removeFavorite(id: UUID) {
        favorites.removeAll { $0.id == id }
        saveFavorites()
    }

    func moveFavorite(from source: IndexSet, to destination: Int) {
        favorites.move(fromOffsets: source, toOffset: destination)
        saveFavorites()
    }

    func loadFavorites() {
        let path = storagePath
        guard FileManager.default.fileExists(atPath: path.path) else { return }

        do {
            let data = try Data(contentsOf: path)
            let decoded = try JSONDecoder().decode([FavoriteItem].self, from: data)

            favorites = decoded.compactMap { item in
                var isStale = false
                if let resolvedURL = try? URL(
                    resolvingBookmarkData: item.bookmarkData,
                    options: [.withSecurityScope],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                ) {
                    if isStale {
                        // Re-create bookmark if stale
                        if let newBookmark = try? resolvedURL.bookmarkData(
                            options: [.withSecurityScope],
                            includingResourceValuesForKeys: nil,
                            relativeTo: nil
                        ) {
                            return FavoriteItem(
                                id: item.id,
                                url: resolvedURL,
                                name: item.name,
                                bookmarkData: newBookmark
                            )
                        }
                    }
                    return FavoriteItem(
                        id: item.id,
                        url: resolvedURL,
                        name: item.name,
                        bookmarkData: item.bookmarkData
                    )
                }

                // Try without security scope
                if let resolvedURL = try? URL(
                    resolvingBookmarkData: item.bookmarkData,
                    options: [],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                ) {
                    return FavoriteItem(
                        id: item.id,
                        url: resolvedURL,
                        name: item.name,
                        bookmarkData: item.bookmarkData
                    )
                }

                // Last resort: use the stored URL directly
                return item
            }
        } catch {
            favorites = []
        }
    }

    func saveFavorites() {
        let directory = storageDirectory
        let path = storagePath

        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(favorites)
            try data.write(to: path, options: .atomic)
        } catch {
            // Storage failure is non-fatal; favorites will be recreated next launch
        }
    }

    private func loadDefaults() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let defaultPaths: [(String, URL)] = [
            ("Desktop", home.appendingPathComponent("Desktop")),
            ("Documents", home.appendingPathComponent("Documents")),
            ("Downloads", home.appendingPathComponent("Downloads")),
            (home.lastPathComponent, home)
        ]

        for (name, url) in defaultPaths {
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let bookmarkData = (try? url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )) ?? (try? url.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )) ?? Data()

            let item = FavoriteItem(
                url: url,
                name: name,
                bookmarkData: bookmarkData
            )
            favorites.append(item)
        }
        saveFavorites()
    }
}
