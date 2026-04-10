import Foundation
import Testing

@testable import Explorer

@Suite("MosaicLayout")
struct MosaicLayoutTests {

    // MARK: - Helpers

    private func makeItem(
        _ name: String, aspectRatio: CGFloat, isMedia: Bool = true
    ) -> (id: URL, aspectRatio: CGFloat, isMedia: Bool) {
        (id: URL(fileURLWithPath: "/test/\(name)"), aspectRatio: aspectRatio, isMedia: isMedia)
    }

    // MARK: - Empty / invalid input

    @Test func emptyItemsReturnsEmptyRows() {
        let rows = computeJustifiedRows(items: [], containerWidth: 800)
        #expect(rows.isEmpty)
    }

    @Test func zeroContainerWidthReturnsEmpty() {
        let items = [makeItem("image1.jpg", aspectRatio: 1.5)]
        let rows = computeJustifiedRows(items: items, containerWidth: 0)
        #expect(rows.isEmpty)
    }

    // MARK: - Single item

    @Test func singleLandscapeImage() {
        let items = [makeItem("landscape.jpg", aspectRatio: 16.0 / 9.0)]
        let rows = computeJustifiedRows(
            items: items, containerWidth: 800, targetRowHeight: 200)
        #expect(rows.count == 1)
        #expect(rows[0].items.count == 1)
        let item = rows[0].items[0]
        #expect(abs(item.height - 200) < 0.1)
    }

    @Test func singlePortraitImage() {
        let items = [makeItem("portrait.jpg", aspectRatio: 9.0 / 16.0)]
        let rows = computeJustifiedRows(
            items: items, containerWidth: 800, targetRowHeight: 200)
        #expect(rows.count == 1)
        let item = rows[0].items[0]
        #expect(abs(item.height - 200) < 0.1)
        #expect(item.width < 800)
    }

    // MARK: - Row filling

    @Test func multipleItemsFillOneRow() {
        // Four square items at 200px target in an 800px container:
        // rowHeight = (800 - 3*2) / 4 = 198.5, which is <= 200 → justified row
        let items = (1...4).map { makeItem("img\($0).jpg", aspectRatio: 1.0) }
        let rows = computeJustifiedRows(
            items: items, containerWidth: 800, targetRowHeight: 200, spacing: 2)
        #expect(rows.count == 1)
        #expect(rows[0].items.count == 4)
    }

    @Test func justifiedRowFillsContainerWidth() {
        let items = (1...4).map { makeItem("img\($0).jpg", aspectRatio: 1.0) }
        let rows = computeJustifiedRows(
            items: items, containerWidth: 800, targetRowHeight: 200, spacing: 2)
        #expect(rows.count >= 1)
        let row = rows[0]
        let totalSpacing = 2.0 * CGFloat(row.items.count - 1)
        let totalWidth = row.items.reduce(CGFloat(0)) { $0 + $1.width } + totalSpacing
        #expect(abs(totalWidth - 800) < 0.5)
    }

    @Test func justifiedRowItemsHaveSameHeight() {
        let items = [
            makeItem("wide.jpg", aspectRatio: 2.0),
            makeItem("square.jpg", aspectRatio: 1.0),
            makeItem("tall.jpg", aspectRatio: 0.7),
        ]
        let rows = computeJustifiedRows(
            items: items, containerWidth: 800, targetRowHeight: 200, spacing: 2)
        guard let row = rows.first, row.items.count > 1 else {
            #expect(Bool(false), "Expected a justified row with multiple items")
            return
        }
        let height = row.items[0].height
        for item in row.items {
            #expect(abs(item.height - height) < 0.01)
        }
    }

    // MARK: - Multiple rows

    @Test func itemsSpanMultipleRows() {
        // 10 square items in 400px container at 200 target → multiple rows
        let items = (1...10).map { makeItem("img\($0).jpg", aspectRatio: 1.0) }
        let rows = computeJustifiedRows(
            items: items, containerWidth: 400, targetRowHeight: 200, spacing: 2)
        #expect(rows.count > 1)
    }

    // MARK: - Last row behavior

    @Test func lastRowNotJustified() {
        // Many items so at least one justified row, plus a leftover last row
        let items = (1...5).map { makeItem("img\($0).jpg", aspectRatio: 1.0) }
        let rows = computeJustifiedRows(
            items: items, containerWidth: 400, targetRowHeight: 200, spacing: 2)
        #expect(rows.count >= 2)
        let lastRow = rows.last!
        #expect(abs(lastRow.height - 200) < 0.1)
    }

