import SwiftUI
import AppKit

struct PathBarView: View {
    @Environment(NavigationViewModel.self) private var navigationVM

    var body: some View {
        let components = navigationVM.pathComponents
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(Array(components.indices), id: \.self) { index in
                    let comp = components[index]
                    let isLast = index == components.count - 1

                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    Button {
                        navigationVM.navigate(to: comp.url)
                    } label: {
                        HStack(spacing: 4) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: comp.url.path))
                                .resizable()
                                .frame(width: 14, height: 14)

                            Text(displayName(comp.name, url: comp.url))
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

    private func displayName(_ name: String, url: URL) -> String {
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
