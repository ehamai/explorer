import SwiftUI
import AVKit

struct VideoViewerView: View {
    let player: AVPlayer
    @Binding var loopEnabled: Bool

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            AVPlayerViewRepresentable(player: player)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
                .onAppear { player.play() }
                .onDisappear { player.pause() }

            // Loop toggle near the player controls
            Button {
                loopEnabled.toggle()
            } label: {
                Image(systemName: loopEnabled ? "repeat.circle.fill" : "repeat.circle")
                    .font(.system(size: 16))
                    .foregroundStyle(loopEnabled ? Color.accentColor : .white.opacity(0.7))
                    .padding(8)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .padding(12)
            .help(loopEnabled ? "Looping On (⌘L)" : "Looping Off (⌘L)")
        }
    }
}

/// NSViewRepresentable wrapper for AVPlayerView.
/// Works around a SwiftUI VideoPlayer crash on macOS 26 where
/// AVPlayerView metadata demangling fails.
private struct AVPlayerViewRepresentable: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .floating
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player {
            nsView.player = player
        }
    }
}
