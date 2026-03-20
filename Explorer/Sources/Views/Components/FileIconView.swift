import SwiftUI
import AppKit

/// Displays the system file icon for a given FileItem.
/// Uses the item's cached icon if available, otherwise
/// retrieves it from NSWorkspace based on the file URL.
struct FileIconView: View {
    let item: FileItem
    let size: CGFloat

    var body: some View {
        Image(nsImage: resolvedIcon)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
    }

    private var resolvedIcon: NSImage {
        return item.icon
    }
}
