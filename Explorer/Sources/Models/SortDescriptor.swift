import Foundation

enum SortField: String, CaseIterable, Identifiable, Codable {
    case name
    case dateModified
    case size
    case kind

    var id: String { rawValue }

    var label: String {
        switch self {
        case .name: return "Name"
        case .dateModified: return "Date Modified"
        case .size: return "Size"
        case .kind: return "Kind"
        }
    }
}

enum SortOrder: String, CaseIterable, Identifiable, Codable {
    case ascending
    case descending

    var id: String { rawValue }

    var label: String {
        switch self {
        case .ascending: return "Ascending"
        case .descending: return "Descending"
        }
    }

    var toggled: SortOrder {
        self == .ascending ? .descending : .ascending
    }
}

struct FileSortDescriptor: Equatable, Codable {
    var field: SortField
    var order: SortOrder

    init(field: SortField = .name, order: SortOrder = .ascending) {
        self.field = field
        self.order = order
    }

    func compare(_ lhs: FileItem, _ rhs: FileItem) -> Bool {
        // Folders always sort before files
        if lhs.isDirectory != rhs.isDirectory {
            return lhs.isDirectory
        }

        let result: ComparisonResult
        switch field {
        case .name:
            result = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
        case .dateModified:
            result = lhs.dateModified.compare(rhs.dateModified)
        case .size:
            if lhs.size == rhs.size {
                result = .orderedSame
            } else {
                result = lhs.size < rhs.size ? .orderedAscending : .orderedDescending
            }
        case .kind:
            result = lhs.kind.localizedCaseInsensitiveCompare(rhs.kind)
        }

        switch order {
        case .ascending:
            return result == .orderedAscending
        case .descending:
            return result == .orderedDescending
        }
    }
}
