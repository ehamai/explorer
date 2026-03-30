import SwiftUI

struct StatusBarView: View {
    @Environment(DirectoryViewModel.self) private var directoryVM

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
        directoryVM.availableDiskSpace()
    }
}
