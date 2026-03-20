import Foundation
import SwiftUI

struct SidebarLocation: Identifiable {
    let id: URL
    let name: String
    let url: URL
    let icon: String

    init(name: String, url: URL, icon: String) {
        self.id = url
        self.name = name
        self.url = url
        self.icon = icon
    }
}

@Observable
final class SidebarViewModel {

    // MARK: - Properties

    private(set) var favorites: [FavoriteItem] = []
    private(set) var volumes: [SidebarLocation] = []

    // MARK: - Dependencies

    private let favoritesManager: FavoritesManager

    // MARK: - Computed Properties

    var systemLocations: [SidebarLocation] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            SidebarLocation(name: "Desktop", url: home.appending(path: "Desktop"), icon: "desktopcomputer"),
            SidebarLocation(name: "Documents", url: home.appending(path: "Documents"), icon: "doc.fill"),
            SidebarLocation(name: "Downloads", url: home.appending(path: "Downloads"), icon: "arrow.down.circle.fill"),
            SidebarLocation(name: "Home", url: home, icon: "house.fill"),
            SidebarLocation(name: "Applications", url: URL(fileURLWithPath: "/Applications"), icon: "square.grid.2x2.fill"),
        ]
    }

    // MARK: - Init

    init(favoritesManager: FavoritesManager = FavoritesManager()) {
        self.favoritesManager = favoritesManager
        syncFavorites()
        refreshVolumes()
    }

    // MARK: - Favorites

    func addFavorite(url: URL) {
        favoritesManager.addFavorite(url: url)
        syncFavorites()
    }

    func removeFavorite(id: UUID) {
        favoritesManager.removeFavorite(id: id)
        syncFavorites()
    }

    func moveFavorite(from source: IndexSet, to destination: Int) {
        favoritesManager.moveFavorite(from: source, to: destination)
        syncFavorites()
    }

    private func syncFavorites() {
        favorites = favoritesManager.favorites
    }

    // MARK: - Volumes

    /// Scan /Volumes for mounted drives, excluding the system volume duplicate.
    func refreshVolumes() {
        let fileManager = FileManager.default
        let volumesURL = URL(fileURLWithPath: "/Volumes")
        var result: [SidebarLocation] = []

        guard let contents = try? fileManager.contentsOfDirectory(
            at: volumesURL,
            includingPropertiesForKeys: [.isVolumeKey, .volumeIsInternalKey],
            options: [.skipsHiddenFiles]
        ) else {
            volumes = []
            return
        }

        let rootVolumeName = (try? URL(fileURLWithPath: "/").resourceValues(
            forKeys: [.volumeNameKey]
        ))?.volumeName

        for volumeURL in contents {
            let name = volumeURL.lastPathComponent

            if let rootName = rootVolumeName, name == rootName {
                if let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: volumeURL.path),
                   destination == "/" {
                    continue
                }
            }

            let isInternal = (try? volumeURL.resourceValues(
                forKeys: [.volumeIsInternalKey]
            ))?.volumeIsInternal ?? false

            let icon = isInternal ? "internaldrive.fill" : "externaldrive.fill"
            result.append(SidebarLocation(name: name, url: volumeURL, icon: icon))
        }

        volumes = result.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
