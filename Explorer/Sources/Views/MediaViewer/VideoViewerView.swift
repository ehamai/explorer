import SwiftUI
import AVKit

struct VideoViewerView: View {
    let player: AVPlayer

    var body: some View {
        VideoPlayer(player: player)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            .onAppear { player.play() }
            .onDisappear { player.pause() }
    }
}
