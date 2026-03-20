import SwiftUI
import AppKit

@main
struct ExplorerApp: App {
    @State private var tabManager = TabManager()
    @State private var sidebarVM = SidebarViewModel()
    @State private var clipboardManager = ClipboardManager()
    @State private var favoritesManager = FavoritesManager()

    private var activeNav: NavigationViewModel? { tabManager.activeTab?.navigationVM }
    private var activeDir: DirectoryViewModel? { tabManager.activeTab?.directoryVM }

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup {
            MainView()
                .environment(tabManager)
                .environment(sidebarVM)
                .environment(clipboardManager)
                .environment(favoritesManager)
                .frame(minWidth: 800, minHeight: 500)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Tab") {
                    tabManager.addTab()
                }
                .keyboardShortcut("t", modifiers: .command)

                Button("Close Tab") {
                    if tabManager.tabs.count > 1 {
                        tabManager.closeActiveTab()
                    } else {
                        NSApp.keyWindow?.close()
                    }
                }
                .keyboardShortcut("w", modifiers: .command)

                Divider()

                Button("New Folder") {
                    createNewFolder()
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            }

            CommandGroup(after: .toolbar) {
                Button("Go Back") {
                    activeNav?.goBack()
                }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(activeNav?.canGoBack != true)

                Button("Go Forward") {
                    activeNav?.goForward()
                }
                .keyboardShortcut("]", modifiers: .command)
                .disabled(activeNav?.canGoForward != true)

                Button("Enclosing Folder") {
                    activeNav?.goUp()
                }
                .keyboardShortcut(.upArrow, modifiers: .command)
                .disabled(activeNav?.canGoUp != true)

                Divider()

                Button("as List") { activeDir?.viewMode = .list }
                    .keyboardShortcut("1", modifiers: .command)

                Button("as Icons") { activeDir?.viewMode = .icon }
                    .keyboardShortcut("2", modifiers: .command)

                Button("as Columns") { activeDir?.viewMode = .column }
                    .keyboardShortcut("3", modifiers: .command)

                Divider()

                Button(activeDir?.showHidden == true ? "Hide Hidden Files" : "Show Hidden Files") {
                    activeDir?.toggleHidden()
                }
                .keyboardShortcut(".", modifiers: [.command, .shift])
            }

            CommandGroup(replacing: .pasteboard) {
                Button("Cut") {
                    if let urls = activeDir?.selectedURLs, !urls.isEmpty {
                        clipboardManager.cut(urls: urls)
                    }
                }
                .keyboardShortcut("x", modifiers: .command)
                .disabled(activeDir?.selectedURLs.isEmpty != false)

                Button("Copy") {
                    if let urls = activeDir?.selectedURLs, !urls.isEmpty {
                        clipboardManager.copy(urls: urls)
                    }
                }
                .keyboardShortcut("c", modifiers: .command)
                .disabled(activeDir?.selectedURLs.isEmpty != false)

                Button("Paste") {
                    guard let nav = activeNav, let dir = activeDir else { return }
                    let url = nav.currentURL
                    Task {
                        try? await clipboardManager.paste(to: url)
                        await dir.loadDirectory(url: url)
                    }
                }
                .keyboardShortcut("v", modifiers: .command)
                .disabled(!clipboardManager.hasPendingOperation)
            }

            CommandGroup(after: .sidebar) {
                Button("Move to Trash") {
                    moveSelectionToTrash()
                }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(activeDir?.selectedURLs.isEmpty != false)

                Divider()

                Button("Properties") {
                    activeDir?.showInspector.toggle()
                }
                .keyboardShortcut("i", modifiers: .command)
            }
        }
    }

    private func createNewFolder() {
        guard let nav = activeNav, let dir = activeDir else { return }
        let currentURL = nav.currentURL
        var folderURL = currentURL.appendingPathComponent("untitled folder")
        var counter = 1
        while FileManager.default.fileExists(atPath: folderURL.path) {
            folderURL = currentURL.appendingPathComponent("untitled folder \(counter)")
            counter += 1
        }
        try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: false)
        Task { await dir.loadDirectory(url: currentURL) }
    }

    private func moveSelectionToTrash() {
        guard let nav = activeNav, let dir = activeDir else { return }
        for url in dir.selectedURLs {
            try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
        }
        let currentURL = nav.currentURL
        Task { await dir.loadDirectory(url: currentURL) }
    }
}
