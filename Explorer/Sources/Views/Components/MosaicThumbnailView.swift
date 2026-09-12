import SwiftUI
import AppKit

struct MosaicThumbnailView: View {
    let layoutItem: MosaicLayoutItem
    let fileItem: FileItem
    let isSelected: Bool
    let isCut: Bool
    var isDropTarget: Bool = false

    @Environment(ThumbnailCache.self) private var thumbnailCache
    @Environment(ThumbnailLoader.self) private var thumbnailLoader

    @State private var thumbnail: NSImage?

    @State private var folderCount: Int?

    var body: some View {
        Group {
            if layoutItem.hasThumbnail {
                mediaCell
            } else {
                nonMediaCell
            }
        }
        .opacity(isCut ? 0.4 : 1.0)
        .overlay {
            if isDropTarget {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentColor.opacity(0.3))
                    .overlay {
                        RoundedRectangle(cornerRadius: 2)
                            .strokeBorder(Color.accentColor, lineWidth: 2)
                    }
            } else if isSelected {
                RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
            }
        }
        .contentShape(Rectangle())
    }

    // MARK: - Media Cell

    @ViewBuilder
    private var mediaCell: some View {
        let isPDF = MediaFileType.detect(from: fileItem.url) == .pdf
        let mediaType = MediaFileType.detect(from: fileItem.url)
        ZStack {
            isPDF ? Color(nsColor: .controlBackgroundColor) : Color.black

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

            // Bottom overlay for badges and date (non-media only)
            VStack {
                Spacer()
                HStack(alignment: .bottom) {
                    // Show date only for PDFs (not images/videos)
                    if !mediaType.isMedia {
                        Text(FormatHelpers.formatDate(fileItem.dateModified))
                            .font(.caption2)
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.6), radius: 2, y: 1)
                            .padding(.leading, 6)
                            .padding(.bottom, 6)
                    }

                    Spacer()

                    if mediaType == .video {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: min(28, layoutItem.height * 0.15)))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
                            .padding(.trailing, 6)
                            .padding(.bottom, 6)
                    }

                    if mediaType == .pdf {
                        Image(systemName: "doc.text.fill")
                            .font(.system(size: min(20, layoutItem.height * 0.12)))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
                            .padding(.trailing, 6)
                            .padding(.bottom, 6)
                    }
                }
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
            }

            Text(FormatHelpers.formatDate(fileItem.dateModified))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
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
