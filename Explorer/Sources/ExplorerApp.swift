import SwiftUI
import AppKit

@main
struct ExplorerApp: App {
    @State private var navigationVM = NavigationViewModel()
    @State private var directoryVM = DirectoryViewModel()
    @State private var sidebarVM = SidebarViewModel()
    @State private var clipboardManager = ClipboardManager()
    @State private var favoritesManager = FavoritesManager()

    init() {
        // Required for SPM executables to appear as a proper GUI app
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup {
            MainView()
                .environment(navigationVM)
                .environment(directoryVM)
                .environment(sidebarVM)
                .environment(clipboardManager)
                .environment(favoritesManager)
                .frame(minWidth: 800, minHeight: 500)
        }
        .commands {
            CommandGroup(after: .toolbar) {
                Button("Go Back") {
                    navigationVM.goBack()
                }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(!navigationVM.canGoBack)

                Button("Go Forward") {
                    navigationVM.goForward()
                }
                .keyboardShortcut("]", modifiers: .command)
                .disabled(!navigationVM.canGoForward)

                Button("Enclosing Folder") {
                    navigationVM.goUp()
                }
                .keyboardShortcut(.upArrow, modifiers: .command)
                .disabled(!navigationVM.canGoUp)

                Divider()

                Button("as List") {
                    directoryVM.viewMode = .list
                }
                .keyboardShortcut("1", modifiers: .command)

                Button("as Icons") {
                    directoryVM.viewMode = .icon
                }
                .keyboardShortcut("2", modifiers: .command)

                Button("as Columns") {
                    directoryVM.viewMode = .column
                }
                .keyboardShortcut("3", modifiers: .command)

                Divider()

                Button(directoryVM.showHidden ? "Hide Hidden Files" : "Show Hidden Files") {
                    directoryVM.toggleHidden()
                }
                .keyboardShortcut(".", modifiers: [.command, .shift])
            }

            CommandGroup(replacing: .pasteboard) {
                Button("Cut") {
                    clipboardManager.cut(urls: directoryVM.selectedURLs)
                }
                .keyboardShortcut("x", modifiers: .command)
                .disabled(directoryVM.selectedURLs.isEmpty)

                Button("Copy") {
                    clipboardManager.copy(urls: directoryVM.selectedURLs)
                }
                .keyboardShortcut("c", modifiers: .command)
                .disabled(directoryVM.selectedURLs.isEmpty)

                Button("Paste") {
                    let url = navigationVM.currentURL
                    Task {
                        try? await clipboardManager.paste(to: url)
                        await directoryVM.loadDirectory(url: url)
                    }
                }
                .keyboardShortcut("v", modifiers: .command)
            }

            CommandGroup(replacing: .newItem) {
                Button("New Folder") {
                    createNewFolder()
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            }

            CommandGroup(after: .sidebar) {
                Button("Move to Trash") {
                    moveSelectionToTrash()
                }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(directoryVM.selectedURLs.isEmpty)

                Divider()

                Button("Properties") {
                    directoryVM.showInspector.toggle()
                }
                .keyboardShortcut("i", modifiers: .command)
            }
        }
    }

    private func createNewFolder() {
        let currentURL = navigationVM.currentURL
        var folderURL = currentURL.appendingPathComponent("untitled folder")
        var counter = 1
        while FileManager.default.fileExists(atPath: folderURL.path) {
            folderURL = currentURL.appendingPathComponent("untitled folder \(counter)")
            counter += 1
        }
        try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: false)
        Task { await directoryVM.loadDirectory(url: currentURL) }
    }

    private func moveSelectionToTrash() {
        for url in directoryVM.selectedURLs {
            try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
        }
        let currentURL = navigationVM.currentURL
        Task { await directoryVM.loadDirectory(url: currentURL) }
    }
}
