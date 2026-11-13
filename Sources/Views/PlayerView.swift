import SwiftUI
import AVKit

struct PlaybackRequest: Identifiable {
    let id = UUID()
    let url: URL
    let title: String?
}

/// Native tvOS player. Handles HLS / MP4 well.
/// TODO (milestone 2): swap in MPVKit or KSPlayer for MKV, DTS/TrueHD and PGS subtitles.
struct PlayerView: UIViewControllerRepresentable {
    let request: PlaybackRequest

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        let item = AVPlayerItem(url: request.url)
        if let title = request.title {
            let meta = AVMutableMetadataItem()
            meta.identifier = .commonIdentifierTitle
            meta.value = title as NSString
            meta.extendedLanguageTag = "und"
            item.externalMetadata = [meta]
        }
        let player = AVPlayer(playerItem: item)
        controller.player = player
        player.play()
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {}

    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: ()) {
        controller.player?.pause()
        controller.player = nil
    }
}
