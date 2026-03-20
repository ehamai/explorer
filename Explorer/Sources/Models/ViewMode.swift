import Foundation

enum ViewMode: String, CaseIterable, Identifiable {
    case list
    case icon
    case column

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .list: return "list.bullet"
        case .icon: return "square.grid.2x2"
        case .column: return "rectangle.split.3x1"
        }
    }

    var label: String {
        switch self {
        case .list: return "List"
        case .icon: return "Icons"
        case .column: return "Columns"
        }
    }
}
