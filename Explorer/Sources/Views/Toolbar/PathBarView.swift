import SwiftUI
import AppKit

struct PathBarView: View {
    @Environment(NavigationViewModel.self) private var navigationVM

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(Array(navigationVM.pathComponents.enumerated()), id: \.offset) { index, component in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    let isLast = index == navigationVM.pathComponents.count - 1

                    Button {
                        navigationVM.navigate(to: component.url)
                    } label: {
                        HStack(spacing: 4) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: component.url.path))
                                .resizable()
                                .frame(width: 14, height: 14)

                            Text(displayName(for: component.url))
                                .font(.callout)
                                .fontWeight(isLast ? .semibold : .regular)
                                .foregroundStyle(isLast ? .primary : .secondary)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.primary.opacity(0.001))
                    )
                    .onHover { hovering in
                        if hovering {
                            NSCursor.pointingHand.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func displayName(for url: URL) -> String {
        let name = url.lastPathComponent
        if name == "/" || name.isEmpty {
            return volumeName(for: url)
        }
        return name
    }

    private func volumeName(for url: URL) -> String {
        if let values = try? url.resourceValues(forKeys: [.volumeNameKey]),
           let volumeName = values.volumeName {
            return volumeName
        }
        return "Macintosh HD"
    }
}