    @Test func lastRowLeftAligned() {
        let items = (1...3).map { makeItem("img\($0).jpg", aspectRatio: 1.0) }
        let rows = computeJustifiedRows(
            items: items, containerWidth: 1000, targetRowHeight: 200, spacing: 2)
        // With 1000px and 3 square items at 200 target: rowHeight = (1000-4)/3 ≈ 332, which is > 200
        // So all items go to the last (incomplete) row at targetRowHeight
        guard let lastRow = rows.last else {
            #expect(Bool(false), "Expected at least one row")
            return
        }
        if abs(lastRow.height - 200) < 0.1 {
            let totalWidth = lastRow.items.reduce(CGFloat(0)) { $0 + $1.width }
            let totalSpacing = 2.0 * CGFloat(max(lastRow.items.count - 1, 0))
            #expect(totalWidth + totalSpacing < 1000)
        }
    }

    // MARK: - Panorama

    @Test func veryWidePanoramaGetsOwnRow() {
        let items = [
            makeItem("pano.jpg", aspectRatio: 5.0),
            makeItem("square.jpg", aspectRatio: 1.0),
        ]
        let rows = computeJustifiedRows(
            items: items, containerWidth: 800, targetRowHeight: 200, spacing: 2)
        // 5.0 AR at 200 target = 1000px width which exceeds 800 container,
        // so rowHeight = 800/5 = 160 <= 200 → panorama fills row alone
        #expect(rows.count == 2)
        #expect(rows[0].items.count == 1)
        #expect(rows[0].items[0].aspectRatio == 5.0)
    }

    // MARK: - Non-media

    @Test func nonMediaItemsUseSquareAspectRatio() {
        let items = [makeItem("doc.pdf", aspectRatio: 3.0, isMedia: false)]
        let rows = computeJustifiedRows(
            items: items, containerWidth: 800, targetRowHeight: 200)
        #expect(rows.count == 1)
        let item = rows[0].items[0]
        // Non-media items are treated as 1.0 AR → width == height
        #expect(abs(item.aspectRatio - 1.0) < 0.01)
        #expect(abs(item.width - item.height) < 0.1)
    }

    // MARK: - Spacing

    @Test func spacingBetweenItems() {
        let items = (1...3).map { makeItem("img\($0).jpg", aspectRatio: 1.0) }
        let rowsNoSpacing = computeJustifiedRows(
            items: items, containerWidth: 600, targetRowHeight: 200, spacing: 0)
        let rowsWithSpacing = computeJustifiedRows(
            items: items, containerWidth: 600, targetRowHeight: 200, spacing: 10)

        guard let rowA = rowsNoSpacing.first, let rowB = rowsWithSpacing.first else {
            #expect(Bool(false), "Expected rows")
            return
        }
        // With spacing, each item should be narrower to accommodate gaps
        if rowA.items.count == rowB.items.count {
            #expect(rowB.items[0].width < rowA.items[0].width)
        }
    }

    // MARK: - Row IDs

    @Test func rowIdsAreSequential() {
        let items = (1...10).map { makeItem("img\($0).jpg", aspectRatio: 1.0) }
        let rows = computeJustifiedRows(
            items: items, containerWidth: 400, targetRowHeight: 200)
        for (index, row) in rows.enumerated() {
            #expect(row.id == index)
        }
    }

    // MARK: - Container width impact

    @Test func containerWidthChangeProducesDifferentLayout() {
        let items = (1...8).map { makeItem("img\($0).jpg", aspectRatio: 1.5) }
        let narrowRows = computeJustifiedRows(
            items: items, containerWidth: 400, targetRowHeight: 200)
        let wideRows = computeJustifiedRows(
            items: items, containerWidth: 1200, targetRowHeight: 200)
        #expect(narrowRows.count != wideRows.count)
    }

    // MARK: - Media flag preservation

    @Test func preservesMediaFlag() {
        let items = [
            makeItem("photo.jpg", aspectRatio: 1.5, isMedia: true),
            makeItem("doc.txt", aspectRatio: 2.0, isMedia: false),
        ]
        let rows = computeJustifiedRows(items: items, containerWidth: 800, targetRowHeight: 200)
        let allItems = rows.flatMap { $0.items }
        let photo = allItems.first { $0.id.lastPathComponent == "photo.jpg" }
        let doc = allItems.first { $0.id.lastPathComponent == "doc.txt" }
        #expect(photo?.isMedia == true)
        #expect(doc?.isMedia == false)
    }
}
