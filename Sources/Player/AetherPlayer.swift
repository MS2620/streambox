import SwiftUI
import AetherEngine

/// One AetherEngine for the app's lifetime, as the engine recommends.
/// Shared by live TV, movies and series.
@MainActor
final class PlayerEngineHolder: ObservableObject {
    let engine: AetherEngine?
    let initError: String?
    /// True while the full-screen player is open. The Live TV guide's small
    /// preview steps aside then, so the engine's picture goes to the full screen.
    @Published var isPresentingPlayer = false

    init() {
        do {
            let engine = try AetherEngine()
            // Tellio plays no audio of its own outside the player.
            engine.deactivatesAudioSessionOnStop = true
            self.engine = engine
            self.initError = nil
        } catch {
            self.engine = nil
            self.initError = error.localizedDescription
        }
    }
}

/// Draws the engine's subtitle cues (text and bitmap, e.g. PGS) over the video.
struct SubtitleOverlay: View {
    let cues: [SubtitleCue]
    let time: Double
    var fontSize: CGFloat = 44

    var body: some View {
        let active = cues.filter { $0.startTime <= time && time < $0.endTime }
        let text = active.compactMap(\.text).joined(separator: "\n")

        GeometryReader { geo in
            ZStack {
                ForEach(active) { cue in
                    if case .image(let image) = cue.body {
                        // Position is [0, 1] against the video frame.
                        Image(decorative: image.cgImage, scale: 1)
                            .resizable()
                            .frame(width: image.position.width * geo.size.width,
                                   height: image.position.height * geo.size.height)
                            .position(x: image.position.midX * geo.size.width,
                                      y: image.position.midY * geo.size.height)
                    }
                }

                if !text.isEmpty {
                    VStack {
                        Spacer()
                        Text(text)
                            .font(.system(size: fontSize, weight: .semibold))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white)
                            .shadow(color: .black, radius: 3)
                            .shadow(color: .black, radius: 1)
                            .padding(.horizontal, 120)
                            .padding(.bottom, 70)
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}
