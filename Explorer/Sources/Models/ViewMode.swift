import Foundation

enum ViewMode: String, CaseIterable, Identifiable {
    case list
    case icon
    case mosaic

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .list: return "list.bullet"
        case .icon: return "square.grid.2x2"
        case .mosaic: return "rectangle.split.3x3"
        }
    }

    var label: String {
        switch self {
        case .list: return "List"
        case .icon: return "Icons"
        case .mosaic: return "Mosaic"
        }
    }
}
