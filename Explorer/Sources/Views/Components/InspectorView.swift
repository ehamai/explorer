import SwiftUI
import AppKit

struct InspectorView: View {
    @Environment(DirectoryViewModel.self) private var directoryVM

    @State private var folderCount: Int?

    var body: some View {
        Group {
            if let item = directoryVM.inspectedItem {
                ScrollView {
                    VStack(spacing: 20) {
                        fileHeader(item)
                        Divider()
                        fileDetails(item)
                        Divider()
                        filePermissions(item)
                    }
                    .padding(16)
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 36))
                        .foregroundStyle(.quaternary)
                    Text("No Selection")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("Select a file to see its properties")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 220)
    }

    // MARK: - Header

    @ViewBuilder
    private func fileHeader(_ item: FileItem) -> some View {
        VStack(spacing: 10) {
            FileIconView(item: item, size: 64)

            Text(item.name)
                .font(.headline)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            Text(item.kind)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Details

    @ViewBuilder
    private func fileDetails(_ item: FileItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Information")
                .font(.headline)

            propertyRow(label: "Kind", value: item.kind)

            if !item.isDirectory {
                propertyRow(label: "Size", value: FormatHelpers.formatFileSize(item.size))
            } else {
                propertyRow(label: "Size", value: folderSizeText)
                    .task(id: item.url) {
                        folderCount = await directoryVM.folderItemCount(at: item.url)
                    }
            }

            propertyRow(label: "Modified", value: fullDateString(item.dateModified))
            propertyRow(label: "Created", value: createdDate(item))
            propertyRow(label: "Path", value: item.url.path)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Permissions

    @ViewBuilder
    private func filePermissions(_ item: FileItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Details")
                .font(.headline)

            propertyRow(label: "Hidden", value: item.isHidden ? "Yes" : "No")

            if let posix = posixPermissions(item) {
                propertyRow(label: "Permissions", value: posix)
            }

            if let owner = fileOwner(item) {
                propertyRow(label: "Owner", value: owner)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func propertyRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout)
                .textSelection(.enabled)
                .lineLimit(3)
        }
    }

    private static let fullDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    private func fullDateString(_ date: Date) -> String {
        Self.fullDateFormatter.string(from: date)
    }

    private func createdDate(_ item: FileItem) -> String {
        guard let values = try? item.url.resourceValues(forKeys: [.creationDateKey]),
              let created = values.creationDate else {
            return "Unknown"
        }
        return fullDateString(created)
    }

    private var folderSizeText: String {
        guard let count = folderCount else { return "--" }
        return "\(count) \(count == 1 ? "item" : "items")"
    }

    private func posixPermissions(_ item: FileItem) -> String? {
        directoryVM.fileAttributes(at: item.url).posixPermissions
    }

    private func fileOwner(_ item: FileItem) -> String? {
        directoryVM.fileAttributes(at: item.url).owner
    }
}
