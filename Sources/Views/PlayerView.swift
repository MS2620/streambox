import SwiftUI
import Combine
import AetherEngine

struct PlaybackRequest: Identifiable {
    let id = UUID()
    let url: URL
    let title: String?
    var isLive: Bool = false
    var httpHeaders: [String: String] = [:]
}

/// Full-screen player for live TV, movies and series, built on AetherEngine.
///
/// Siri Remote:
///   click / play-pause  → pause / resume
///   left / right        → seek back / forward (intervals in Settings → Playback)
///   up                  → cycle subtitles (off → tracks → off)
///   down                → cycle audio tracks
///   Menu / Back         → close
struct PlayerView: View {
    let request: PlaybackRequest
    @EnvironmentObject private var player: PlayerEngineHolder

    var body: some View {
        if let engine = player.engine {
            AetherPlaybackView(engine: engine, request: request)
        } else {
            ZStack {
                Color.black.ignoresSafeArea()
                Text("Player failed to start: \(player.initError ?? "unknown error")")
            }
        }
    }
}

private struct AetherPlaybackView: View {
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject var engine: AetherEngine
    @ObservedObject private var clock: PlaybackClock
    let request: PlaybackRequest

    @Environment(\.dismiss) private var dismiss
    @State private var showOverlay = true
    @State private var hideTask: Task<Void, Never>?
    @State private var toast: String?
    @State private var toastTask: Task<Void, Never>?
    @State private var loadError: String?

    // Live retune guard (see AetherEngine's Examples/LiveHost).
    @State private var retuneInFlight = false
    @State private var retuneCount = 0
    @State private var lastRetuneAt: Date?
    private static let retuneSpacing: TimeInterval = 20
    private static let retuneBudget = 3

    init(engine: AetherEngine, request: PlaybackRequest) {
        self.engine = engine
        self._clock = ObservedObject(wrappedValue: engine.clock)
        self.request = request
    }

    private var errorMessage: String? {
        if case .error(let message) = engine.state { return message }
        return loadError
    }

    private var isPaused: Bool { engine.state == .paused }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            AetherPlayerSurface(engine: engine)
                .ignoresSafeArea()

            SubtitleOverlay(cues: engine.subtitleCues, time: clock.sourceTime,
                            fontSize: settings.prefs.subtitleSize.points)
                .ignoresSafeArea()

            if errorMessage == nil && (!engine.hasFirstFrameReadyForDisplay || engine.isBuffering) {
                ProgressView().scaleEffect(1.5)
            }

