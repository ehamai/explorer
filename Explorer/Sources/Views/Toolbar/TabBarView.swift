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
        .frame(height: 28)
        .background(.bar)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct TabItemView: View {
    let tab: BrowserTab
    let isActive: Bool

    @Environment(TabManager.self) private var tabManager
    @State private var isHovering = false
    @State private var isBlinking = false
    @State private var switchWorkItem: DispatchWorkItem?

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
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, maxHeight: 24)
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
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.accentColor.opacity(isBlinking ? 0.4 : 0))
                .animation(
                    isBlinking
                        ? .easeInOut(duration: 0.1).repeatForever(autoreverses: true)
                        : .default,
                    value: isBlinking
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .dropDestination(for: URL.self) { _, _ in
            false
        } isTargeted: { targeted in
            if targeted && !isActive {
                isBlinking = true
                let workItem = DispatchWorkItem {
                    isBlinking = false
                    tabManager.activeTabID = tab.id
                }
                switchWorkItem = workItem
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
            } else {
                isBlinking = false
                switchWorkItem?.cancel()
                switchWorkItem = nil
            }
        }
        .onTapGesture {
            tabManager.activeTabID = tab.id
        }
        .onHover { hovering in
            isHovering = hovering
        }
    }
}
