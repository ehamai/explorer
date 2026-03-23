import Testing
import Foundation
@testable import Explorer

@Suite("SidebarViewModel")
struct SidebarViewModelTests {

    @Test func initLoadsFavorites() throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }
        let manager = FavoritesManager(storageDirectory: dir)
        let vm = SidebarViewModel(favoritesManager: manager)
        #expect(!vm.favorites.isEmpty)
    }

    @Test func systemLocationsHasFiveItems() throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }
        let manager = FavoritesManager(storageDirectory: dir)
        let vm = SidebarViewModel(favoritesManager: manager)
        #expect(vm.systemLocations.count == 5)
    }

    @Test func systemLocationsCorrectNames() throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }
        let manager = FavoritesManager(storageDirectory: dir)
        let vm = SidebarViewModel(favoritesManager: manager)
        let names = vm.systemLocations.map(\.name)
        #expect(names == ["Desktop", "Documents", "Downloads", "Home", "Applications"])
    }

    @Test func systemLocationsCorrectIcons() throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }
        let manager = FavoritesManager(storageDirectory: dir)
        let vm = SidebarViewModel(favoritesManager: manager)
        let icons = vm.systemLocations.map(\.icon)
        #expect(icons == [
            "desktopcomputer",
            "doc.fill",
            "arrow.down.circle.fill",
            "house.fill",
            "square.grid.2x2.fill",
        ])
    }

    @Test func addFavoriteDelegatesToManager() throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }
        let manager = FavoritesManager(storageDirectory: dir)
        let vm = SidebarViewModel(favoritesManager: manager)
        let initialCount = vm.favorites.count

        let folder = try TestHelpers.createFolder("sidefav", in: dir)
        vm.addFavorite(url: folder)
        #expect(vm.favorites.count == initialCount + 1)
    }

    @Test func removeFavoriteDelegatesToManager() throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }
        let manager = FavoritesManager(storageDirectory: dir)
        let vm = SidebarViewModel(favoritesManager: manager)

        let folder = try TestHelpers.createFolder("remove", in: dir)
        vm.addFavorite(url: folder)
        let countAfterAdd = vm.favorites.count
        let addedID = vm.favorites.last!.id

        vm.removeFavorite(id: addedID)
        #expect(vm.favorites.count == countAfterAdd - 1)
    }

    @Test func moveFavoriteReorders() throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }
        let manager = FavoritesManager(storageDirectory: dir)
        let vm = SidebarViewModel(favoritesManager: manager)

        let f1 = try TestHelpers.createFolder("first", in: dir)
        let f2 = try TestHelpers.createFolder("second", in: dir)
        vm.addFavorite(url: f1)
        vm.addFavorite(url: f2)

        let lastIdx = vm.favorites.count - 1
        let secondToLast = lastIdx - 1
        let movedName = vm.favorites[secondToLast].name

        vm.moveFavorite(from: IndexSet(integer: secondToLast), to: vm.favorites.count)
        #expect(vm.favorites.last?.name == movedName)
    }

    @Test func syncFavoritesMatchesManager() throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }
        let manager = FavoritesManager(storageDirectory: dir)
        let vm = SidebarViewModel(favoritesManager: manager)

        #expect(vm.favorites.count == manager.favorites.count)

        let folder = try TestHelpers.createFolder("sync", in: dir)
        vm.addFavorite(url: folder)
        #expect(vm.favorites.count == manager.favorites.count)
    }

    @Test func refreshVolumesPopulatesArray() throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }
        let manager = FavoritesManager(storageDirectory: dir)
        let vm = SidebarViewModel(favoritesManager: manager)
        vm.refreshVolumes()
        // Volumes may be empty if only the root volume (symlink to /) exists,
        // but the method should run without error and produce a valid array
        for volume in vm.volumes {
            #expect(!volume.name.isEmpty)
            #expect(!volume.icon.isEmpty)
        }
    }

    @Test func volumesHaveCorrectIconTypes() throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }
        let manager = FavoritesManager(storageDirectory: dir)
        let vm = SidebarViewModel(favoritesManager: manager)
        vm.refreshVolumes()

        for volume in vm.volumes {
            #expect(
                volume.icon == "internaldrive.fill" || volume.icon == "externaldrive.fill",
                "Volume \(volume.name) has unexpected icon: \(volume.icon)"
            )
        }
    }
}
