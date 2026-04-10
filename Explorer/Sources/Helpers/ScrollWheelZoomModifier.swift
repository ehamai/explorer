import SwiftUI
import AppKit

/// Modifier that provides continuous pinch-to-zoom on trackpad.
struct PinchToZoomModifier: ViewModifier {
    @Binding var zoom: CGFloat
    let range: ClosedRange<CGFloat>

    @State private var baseZoom: CGFloat = 0

    func body(content: Content) -> some View {
        content.gesture(
            MagnifyGesture()
                .onChanged { value in
                    if baseZoom == 0 { baseZoom = zoom }
                    let newZoom = baseZoom * value.magnification
                    withAnimation(.interactiveSpring) {
                        zoom = min(max(newZoom, range.lowerBound), range.upperBound)
                    }
                }
                .onEnded { _ in
                    baseZoom = 0
                }
        )
    }
}

extension View {
    func pinchToZoom(_ zoom: Binding<CGFloat>, range: ClosedRange<CGFloat>) -> some View {
        modifier(PinchToZoomModifier(zoom: zoom, range: range))
    }
}
