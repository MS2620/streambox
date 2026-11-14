import SwiftUI

struct PlaybackRequest: Identifiable {
    let id = UUID()
    let url: URL
    let title: String?
}

/// Full-screen player built on mpv (via MPVKit).
///
/// Siri Remote:
///   click / play-pause  → pause / resume
///   left / right        → seek -10s / +30s
///   up                  → cycle subtitles
///   down                → cycle audio tracks
///   Menu / Back         → close
struct PlayerView: View {
    let request: PlaybackRequest

    @StateObject private var state = MPVPlayerState()
    @StateObject private var handle = MPVHandle()
    @State private var showOverlay = true
    @State private var hideTask: Task<Void, Never>?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            MPVVideoView(url: request.url, state: state, handle: handle)
                .ignoresSafeArea()

            if state.buffering && state.error == nil {
                ProgressView().scaleEffect(1.5)
            }

            if let error = state.error {
                VStack(spacing: 16) {
                    Text("Playback failed").font(.title2).bold()
                    Text(error)
                    Text("Press Back to return").foregroundStyle(.secondary)
                }
                .padding(40)
                .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 24))
            }

            if showOverlay && state.error == nil {
                overlay
            }
        }
        .focusable()
        .focusEffectDisabled()
        .onPlayPauseCommand { togglePause() }
        .onTapGesture { togglePause() }
        .onMoveCommand { direction in
            switch direction {
            case .left: handle.controller?.seek(by: -10)
            case .right: handle.controller?.seek(by: 30)
            case .up: handle.controller?.cycle("sub")
            case .down: handle.controller?.cycle("audio")
            @unknown default: break
            }
            poke()
        }
        .onExitCommand { dismiss() }
        .onChange(of: state.ended) { _, ended in
            if ended { dismiss() }
        }
        .onChange(of: state.paused) { _, _ in poke() }
        .onAppear { poke() }
        .onDisappear { hideTask?.cancel() }
    }

    private var overlay: some View {
        VStack {
            Spacer()
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    if state.paused {
                        Image(systemName: "pause.fill")
                    }
                    Text(request.title ?? "").font(.title3).bold().lineLimit(1)
                }
                if state.duration > 0 {
                    ProgressView(value: min(state.position, state.duration), total: state.duration)
                    HStack {
                        Text(Self.format(state.position))
                        Spacer()
                        Text("-" + Self.format(max(state.duration - state.position, 0)))
                    }
                    .font(.caption)
                    .monospacedDigit()
                } else {
                    Text("LIVE").font(.caption).bold().foregroundStyle(.red)
                }
                Text("◀ −10s   ▶ +30s   ▲ subtitles   ▼ audio")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 80)
            .padding(.vertical, 40)
            .background(
                LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
            )
        }
        .ignoresSafeArea()
        .transition(.opacity)
    }

    private func togglePause() {
        handle.controller?.togglePause()
        poke()
    }

    /// Shows the overlay, then hides it after a few seconds unless paused.
    private func poke() {
        withAnimation { showOverlay = true }
        hideTask?.cancel()
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, !state.paused else { return }
            withAnimation { showOverlay = false }
        }
    }

    static func format(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let total = Int(seconds)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
