import Foundation

/// Represents the iCloud sync status of a file.
enum ICloudStatus: Equatable, Hashable {
    /// File is not in an iCloud-managed directory.
    case local
    /// File is fully downloaded and available locally.
    case current
    /// File is a cloud-only placeholder (not downloaded).
    case cloudOnly
    /// File is currently downloading.
    case downloading(progress: Double)
    /// File is currently uploading.
    case uploading(progress: Double)
    /// A sync error occurred.
    case error(String)

    var symbolName: String? {
        switch self {
        case .local:        return nil
        case .current:      return "checkmark.icloud"
        case .cloudOnly:    return "icloud.and.arrow.down"
        case .downloading:  return "arrow.down.circle"
        case .uploading:    return "arrow.up.circle"
        case .error:        return "exclamationmark.icloud"
        }
    }

    var label: String {
        switch self {
        case .local:                return ""
        case .current:              return "Downloaded"
        case .cloudOnly:            return "In iCloud"
        case .downloading(let p):   return "Downloading \(Int(p * 100))%"
        case .uploading(let p):     return "Uploading \(Int(p * 100))%"
        case .error(let msg):       return "Error: \(msg)"
        }
    }

    /// Whether the file content is available locally.
    var isAvailableLocally: Bool {
        switch self {
        case .local, .current, .uploading: return true
        default: return false
        }
    }

    /// Whether `FileManager.startDownloadingUbiquitousItem` is applicable.
    var canDownload: Bool { self == .cloudOnly }

    /// Whether `FileManager.evictUbiquitousItem` is applicable.
    var canEvict: Bool {
        if case .current = self { return true }
        return false
    }
}
