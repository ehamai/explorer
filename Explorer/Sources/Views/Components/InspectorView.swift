import SwiftUI
import AppKit

struct InspectorView: View {
    @Environment(DirectoryViewModel.self) private var directoryVM

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
                propertyRow(label: "Size", value: folderSize(item))
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

    private func folderSize(_ item: FileItem) -> String {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: item.url,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return "--"
        }
        let count = contents.count
        return "\(count) \(count == 1 ? "item" : "items")"
    }

    private func posixPermissions(_ item: FileItem) -> String? {
        guard let values = try? item.url.resourceValues(forKeys: [.fileSecurityKey]),
              let security = values.fileSecurity else { return nil }
        var mode: mode_t = 0
        CFFileSecurityGetMode(security as CFFileSecurity, &mode)
        return String(format: "%o", mode & 0o777)
    }

    private func fileOwner(_ item: FileItem) -> String? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: item.url.path),
              let owner = attrs[.ownerAccountName] as? String else { return nil }
        return owner
    }
}
