import Foundation

struct MosaicLayoutItem: Identifiable, Equatable {
    let id: URL
    let width: CGFloat
    let height: CGFloat
    let aspectRatio: CGFloat
    let hasThumbnail: Bool
}

struct MosaicRow: Identifiable, Equatable {
    let id: Int
    let items: [MosaicLayoutItem]
    let height: CGFloat
}

func computeJustifiedRows(
    items: [(id: URL, aspectRatio: CGFloat, hasThumbnail: Bool)],
    containerWidth: CGFloat,
    targetRowHeight: CGFloat = 200,
    spacing: CGFloat = 2
) -> [MosaicRow] {
    guard !items.isEmpty, containerWidth > 0 else { return [] }

    var rows: [MosaicRow] = []
    var currentItems: [(id: URL, aspectRatio: CGFloat, hasThumbnail: Bool)] = []
    var sumAspectRatios: CGFloat = 0

    for item in items {
        let ar = item.hasThumbnail ? max(item.aspectRatio, 0.1) : 1.0
        currentItems.append((item.id, ar, item.hasThumbnail))
        sumAspectRatios += ar

        let totalSpacing = spacing * CGFloat(currentItems.count - 1)
        let rowHeight = (containerWidth - totalSpacing) / sumAspectRatios

        if rowHeight <= targetRowHeight {
            // Row is full — justify to container width
            let layoutItems = currentItems.map { entry in
                MosaicLayoutItem(
                    id: entry.id,
                    width: entry.aspectRatio * rowHeight,
                    height: rowHeight,
                    aspectRatio: entry.aspectRatio,
                    hasThumbnail: entry.hasThumbnail
                )
            }
            rows.append(MosaicRow(id: rows.count, items: layoutItems, height: rowHeight))
            currentItems = []
            sumAspectRatios = 0
        }
    }

    // Last incomplete row: render at targetRowHeight, left-aligned
    if !currentItems.isEmpty {
        let layoutItems = currentItems.map { entry in
            MosaicLayoutItem(
                id: entry.id,
                width: entry.aspectRatio * targetRowHeight,
                height: targetRowHeight,
                aspectRatio: entry.aspectRatio,
                hasThumbnail: entry.hasThumbnail
            )
        }
        rows.append(MosaicRow(id: rows.count, items: layoutItems, height: targetRowHeight))
    }

    return rows
}
