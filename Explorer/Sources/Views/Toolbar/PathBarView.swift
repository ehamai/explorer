import SwiftUI
import AppKit

struct PathBarView: View {
    @Environment(NavigationViewModel.self) private var navigationVM
    @Environment(SplitScreenManager.self) private var splitManager

    @State private var isEditing = false
    @State private var editText = ""
    @State private var showError = false
    @State private var dropTargetURL: URL?
    @FocusState private var textFieldFocused: Bool

    var body: some View {
        Group {
            if isEditing {
                editablePathField
            } else {
                breadcrumbView
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: navigationVM.currentURL) { _, _ in
            // Exit edit mode when navigation changes
            isEditing = false
        }
    }

    // MARK: - Breadcrumb Mode

    private var breadcrumbView: some View {
        let components = navigationVM.pathComponents
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(Array(components.indices), id: \.self) { index in
                    let comp = components[index]
                    let isLast = index == components.count - 1

                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    Button {
                        navigationVM.navigate(to: comp.url)
                    } label: {
                        HStack(spacing: 4) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: comp.url.path))
                                .resizable()
                                .frame(width: 14, height: 14)

                            Text(displayName(comp.name, url: comp.url))
                                .font(.callout)
                                .fontWeight(isLast ? .semibold : .regular)
                                .foregroundStyle(isLast ? .primary : .secondary)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(dropTargetURL == comp.url
                                  ? Color.accentColor.opacity(0.3)
                                  : Color.primary.opacity(0.001))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(dropTargetURL == comp.url
                                          ? Color.accentColor : Color.clear, lineWidth: 1.5)
                    )
                    .dropDestination(for: URL.self) { urls, _ in
                        guard !urls.contains(comp.url) else { return false }
                        performMove(urls, to: comp.url)
                        return true
                    } isTargeted: { isTargeted in
                        dropTargetURL = isTargeted ? comp.url : nil
                    }
                    .onHover { hovering in
                        if hovering {
                            NSCursor.pointingHand.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            enterEditMode()
        }
    }

    // MARK: - Text Field Mode

    private var editablePathField: some View {
        TextField("Enter path…", text: $editText)
            .textFieldStyle(.roundedBorder)
            .font(.callout.monospaced())
            .focused($textFieldFocused)
            .onSubmit {
                submitPath()
            }
            .onExitCommand {
                isEditing = false
            }
            .onAppear {
                textFieldFocused = true
            }
            .onChange(of: textFieldFocused) { _, focused in
                if !focused {
                    isEditing = false
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(showError ? Color.red : Color.clear, lineWidth: 1.5)
            )
    }

    // MARK: - Actions

    private func enterEditMode() {
        editText = navigationVM.currentURL.path
        showError = false
        isEditing = true
    }

    private func submitPath() {
        var path = editText.trimmingCharacters(in: .whitespaces)
        guard !path.isEmpty else {
            isEditing = false
            return
        }

        // Expand ~ to home directory
        if path.hasPrefix("~") {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            path = home + path.dropFirst()
        }

        let url = URL(fileURLWithPath: path).standardizedFileURL
        let fm = FileManager.default
        var isDir: ObjCBool = false

        if fm.fileExists(atPath: url.path, isDirectory: &isDir) {
            if isDir.boolValue {
                navigationVM.navigate(to: url)
            } else {
                NSWorkspace.shared.open(url)
            }
            isEditing = false
        } else {
            // Path doesn't exist — flash red border
            showError = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                showError = false
            }
        }
    }

    // MARK: - Helpers

    private func performMove(_ urls: [URL], to destination: URL) {
        let validURLs = FileMoveService.validURLsForFolderDrop(urls, destination: destination)
        guard !validURLs.isEmpty else { return }
        let currentURL = navigationVM.currentURL
        FileMoveService.moveItems(validURLs, to: destination)
        Task {
            await splitManager.reloadAllPanes(showing: currentURL)
            await splitManager.reloadAllPanes(showing: destination)
        }
    }

    private func displayName(_ name: String, url: URL) -> String {
        if name == "/" || name.isEmpty {
            return volumeName(for: url)
        }
        return name
    }

    private func volumeName(for url: URL) -> String {
        if let values = try? url.resourceValues(forKeys: [.volumeNameKey]),
           let volumeName = values.volumeName {
            return volumeName
        }
        return "Macintosh HD"
    }
}
