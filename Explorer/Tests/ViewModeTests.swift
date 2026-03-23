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

    @Test func allCasesHasTwoElements() {
        #expect(ViewMode.allCases.count == 2)
    }
}
