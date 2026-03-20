import SwiftUI
import AppKit

struct TabBarView: View {
    @Environment(TabManager.self) private var tabManager

    var body: some View {
        HStack(spacing: 1) {
            ForEach(tabManager.tabs) { tab in
                TabItemView(
                    tab: tab,
                    isActive: tab.id == tabManager.activeTabID
                )
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(.bar)
    }
}

private struct TabItemView: View {
    let tab: BrowserTab
    let isActive: Bool

    @Environment(TabManager.self) private var tabManager
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 0) {
            // Close button area (left, Finder-style)
            ZStack {
                if isHovering && tabManager.tabs.count > 1 {
                    Button {
                        tabManager.closeTab(id: tab.id)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 16, height: 16)
                            .background(
                                Circle()
                                    .fill(Color.primary.opacity(0.1))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(width: 24)

            Spacer(minLength: 0)

            HStack(spacing: 5) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Text(tab.displayName)
                    .font(.system(size: 12))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            // Balance close button width
            Color.clear.frame(width: 24)
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(isActive
                      ? Color(nsColor: .controlBackgroundColor)
                      : Color.primary.opacity(isHovering ? 0.04 : 0))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    isActive ? Color.primary.opacity(0.08) : Color.clear,
                    lineWidth: 0.5
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .onTapGesture {
            tabManager.activeTabID = tab.id
        }
        .onHover { hovering in
            isHovering = hovering
        }
    }
}
