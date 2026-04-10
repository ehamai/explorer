import Testing
import Foundation
@testable import Explorer

@Suite("ViewMode")
struct ViewModeTests {

    @Test func listSystemImage() {
        #expect(ViewMode.list.systemImage == "list.bullet")
    }

    @Test func iconSystemImage() {
        #expect(ViewMode.icon.systemImage == "square.grid.2x2")
    }

    @Test func listLabel() {
        #expect(ViewMode.list.label == "List")
    }

    @Test func iconLabel() {
        #expect(ViewMode.icon.label == "Icons")
    }

    @Test func mosaicSystemImage() {
        #expect(ViewMode.mosaic.systemImage == "rectangle.split.3x3")
    }

    @Test func mosaicLabel() {
        #expect(ViewMode.mosaic.label == "Mosaic")
    }

    @Test func allCasesHasThreeElements() {
        #expect(ViewMode.allCases.count == 3)
    }
}
