import SwiftUI
import AppKit

struct SidebarView: View {
    @Environment(NavigationViewModel.self) private var navigationVM
    @Environment(DirectoryViewModel.self) private var directoryVM
    @Environment(SidebarViewModel.self) private var sidebarVM

    var body: some View {
        @Bindable var directoryVM = directoryVM

        List {
            Section {
                TextField("Search", text: $directoryVM.searchText)
                    .textFieldStyle(.roundedBorder)
            }

            Section("Favorites") {
                ForEach(sidebarVM.favorites) { item in
                    SidebarRow(url: item.url, name: item.name, isActive: navigationVM.currentURL == item.url)
                        .contextMenu {
                            Button("Remove from Favorites") {
                                sidebarVM.removeFavorite(id: item.id)
                            }
                        }
                        .draggable(item.url)
                }
                .onMove { source, destination in
                    sidebarVM.moveFavorite(from: source, to: destination)
                }
            }

            Section("Locations") {
                let locations = sidebarVM.systemLocations
                ForEach(Array(locations.indices), id: \.self) { index in
                    let loc = locations[index]
                    SidebarRow(
                        url: loc.url,
                        name: loc.name,
                        systemImage: loc.icon,
                        isActive: navigationVM.currentURL == loc.url
                    )
                }
            }

            Section("Volumes") {
                let vols = sidebarVM.volumes
                ForEach(Array(vols.indices), id: \.self) { index in
                    let vol = vols[index]
                    SidebarRow(
                        url: vol.url,
                        name: vol.name,
                        systemImage: vol.icon,
                        isActive: navigationVM.currentURL == vol.url
                    )
                }
            }
        }
        .listStyle(.sidebar)
        .dropDestination(for: URL.self) { urls, _ in
            for url in urls {
                sidebarVM.addFavoriteIfDirectory(url: url)
            }
            return !urls.isEmpty
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                sidebarVM.addFavorite(url: navigationVM.currentURL)
            } label: {
                Label("Add Current Folder", systemImage: "plus.circle")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.bar)
        }
    }


}

// MARK: - Sidebar Row

private struct SidebarRow: View {
    let url: URL
    let name: String
    var systemImage: String? = nil
    let isActive: Bool

    @Environment(NavigationViewModel.self) private var navigationVM

    var body: some View {
        Button {
            navigationVM.navigate(to: url)
        } label: {
            Label {
                Text(name)
                    .lineLimit(1)
            } icon: {
                if let systemImage {
                    Image(systemName: systemImage)
                        .foregroundStyle(.secondary)
                } else {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                        .resizable()
                        .frame(width: 18, height: 18)
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isActive ? Color.accentColor.opacity(0.2) : Color.clear)
        )
    }
}
