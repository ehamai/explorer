import SwiftUI
import AppKit

struct TabBarView: View {
    @Environment(TabManager.self) private var tabManager

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 1) {
                    ForEach(tabManager.tabs) { tab in
                        TabItemView(
                            tab: tab,
                            isActive: tab.id == tabManager.activeTabID,
                            canClose: tabManager.tabs.count > 1
                        )
                    }
                }
                .padding(.horizontal, 4)
            }
            Spacer()
        }
        .frame(height: 28)
        .background(.bar)
    }
}

private struct TabItemView: View {
    let tab: BrowserTab
    let isActive: Bool
    let canClose: Bool

    @Environment(TabManager.self) private var tabManager
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "folder.fill")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(tab.displayName)
                .font(.callout)
                .lineLimit(1)
                .frame(maxWidth: 140)

            if canClose {
                Button {
                    tabManager.closeTab(id: tab.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 14, height: 14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(isHovering || isActive ? 1 : 0)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isActive ? Color(nsColor: .controlBackgroundColor) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(isActive ? Color.primary.opacity(0.1) : Color.clear, lineWidth: 0.5)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            tabManager.activeTabID = tab.id
        }
        .onHover { hovering in
            isHovering = hovering
        }
    }
}
