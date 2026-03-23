import Testing
import Foundation
@testable import Explorer

@Suite("FavoritesManager")
struct FavoritesManagerTests {

    @Test func initLoadsDefaults() throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }
        let manager = FavoritesManager(storageDirectory: dir)
        // Defaults include Desktop, Documents, Downloads, Home (if they exist)
        #expect(!manager.favorites.isEmpty)
    }

    @Test func addFavoriteAppendsItem() throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }
        let manager = FavoritesManager(storageDirectory: dir)
        let initialCount = manager.favorites.count

        let folder = try TestHelpers.createFolder("testfav", in: dir)
        manager.addFavorite(url: folder)

        #expect(manager.favorites.count == initialCount + 1)
    }

    @Test func addFavoriteDuplicateRejected() throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }
        let manager = FavoritesManager(storageDirectory: dir)

        let folder = try TestHelpers.createFolder("dup", in: dir)
        manager.addFavorite(url: folder)
        let countAfterFirst = manager.favorites.count

        manager.addFavorite(url: folder)
        #expect(manager.favorites.count == countAfterFirst)
    }

    @Test func addFavoriteSetsCorrectName() throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }
        let manager = FavoritesManager(storageDirectory: dir)

        let folder = try TestHelpers.createFolder("MyFolder", in: dir)
        manager.addFavorite(url: folder)

        let added = manager.favorites.last!
        #expect(added.name == "MyFolder")
    }

    @Test func removeFavoriteByID() throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }
        let manager = FavoritesManager(storageDirectory: dir)

        let folder = try TestHelpers.createFolder("removeme", in: dir)
        manager.addFavorite(url: folder)
        let countAfterAdd = manager.favorites.count
        let addedID = manager.favorites.last!.id

        manager.removeFavorite(id: addedID)
        #expect(manager.favorites.count == countAfterAdd - 1)
    }

    @Test func removeFavoriteNonexistentIDNoOp() throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }
        let manager = FavoritesManager(storageDirectory: dir)
        let count = manager.favorites.count

        manager.removeFavorite(id: UUID())
        #expect(manager.favorites.count == count)
    }

    @Test func moveFavoriteReorders() throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }
        let manager = FavoritesManager(storageDirectory: dir)

        // Clear defaults and add our own items for precise control
        for id in manager.favorites.map(\.id) { manager.removeFavorite(id: id) }

        let f1 = try TestHelpers.createFolder("aaa", in: dir)
        let f2 = try TestHelpers.createFolder("bbb", in: dir)
        let f3 = try TestHelpers.createFolder("ccc", in: dir)
        manager.addFavorite(url: f1)
        manager.addFavorite(url: f2)
        manager.addFavorite(url: f3)
        #expect(manager.favorites.map(\.name) == ["aaa", "bbb", "ccc"])

        // Move first item to end
        manager.moveFavorite(from: IndexSet(integer: 0), to: 3)
        #expect(manager.favorites.map(\.name) == ["bbb", "ccc", "aaa"])
    }

    @Test func persistenceRoundTrip() throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }

        let storageDir = dir.appendingPathComponent("storage")
        try FileManager.default.createDirectory(at: storageDir, withIntermediateDirectories: true)
        let folder = try TestHelpers.createFolder("persist", in: dir)

        let manager1 = FavoritesManager(storageDirectory: storageDir)
        manager1.addFavorite(url: folder)
        let count = manager1.favorites.count
        let addedName = manager1.favorites.last!.name

        // New manager with same storage should load persisted favorites
        let manager2 = FavoritesManager(storageDirectory: storageDir)
        #expect(manager2.favorites.count == count)
        #expect(manager2.favorites.contains { $0.name == addedName })
    }

    @Test func saveFavoritesCreatesDirectory() throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }

        let storageDir = dir.appendingPathComponent("nested").appendingPathComponent("storage")
        // storageDir does not exist yet — init triggers loadDefaults → saveFavorites
        let _ = FavoritesManager(storageDirectory: storageDir)

        #expect(FileManager.default.fileExists(atPath: storageDir.path))
    }

    @Test func saveFavoritesWritesFile() throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }
        let _ = FavoritesManager(storageDirectory: dir)

        let favPath = dir.appendingPathComponent("favorites.json")
        #expect(FileManager.default.fileExists(atPath: favPath.path))
    }

    @Test func loadFavoritesEmptyFileReturnsEmpty() throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }

        let manager = FavoritesManager(storageDirectory: dir)
        #expect(!manager.favorites.isEmpty)

        // Corrupt the favorites file and reload
        let favPath = dir.appendingPathComponent("favorites.json")
        try "not valid json".write(to: favPath, atomically: true, encoding: .utf8)

        manager.loadFavorites()
        #expect(manager.favorites.isEmpty)
    }

    @Test func addFavoriteToEmptyStorage() throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }

        let manager = FavoritesManager(storageDirectory: dir)
        // Remove all defaults to start empty
        for id in manager.favorites.map(\.id) { manager.removeFavorite(id: id) }
        #expect(manager.favorites.isEmpty)

        let folder = try TestHelpers.createFolder("new", in: dir)
        manager.addFavorite(url: folder)
        #expect(manager.favorites.count == 1)
        #expect(manager.favorites.first?.name == "new")
    }

    @Test func favoritesURLsAreCorrect() throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }

        let manager = FavoritesManager(storageDirectory: dir)
        let folder = try TestHelpers.createFolder("urltest", in: dir)
        manager.addFavorite(url: folder)

        let addedFav = manager.favorites.last!
        #expect(addedFav.url.path == folder.path)
        #expect(addedFav.url.lastPathComponent == "urltest")
    }

    @Test func multipleAddRemove() throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }

        let manager = FavoritesManager(storageDirectory: dir)
        for id in manager.favorites.map(\.id) { manager.removeFavorite(id: id) }

        let f1 = try TestHelpers.createFolder("one", in: dir)
        let f2 = try TestHelpers.createFolder("two", in: dir)
        let f3 = try TestHelpers.createFolder("three", in: dir)

        manager.addFavorite(url: f1)
        manager.addFavorite(url: f2)
        manager.addFavorite(url: f3)
        #expect(manager.favorites.count == 3)

        // Remove middle item
        let middleID = manager.favorites[1].id
        manager.removeFavorite(id: middleID)

        #expect(manager.favorites.count == 2)
        #expect(manager.favorites[0].name == "one")
        #expect(manager.favorites[1].name == "three")
    }

    @Test func favoriteItemCodableRoundTrip() throws {
        let id = UUID()
        let url = URL(fileURLWithPath: "/tmp/test-codable")
        let item = FavoriteItem(id: id, url: url, name: "test-codable", bookmarkData: Data([1, 2, 3]))

        let data = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(FavoriteItem.self, from: data)

        #expect(decoded.id == id)
        #expect(decoded.url == url)
        #expect(decoded.name == "test-codable")
        #expect(decoded.bookmarkData == Data([1, 2, 3]))
    }
}
