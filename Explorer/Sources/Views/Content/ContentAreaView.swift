import SwiftUI

struct ContentAreaView: View {
    @Environment(DirectoryViewModel.self) private var directoryVM

    var body: some View {
        ZStack {
            if directoryVM.isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Loading…")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if directoryVM.items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "folder")
                        .font(.system(size: 48))
                        .foregroundStyle(.quaternary)
                    Text("Empty Folder")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                switch directoryVM.viewMode {
                case .list:
                    FileListView()
                case .icon:
                    IconGridView()
                case .column:
                    ColumnBrowserView()
                }
            }
        }
    }
}

// MARK: - Column Browser View

/// A single-column list view serving as the column view mode.
/// Navigating into folders replaces the list content via the NavigationViewModel.
private struct ColumnBrowserView: View {
    @Environment(DirectoryViewModel.self) private var directoryVM
    @Environment(NavigationViewModel.self) private var navigationVM
    @Environment(ClipboardManager.self) private var clipboardManager

    var body: some View {
        @Bindable var directoryVM = directoryVM

        List(selection: $directoryVM.selectedItems) {
            ForEach(directoryVM.items) { item in
                HStack(spacing: 8) {
                    FileIconView(item: item, size: 18)

                    Text(item.name)
                        .lineLimit(1)

                    Spacer()

                    if item.isDirectory {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .opacity(isCut(item) ? 0.4 : 1.0)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    open(item)
                }
                .tag(item.id)
            }
        }
        .listStyle(.plain)
    }

    private func isCut(_ item: FileItem) -> Bool {
        clipboardManager.isCut && clipboardManager.sourceURLs.contains(item.url)
    }

    private func open(_ item: FileItem) {
        if item.isDirectory {
            navigationVM.navigate(to: item.url)
        } else {
            NSWorkspace.shared.open(item.url)
        }
    }
}