            if let errorMessage {
                VStack(spacing: 16) {
                    Text("Playback failed").font(.title2).bold()
                    Text(errorMessage).multilineTextAlignment(.center)
                    Text("Press Back to return").foregroundStyle(.secondary)
                }
                .padding(40)
                .frame(maxWidth: 1200)
                .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 24))
            }

            if let toast {
                VStack {
                    Text(toast)
                        .font(.headline)
                        .padding(.horizontal, 30).padding(.vertical, 16)
                        .background(.black.opacity(0.75), in: Capsule())
                        .padding(.top, 60)
                    Spacer()
                }
                .transition(.opacity)
            }

            if showOverlay && errorMessage == nil {
                overlay
            }
        }
        .focusable()
        .focusEffectDisabled()
        .onPlayPauseCommand { togglePause() }
        .onTapGesture { togglePause() }
        .onMoveCommand { direction in
            switch direction {
            case .left: seek(by: -Double(settings.prefs.seekBackSeconds))
            case .right: seek(by: Double(settings.prefs.seekForwardSeconds))
            case .up: cycleSubtitles()
            case .down: cycleAudio()
            @unknown default: break
            }
            poke()
        }
        .onExitCommand { dismiss() }
        .task { await load() }
        .onDisappear {
            hideTask?.cancel()
            toastTask?.cancel()
            engine.stop()
        }
        .onChange(of: engine.state) { _, state in
            if state == .ended { dismiss() }
            poke()
        }
        .onReceive(engine.liveSourceReset.receive(on: DispatchQueue.main)) { _ in
            handleLiveSourceReset()
        }
    }

    // MARK: - Overlay

    private var overlay: some View {
        VStack {
            Spacer()
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    if isPaused { Image(systemName: "pause.fill") }
                    Text(request.title ?? "").font(.title3).bold().lineLimit(1)
                }
                if engine.isLive {
                    Text("LIVE").font(.caption).bold().foregroundStyle(.red)
                } else if engine.duration > 0 {
                    ProgressView(value: min(clock.currentTime, engine.duration), total: engine.duration)
                    HStack {
                        Text(Self.format(clock.currentTime))
                        Spacer()
                        Text("-" + Self.format(max(engine.duration - clock.currentTime, 0)))
                    }
                    .font(.caption)
                    .monospacedDigit()
                }
                Text("◀ −\(settings.prefs.seekBackSeconds)s   ▶ +\(settings.prefs.seekForwardSeconds)s   ▲ subtitles   ▼ audio")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 80)
            .padding(.vertical, 40)
            .background(LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom))
        }
        .ignoresSafeArea()
        .transition(.opacity)
    }

    // MARK: - Loading

    private func load() async {
        loadError = nil
        let prefs = settings.prefs
        var shaping = AudioShaping()
        if prefs.dialogueBoost { shaping.dialogueGainDB = 6 }
        if prefs.nightMode { shaping.compressor = .night }
        let subtitleLanguages = prefs.autoSubtitles ? [prefs.subtitleLanguage] : []

        let options: LoadOptions
        if request.isLive {
            options = LoadOptions(
                httpHeaders: request.httpHeaders,
                upscalesLowResolutionVideo: prefs.upscaleLowResolution,
                matchContentEnabled: prefs.matchContent,
                isLive: true,
                dvrWindowSeconds: prefs.timeshiftMinutes > 0 ? Double(prefs.timeshiftMinutes * 60) : nil,
                liveJoinProfile: prefs.channelSwitching == .fast ? .fastZap : .standard,
                nativeRemoteHLS: request.url.pathExtension.lowercased() == "m3u8",
                preferredAudioLanguages: [prefs.audioLanguage],
                preferredSubtitleLanguages: subtitleLanguages,
                audioShaping: shaping
            )
        } else {
            options = LoadOptions(
                httpHeaders: request.httpHeaders,
                upscalesLowResolutionVideo: prefs.upscaleLowResolution,
                matchContentEnabled: prefs.matchContent,
                preferredAudioLanguages: [prefs.audioLanguage],
                preferredSubtitleLanguages: subtitleLanguages,
                audioShaping: shaping
            )
        }
        do {
            _ = try await engine.load(url: request.url, options: options)
        } catch is CancellationError {
            // A newer load or a stop replaced this one; not a failure.
        } catch {
            loadError = error.localizedDescription
        }
    }

    /// The engine asks for a fresh load when a live session can't be revived.
    /// Bounded so a dead channel doesn't loop forever.
    private func handleLiveSourceReset() {
        guard request.isLive, !retuneInFlight else { return }
        let tooSoon = lastRetuneAt.map { Date().timeIntervalSince($0) < Self.retuneSpacing } ?? false
        guard retuneCount < Self.retuneBudget, !tooSoon else {
            loadError = "This channel keeps failing. Try it again later."
            return
        }
        retuneInFlight = true
        retuneCount += 1
        lastRetuneAt = Date()
        Task {
            await load()
            retuneInFlight = false
        }
    }

    // MARK: - Controls

    private func togglePause() {
        engine.togglePlayPause()
        poke()
    }

    private func seek(by seconds: Double) {
        guard engine.canSeek else {
            showToast(engine.isLive ? "Seeking isn't available on this channel" : "This stream can't seek")
            return
        }
        let target = max(0, clock.currentTime + seconds)
        Task { await engine.seek(to: target) }
    }

    private func cycleSubtitles() {
        let tracks = engine.subtitleTracks
        guard !tracks.isEmpty else {
            showToast("No subtitles")
            return
        }
        if let active = engine.activeSubtitleTrackIndex,
           let position = tracks.firstIndex(where: { $0.id == active }) {
            if position + 1 < tracks.count {
                let next = tracks[position + 1]
                engine.selectSubtitleTrack(index: next.id)
                showToast("Subtitles: \(Self.label(next))")
            } else {
                engine.clearSubtitle()
                showToast("Subtitles: Off")
            }
        } else {
            engine.selectSubtitleTrack(index: tracks[0].id)
            showToast("Subtitles: \(Self.label(tracks[0]))")
        }
    }

    private func cycleAudio() {
        let tracks = engine.audioTracks
        guard tracks.count > 1 else {
            showToast(tracks.first.map { "Audio: \(Self.label($0))" } ?? "No other audio tracks")
            return
        }
        let position = tracks.firstIndex(where: { $0.id == engine.activeAudioTrackIndex }) ?? -1
        let next = tracks[(position + 1) % tracks.count]
        engine.selectAudioTrack(index: next.id)
        showToast("Audio: \(Self.label(next))")
    }

    private func showToast(_ message: String) {
        withAnimation { toast = message }
        toastTask?.cancel()
        toastTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            withAnimation { toast = nil }
        }
    }

    /// Shows the overlay, then hides it after a few seconds unless paused.
    private func poke() {
        withAnimation { showOverlay = true }
        hideTask?.cancel()
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, !isPaused else { return }
            withAnimation { showOverlay = false }
        }
    }

    // MARK: - Formatting

    static func label(_ track: TrackInfo) -> String {
        var parts: [String] = []
        if !track.name.isEmpty { parts.append(track.name) }
        if let language = track.language, !track.name.localizedCaseInsensitiveContains(language) {
            parts.append(language.uppercased())
        }
        if parts.isEmpty { parts.append(track.codec.uppercased()) }
        return parts.joined(separator: " · ")
    }

    static func format(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
