import SwiftUI

struct StatusBarView: View {
    @Environment(DirectoryViewModel.self) private var directoryVM
    @Environment(NavigationViewModel.self) private var navigationVM

    var body: some View {
        HStack(spacing: 12) {
            let count = directoryVM.items.count
            Text("\(count) \(count == 1 ? "item" : "items")")

            if !directoryVM.selectedItems.isEmpty {
                Text("·")
                    .foregroundStyle(.quaternary)
                let selected = directoryVM.selectedItems.count
                Text("\(selected) selected")
            }

            Spacer()

            if let space = availableDiskSpace {
                Text("\(FormatHelpers.formatFileSize(space)) available")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var availableDiskSpace: Int64? {
        let url = navigationVM.currentURL
        guard let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let capacity = values.volumeAvailableCapacityForImportantUsage else {
            // Fall back to the older API
            guard let attrs = try? FileManager.default.attributesOfFileSystem(forPath: url.path),
                  let freeSize = attrs[.systemFreeSize] as? Int64 else {
                return nil
            }
            return freeSize
        }
        return capacity
    }
}
