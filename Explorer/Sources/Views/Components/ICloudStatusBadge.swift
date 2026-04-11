import SwiftUI

/// Displays an iCloud sync status icon for a file item.
struct ICloudStatusBadge: View {
    let status: ICloudStatus

    var body: some View {
        if let symbolName = status.symbolName {
            Image(systemName: symbolName)
                .font(.system(size: 10))
                .foregroundStyle(color)
                .help(status.label)
        }
    }

    private var color: Color {
        switch status {
        case .current:      return .green
        case .cloudOnly:    return .secondary
        case .downloading:  return .blue
        case .uploading:    return .orange
        case .error:        return .red
        case .local:        return .clear
        }
    }
}
