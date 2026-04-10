import SwiftUI
import AppKit

struct MosaicThumbnailView: View {
    let layoutItem: MosaicLayoutItem
    let fileItem: FileItem
    let isSelected: Bool
    let isCut: Bool

    @Environment(ThumbnailCache.self) private var thumbnailCache
    @Environment(ThumbnailLoader.self) private var thumbnailLoader

    @State private var thumbnail: NSImage?

    @State private var folderCount: Int?

    var body: some View {
        Group {
            if layoutItem.isMedia {
                mediaCell
            } else {
                nonMediaCell
            }
        }
        .opacity(isCut ? 0.4 : 1.0)
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
            }
        }
        .contentShape(Rectangle())
    }

    // MARK: - Media Cell

    @ViewBuilder
    private var mediaCell: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.black

            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: layoutItem.width, height: layoutItem.height)
            } else {
                // Placeholder while loading
                Image(nsImage: fileItem.icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: min(64, layoutItem.width * 0.5),
                           height: min(64, layoutItem.height * 0.5))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Video badge
            if MediaFileType.detect(from: fileItem.url) == .video {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: min(28, layoutItem.height * 0.15)))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
                    .padding(6)
            }
        }
        .task(id: fileItem.url) {
            if let cached = thumbnailCache.get(for: fileItem.url) {
                thumbnail = cached
                return
            }
            let image = await thumbnailLoader.awaitThumbnail(
                for: fileItem.url,
                modificationDate: fileItem.dateModified
            )
            if !Task.isCancelled {
                thumbnail = image
            }
        }
    }

    // MARK: - Non-Media Cell

    @ViewBuilder
    private var nonMediaCell: some View {
        VStack(spacing: 4) {
            Spacer()
            FileIconView(item: fileItem, size: min(48, layoutItem.height * 0.4))

            Text(fileItem.name)
                .font(.caption2)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
                .frame(maxWidth: layoutItem.width - 8)

            if fileItem.isDirectory, let count = folderCount {
                Text("\(count) \(count == 1 ? "item" : "items")")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            } else {
                Text(FormatHelpers.formatDate(fileItem.dateModified))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .frame(width: layoutItem.width, height: layoutItem.height)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay {
            RoundedRectangle(cornerRadius: 2)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
        }
        .task(id: fileItem.url) {
            guard fileItem.isDirectory else { return }
            let fm = FileManager.default
            let count = (try? fm.contentsOfDirectory(atPath: fileItem.url.path))?.count
            if !Task.isCancelled {
                folderCount = count
            }
        }
    }
}
