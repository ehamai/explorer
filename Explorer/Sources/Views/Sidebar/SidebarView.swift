import SwiftUI
import AppKit

struct SidebarView: View {
    @Environment(NavigationViewModel.self) private var navigationVM
    @Environment(SidebarViewModel.self) private var sidebarVM

    var body: some View {
        List {
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
                ForEach(sidebarVM.systemLocations) { item in
                    SidebarRow(
                        url: item.url,
                        name: item.name,
                        systemImage: systemImageForLocation(item.url),
                        isActive: navigationVM.currentURL == item.url
                    )
                }
            }

            Section("Volumes") {
                ForEach(sidebarVM.volumes) { item in
                    SidebarRow(
                        url: item.url,
                        name: item.name,
                        systemImage: "externaldrive",
                        isActive: navigationVM.currentURL == item.url
                    )
                }
            }
        }
        .listStyle(.sidebar)
        .dropDestination(for: URL.self) { urls, _ in
            for url in urls {
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                    sidebarVM.addFavorite(url: url)
                }
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

    private func systemImageForLocation(_ url: URL) -> String {
        let path = url.path
        if path.hasSuffix("/Desktop") { return "menubar.dock.rectangle" }
        if path.hasSuffix("/Documents") { return "doc.text" }
        if path.hasSuffix("/Downloads") { return "arrow.down.circle" }
        if path == FileManager.default.homeDirectoryForCurrentUser.path { return "house" }
        if path.hasSuffix("/Applications") { return "square.grid.2x2" }
        return "folder"
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
