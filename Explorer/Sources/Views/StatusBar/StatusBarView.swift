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

            if directoryVM.viewMode == .mosaic {
                mosaicZoomSlider
            }

            if let space = availableDiskSpace {
                Text("\(FormatHelpers.formatFileSize(space)) available")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var mosaicZoomSlider: some View {
        @Bindable var directoryVM = directoryVM
        HStack(spacing: 4) {
            Image(systemName: "minus.magnifyingglass")
                .font(.caption2)
            Slider(
                value: Binding(
                    get: { directoryVM.mosaicZoom },
                    set: { newValue in
                        withAnimation(.easeInOut(duration: 0.15)) {
                            directoryVM.mosaicZoom = newValue
                        }
                    }
                ),
                in: DirectoryViewModel.mosaicZoomRange,
                step: 10
            )
            .frame(width: 100)
            Image(systemName: "plus.magnifyingglass")
                .font(.caption2)
        }
    }

    private var availableDiskSpace: Int64? {
        directoryVM.availableDiskSpace()
    }
}
