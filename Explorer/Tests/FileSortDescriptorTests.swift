import Testing
import Foundation
@testable import Explorer

@Suite("FileSortDescriptor")
struct FileSortDescriptorTests {

    // MARK: - Defaults

    @Test func defaultFieldIsName() {
        let descriptor = FileSortDescriptor()
        #expect(descriptor.field == .name)
    }

    @Test func defaultOrderIsAscending() {
        let descriptor = FileSortDescriptor()
        #expect(descriptor.order == .ascending)
    }

    // MARK: - Name sorting

    @Test func compareByNameAscending() {
        let descriptor = FileSortDescriptor(field: .name, order: .ascending)
        let apple = TestHelpers.makeFileItem(name: "apple")
        let zebra = TestHelpers.makeFileItem(name: "zebra")
        #expect(descriptor.compare(apple, zebra) == true)
        #expect(descriptor.compare(zebra, apple) == false)
    }

    @Test func compareByNameDescending() {
        let descriptor = FileSortDescriptor(field: .name, order: .descending)
        let apple = TestHelpers.makeFileItem(name: "apple")
        let zebra = TestHelpers.makeFileItem(name: "zebra")
        #expect(descriptor.compare(zebra, apple) == true)
        #expect(descriptor.compare(apple, zebra) == false)
    }

    @Test func compareByNameCaseInsensitive() {
        let descriptor = FileSortDescriptor(field: .name, order: .ascending)
        let upper = TestHelpers.makeFileItem(name: "Apple")
        let lower = TestHelpers.makeFileItem(name: "banana")
        #expect(descriptor.compare(upper, lower) == true)
        #expect(descriptor.compare(lower, upper) == false)
    }

    // MARK: - Size sorting

    @Test func compareBySizeAscending() {
        let descriptor = FileSortDescriptor(field: .size, order: .ascending)
        let small = TestHelpers.makeFileItem(name: "small", size: 100)
        let large = TestHelpers.makeFileItem(name: "large", size: 9999)
        #expect(descriptor.compare(small, large) == true)
        #expect(descriptor.compare(large, small) == false)
    }

    @Test func compareBySizeDescending() {
        let descriptor = FileSortDescriptor(field: .size, order: .descending)
        let small = TestHelpers.makeFileItem(name: "small", size: 100)
        let large = TestHelpers.makeFileItem(name: "large", size: 9999)
        #expect(descriptor.compare(large, small) == true)
        #expect(descriptor.compare(small, large) == false)
    }

    // MARK: - Date sorting

    @Test func compareByDateAscending() {
        let descriptor = FileSortDescriptor(field: .dateModified, order: .ascending)
        let earlier = TestHelpers.makeFileItem(name: "old", dateModified: Date(timeIntervalSince1970: 1000))
        let later = TestHelpers.makeFileItem(name: "new", dateModified: Date(timeIntervalSince1970: 9999))
        #expect(descriptor.compare(earlier, later) == true)
        #expect(descriptor.compare(later, earlier) == false)
    }

    @Test func compareByDateDescending() {
        let descriptor = FileSortDescriptor(field: .dateModified, order: .descending)
        let earlier = TestHelpers.makeFileItem(name: "old", dateModified: Date(timeIntervalSince1970: 1000))
        let later = TestHelpers.makeFileItem(name: "new", dateModified: Date(timeIntervalSince1970: 9999))
        #expect(descriptor.compare(later, earlier) == true)
        #expect(descriptor.compare(earlier, later) == false)
    }

    // MARK: - Kind sorting

    @Test func compareByKindAscending() {
        let descriptor = FileSortDescriptor(field: .kind, order: .ascending)
        let doc = TestHelpers.makeFileItem(name: "a", kind: "Document")
        let img = TestHelpers.makeFileItem(name: "b", kind: "Image")
        #expect(descriptor.compare(doc, img) == true)
        #expect(descriptor.compare(img, doc) == false)
    }

    // MARK: - Directories before files

    @Test func directoriesAlwaysBeforeFiles() {
        for field in SortField.allCases {
            for order in SortOrder.allCases {
                let descriptor = FileSortDescriptor(field: field, order: order)
                let dir = TestHelpers.makeFileItem(name: "zebra", isDirectory: true)
                let file = TestHelpers.makeFileItem(name: "apple")
                #expect(descriptor.compare(dir, file) == true,
                        "Directory should sort before file with field=\(field) order=\(order)")
                #expect(descriptor.compare(file, dir) == false,
                        "File should not sort before directory with field=\(field) order=\(order)")
            }
        }
    }

    // MARK: - Codable

    @Test func codableRoundTrip() throws {
        let original = FileSortDescriptor(field: .size, order: .descending)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(FileSortDescriptor.self, from: data)
        #expect(decoded.field == original.field)
        #expect(decoded.order == original.order)
    }

    // MARK: - Label & toggle helpers

    @Test func sortFieldLabelsCorrect() {
        #expect(SortField.name.label == "Name")
        #expect(SortField.dateModified.label == "Date Modified")
        #expect(SortField.size.label == "Size")
        #expect(SortField.kind.label == "Kind")
    }

    @Test func sortOrderToggledValues() {
        #expect(SortOrder.ascending.toggled == .descending)
        #expect(SortOrder.descending.toggled == .ascending)
    }

    // MARK: - Equality

    @Test func equalityCheck() {
        let a = FileSortDescriptor(field: .name, order: .ascending)
        let b = FileSortDescriptor(field: .name, order: .ascending)
        let c = FileSortDescriptor(field: .size, order: .ascending)
        #expect(a == b)
        #expect(a != c)
    }
}
