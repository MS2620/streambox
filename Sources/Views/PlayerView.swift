import SwiftUI
import Combine
import AVFoundation
import AetherEngine

/// The channel list a live stream was started from, so the player can zap.
struct LiveContext {
    var channels: [XtreamChannel]
    var index: Int
    var channel: XtreamChannel { channels[index] }
}

struct PlaybackRequest: Identifiable {
    let id = UUID()
    var url: URL
    var title: String?
    /// Episode line for VOD (e.g. "S1E2 · Pilot").
    var subtitle: String? = nil
    var overview: String? = nil
    /// Channel logo for live TV.
    var artworkURL: URL? = nil
    /// Addon name for VOD, category for live; shown as a badge.
    var sourceName: String? = nil
    var isLive: Bool = false
    var httpHeaders: [String: String] = [:]
    var live: LiveContext? = nil
}

/// Full-screen player for live TV, movies and series, built on AetherEngine.
///
/// Siri Remote, controls hidden:
///   click             → show controls
///   play/pause        → pause / resume
///   left / right      → skip back / forward (when the stream can seek)
///   up / down         → previous / next channel (live) or show controls
///   Back              → close the player
/// Controls shown: swipe between the buttons; Back hides them.
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

private enum OverlayMode { case hidden, info, controls }

private enum Panel: Identifiable {
    case channels, subtitles, audio, more
    var id: Self { self }

    var title: String {
        switch self {
        case .channels: return "Channels"
        case .subtitles: return "Subtitles"
        case .audio: return "Audio"
        case .more: return "More"
        }
    }
}

private enum Control: Hashable { case aspect, favourite, channels, subtitles, audio, more, progress }

private struct PanelOption: Identifiable {
    let id: String
    let title: String
    var detail: String? = nil
    var selected = false
    let action: () -> Void
}

private struct AetherPlaybackView: View {
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject var engine: AetherEngine
    @ObservedObject private var clock: PlaybackClock
    @State private var current: PlaybackRequest

    @Environment(\.dismiss) private var dismiss
    @State private var mode: OverlayMode = .controls
    @State private var panel: Panel?
    @State private var hideTask: Task<Void, Never>?
    @State private var toast: String?
    @State private var toastTask: Task<Void, Never>?
    @State private var loadError: String?
    @State private var epg: [XtreamEPGEntry] = []
    @State private var fillScreen = false
    @State private var rate: Float = 1
    @FocusState private var focusedControl: Control?
    @FocusState private var focusedOption: String?
    @FocusState private var rootFocused: Bool

    // Live retune guard (see AetherEngine's Examples/LiveHost).
    @State private var retuneInFlight = false
    @State private var retuneCount = 0
    @State private var lastRetuneAt: Date?
    private static let retuneSpacing: TimeInterval = 20
    private static let retuneBudget = 3

    init(engine: AetherEngine, request: PlaybackRequest) {
        self.engine = engine
        self._clock = ObservedObject(wrappedValue: engine.clock)
        self._current = State(initialValue: request)
    }

    // MARK: - Derived state

    private var errorMessage: String? {
        if case .error(let message) = engine.state { return message }
        return loadError
    }

    private var isPaused: Bool { engine.state == .paused }
    private var prefs: Preferences { settings.prefs }

    private var epgNow: XtreamEPGEntry? {
        let now = Date()
        return epg.first { ($0.start ?? .distantFuture) <= now && now < ($0.end ?? .distantPast) }
    }

    private var epgNext: XtreamEPGEntry? {
        guard let end = epgNow?.end else { return nil }
        return epg.first { ($0.start ?? .distantPast) >= end }
    }

    private var programmeTitle: String? {
        current.live != nil ? epgNow?.title : current.subtitle
    }

    private var programmeDescription: String? {
        current.live != nil ? epgNow?.description : current.overview
    }

    private var isFavourite: Bool {
        guard let id = current.live?.channel.id else { return false }
        return prefs.favouriteChannelIDs.contains(id)
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            AetherPlayerSurface(engine: engine)
                .ignoresSafeArea()

            SubtitleOverlay(cues: engine.subtitleCues, time: clock.sourceTime,
                            fontSize: prefs.subtitleSize.points)
                .ignoresSafeArea()

            // Catches the remote while the buttons are hidden. It is a sibling of the
            // controls (not their parent), so it never steals focus navigation from them.
            if mode != .controls && panel == nil {
                Color.clear
                    .contentShape(Rectangle())
                    .focusable()
                    .focused($rootFocused)
                    .focusEffectDisabled()
                    .onTapGesture { showControls() }
                    .onMoveCommand { direction in handleMove(direction) }
                    .onAppear { rootFocused = true }
                    .ignoresSafeArea()
            }

            if errorMessage == nil && (!engine.hasFirstFrameReadyForDisplay || engine.isBuffering) {
                ProgressView().scaleEffect(1.5)
            }

            if let errorMessage {
                errorBox(errorMessage)
            }

            if mode != .hidden && panel == nil {
                overlay.transition(.opacity)
            }

            if let panel {
                panelView(panel).transition(.move(edge: .trailing))
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
        }
        .onPlayPauseCommand { togglePause() }
        .onExitCommand { handleExit() }
        .task(id: current.id) { await load() }
        .task(id: current.live?.channel.id) { await epgLoop() }
        .onAppear { showControls() }
        .onDisappear {
            hideTask?.cancel()
            toastTask?.cancel()
            engine.stop()
        }
        .onChange(of: engine.state) { _, state in
            if state == .ended { dismiss() }
        }
        .onChange(of: focusedControl) { _, _ in scheduleHide() }
        .onReceive(engine.liveSourceReset.receive(on: DispatchQueue.main)) { _ in
            handleLiveSourceReset()
        }
    }

    // MARK: - Overlay

    private var overlay: some View {
        ZStack {
            VStack {
                LinearGradient(colors: [.black.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 220)
                Spacer()
                LinearGradient(colors: [.clear, .black.opacity(0.92)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 620)
            }

            VStack {
                HStack {
                    Spacer()
                    TimelineView(.everyMinute) { context in
                        Text(context.date.formatted(date: .omitted, time: .shortened))
                            .font(.title3).bold().monospacedDigit()
                    }
                }
                Spacer()
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .bottom, spacing: 40) {
                        infoColumn
                        Spacer(minLength: 0)
                        if mode == .controls { controlsPill }
                    }
                    progressSection
                }
            }
            .padding(.horizontal, 90)
            .padding(.top, 50)
            .padding(.bottom, 55)
        }
        .ignoresSafeArea()
    }

    private var infoColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 18) {
                if let artwork = current.artworkURL {
                    AsyncImage(url: artwork) { image in
                        image.resizable().aspectRatio(contentMode: .fit)
                    } placeholder: {
                        Color.clear
                    }
                    .frame(width: 110, height: 56)
                }
                Text(current.title ?? "").font(.title2).bold().lineLimit(1)
                if isPaused {
                    Image(systemName: "pause.fill").font(.title3)
                }
            }

            HStack(spacing: 10) {
                ForEach(badges, id: \.self) { badge in
                    Text(badge)
                        .font(.system(size: 18, weight: .semibold))
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(.white.opacity(0.18), in: Capsule())
                }
            }

            if let title = programmeTitle, !title.isEmpty {
                Text(title).font(.headline).lineLimit(1)
            }
            if let description = programmeDescription, !description.isEmpty {
                Text(description)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: 1100, alignment: .leading)
    }

    @ViewBuilder
    private var progressSection: some View {
        if current.live != nil {
            if let now = epgNow, let start = now.start, let end = now.end, end > start {
                let playhead = Date().addingTimeInterval(-clock.behindLiveSeconds)
                let fraction = playhead.timeIntervalSince(start) / end.timeIntervalSince(start)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(Self.time(start))
                        Spacer()
                        Text(Self.time(end))
                    }
                    .font(.caption).monospacedDigit()
                    scrubbableBar(fraction: fraction)
                    ZStack(alignment: .trailing) {
                        PositionMarker(fraction: fraction, label: Self.time(playhead), live: clock.behindLiveSeconds < 5)
                        if let next = epgNext, let nextStart = next.start {
                            Text("\(Self.time(nextStart))  \(next.title)")
                                .font(.callout).bold().lineLimit(1)
                                .frame(maxWidth: 520, alignment: .trailing)
                        }
                    }
                }
            } else {
                HStack(spacing: 10) {
                    Circle().fill(.red).frame(width: 14, height: 14)
                    Text("LIVE").font(.caption).bold()
                }
            }
        } else if engine.duration > 0 {
            let fraction = clock.currentTime / engine.duration
            VStack(alignment: .leading, spacing: 8) {
                scrubbableBar(fraction: fraction)
                ZStack(alignment: .trailing) {
                    PositionMarker(fraction: fraction, label: Self.duration(clock.currentTime), live: false)
                    Text("-" + Self.duration(max(engine.duration - clock.currentTime, 0)))
                        .font(.callout).monospacedDigit()
                }
            }
        }
    }

    /// The progress bar. With the buttons shown, press down to focus it, then
    /// left / right to rewind / fast-forward; up returns to the buttons.
    private func scrubbableBar(fraction: Double) -> some View {
        ProgressBar(fraction: fraction, highlighted: focusedControl == .progress)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .focusable(mode == .controls)
            .focused($focusedControl, equals: .progress)
            .focusEffectDisabled()
            .onMoveCommand { direction in
                switch direction {
                case .left: seek(by: -Double(prefs.seekBackSeconds))
                case .right: seek(by: Double(prefs.seekForwardSeconds))
                case .up: focusedControl = .aspect
                default: break
                }
                scheduleHide()
            }
    }

    private var controlsPill: some View {
        HStack(spacing: 12) {
            controlButton(fillScreen ? "arrow.down.right.and.arrow.up.left" : "aspectratio", .aspect) {
                toggleAspect()
            }
            if current.live != nil {
                controlButton(isFavourite ? "heart.fill" : "heart", .favourite) { toggleFavourite() }
                controlButton("square.grid.2x2", .channels) { open(.channels) }
            }
            controlButton("captions.bubble", .subtitles) { open(.subtitles) }
            controlButton("waveform", .audio) { open(.audio) }
            controlButton("ellipsis", .more) { open(.more) }
        }
        .padding(10)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private func controlButton(_ icon: String, _ control: Control, action: @escaping () -> Void) -> some View {
        Button {
            action()
            scheduleHide()
        } label: {
            PillIcon(systemName: icon)
        }
        .buttonStyle(BareButtonStyle())
        .focused($focusedControl, equals: control)
    }

    private func errorBox(_ message: String) -> some View {
        VStack(spacing: 16) {
            Text("Playback failed").font(.title2).bold()
            Text(message).multilineTextAlignment(.center)
            Text(current.live != nil ? "Press up or down to try another channel, or Back to return"
                                     : "Press Back to return")
                .foregroundStyle(.secondary)
        }
        .padding(40)
        .frame(maxWidth: 1200)
        .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 24))
    }

    // MARK: - Badges

    private var badges: [String] {
        var list = ["AetherEngine"]
        if let source = current.sourceName, !source.isEmpty { list.append(source) }
        if let resolution = resolutionLabel { list.append(resolution) }
        list.append(Self.formatLabel(engine.videoFormat))
        if let fps = engine.sourceVideoFrameRate, fps > 0 {
            list.append(abs(fps - fps.rounded()) < 0.01 ? "\(Int(fps.rounded())) fps" : String(format: "%.2f fps", fps))
        }
        if let audio = audioLabel { list.append(audio) }
        return list
    }

    private var resolutionLabel: String? {
        let size = engine.currentAVPlayerItem?.presentationSize ?? engine.softwareDisplaySize ?? .zero
        let width = max(size.width, size.height * 16 / 9)
        switch width {
        case 3000...: return "4K"
        case 1800..<3000: return "1080p"
        case 1200..<1800: return "720p"
        case 1..<1200: return "SD"
        default: return nil
        }
    }

    private var audioLabel: String? {
        let tracks = engine.audioTracks
        guard let track = tracks.first(where: { $0.id == engine.activeAudioTrackIndex }) ?? tracks.first else { return nil }
        return Self.audioDescription(track)
    }

    // MARK: - Panels

    private func panelView(_ panel: Panel) -> some View {
        let options = panelOptions(panel)
        return HStack {
            Spacer()
            VStack(alignment: .leading, spacing: 24) {
                Text(panel.title).font(.title3).bold()
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(options) { option in
                                Button {
                                    option.action()
                                } label: {
                                    PanelRow(option: option)
                                }
                                .buttonStyle(BareButtonStyle())
                                .focused($focusedOption, equals: option.id)
                                .id(option.id)
                            }
                        }
                        .padding(.vertical, 10)
                    }
                    .onAppear {
                        let target = options.first(where: \.selected)?.id ?? options.first?.id
                        if let target {
                            proxy.scrollTo(target, anchor: .center)
                            Task { @MainActor in
                                try? await Task.sleep(for: .milliseconds(80))
                                focusedOption = target
                            }
                        }
                    }
                }
            }
            .padding(50)
            .frame(width: 760)
            .frame(maxHeight: .infinity)
            .background(.ultraThinMaterial)
        }
        .ignoresSafeArea()
    }

    private func panelOptions(_ panel: Panel) -> [PanelOption] {
        switch panel {
        case .subtitles:
            var options = [PanelOption(id: "off", title: "Off", selected: engine.activeSubtitleTrackIndex == nil) {
                engine.clearSubtitle()
                closePanel()
            }]
            options += engine.subtitleTracks.map { track in
                PanelOption(id: "sub-\(track.id)", title: Self.trackTitle(track),
                            detail: track.isForced ? "Forced" : (track.isHearingImpaired ? "SDH" : nil),
                            selected: track.id == engine.activeSubtitleTrackIndex) {
                    engine.selectSubtitleTrack(index: track.id)
                    closePanel()
                }
            }
            return options

        case .audio:
            return engine.audioTracks.map { track in
                PanelOption(id: "audio-\(track.id)", title: Self.trackTitle(track),
                            detail: Self.audioDescription(track),
                            selected: track.id == engine.activeAudioTrackIndex) {
                    engine.selectAudioTrack(index: track.id)
                    closePanel()
                }
            }

        case .channels:
            guard let live = current.live else { return [] }
            return live.channels.enumerated().map { index, channel in
                PanelOption(id: "ch-\(channel.id)",
                            title: channel.number.map { "\($0)  \(channel.name)" } ?? channel.name,
                            detail: prefs.favouriteChannelIDs.contains(channel.id) ? "★" : nil,
                            selected: index == live.index) {
                    zap(to: index)
                    closePanel()
                }
            }

        case .more:
            if current.live != nil {
                var options: [PanelOption] = []
                if engine.canSeek {
                    options.append(PanelOption(id: "live-edge", title: "Jump to live") {
                        Task { await engine.seekToLiveEdge() }
                        closePanel()
                    })
                }
                options.append(PanelOption(id: "reload", title: "Reload channel") {
                    reload()
                    closePanel()
                })
                return options
            } else {
                var options = [PanelOption(id: "restart", title: "Restart from the beginning") {
                    Task { await engine.seek(to: 0) }
                    closePanel()
                }]
                for speed: Float in [0.75, 1, 1.25, 1.5, 2] {
                    options.append(PanelOption(id: "speed-\(speed)", title: "Speed \(Self.speedLabel(speed))",
                                               selected: speed == rate) {
                        rate = speed
                        engine.setRate(speed)
                        closePanel()
                    })
                }
                return options
            }
        }
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
        if current.isLive {
            options = LoadOptions(
                httpHeaders: current.httpHeaders,
                upscalesLowResolutionVideo: prefs.upscaleLowResolution,
                matchContentEnabled: prefs.matchContent,
                isLive: true,
                dvrWindowSeconds: prefs.timeshiftMinutes > 0 ? Double(prefs.timeshiftMinutes * 60) : nil,
                liveJoinProfile: prefs.channelSwitching == .fast ? .fastZap : .standard,
                nativeRemoteHLS: current.url.pathExtension.lowercased() == "m3u8",
                preferredAudioLanguages: [prefs.audioLanguage],
                preferredSubtitleLanguages: subtitleLanguages,
                audioShaping: shaping
            )
        } else {
            options = LoadOptions(
                httpHeaders: current.httpHeaders,
                upscalesLowResolutionVideo: prefs.upscaleLowResolution,
                matchContentEnabled: prefs.matchContent,
                preferredAudioLanguages: [prefs.audioLanguage],
                preferredSubtitleLanguages: subtitleLanguages,
                audioShaping: shaping
            )
        }
        do {
            // The Live TV guide preview plays muted on the same engine.
            engine.volume = 1
            _ = try await engine.load(url: current.url, options: options)
            engine.videoGravity = fillScreen ? .resizeAspectFill : .resizeAspect
        } catch is CancellationError {
            // A newer load or a stop replaced this one; not a failure.
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func epgLoop() async {
        epg = []
        guard let channel = current.live?.channel, prefs.showEPG else { return }
        while !Task.isCancelled {
            if let entries = try? await settings.xtreamClient.shortEPG(streamID: channel.id, limit: 4) {
                epg = entries
            }
            try? await Task.sleep(for: .seconds(60))
        }
    }

    /// The engine asks for a fresh load when a live session can't be revived.
    private func handleLiveSourceReset() {
        guard current.isLive, !retuneInFlight else { return }
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

    // MARK: - Remote handling

    private func handleMove(_ direction: MoveCommandDirection) {
        switch direction {
        case .left: seek(by: -Double(prefs.seekBackSeconds))
        case .right: seek(by: Double(prefs.seekForwardSeconds))
        case .up: current.live != nil ? zap(by: -1) : showControls()
        case .down: current.live != nil ? zap(by: 1) : showControls()
        @unknown default: break
        }
    }

    private func handleExit() {
        if panel != nil {
            closePanel()
        } else if mode != .hidden {
            hide()
        } else {
            dismiss()
        }
    }

    private func showControls() {
        withAnimation(.easeOut(duration: 0.2)) { mode = .controls }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(60))
            if focusedControl == nil { focusedControl = .aspect }
        }
        scheduleHide()
    }

    /// Info only (no buttons), e.g. after a seek or channel change.
    private func showInfo() {
        if mode == .hidden { withAnimation(.easeOut(duration: 0.2)) { mode = .info } }
        scheduleHide(after: mode == .controls ? 6 : 4)
    }

    private func hide() {
        hideTask?.cancel()
        focusedControl = nil
        withAnimation(.easeIn(duration: 0.2)) { mode = .hidden }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            rootFocused = true
        }
    }

    private func scheduleHide(after seconds: Double = 6) {
        hideTask?.cancel()
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, panel == nil, !isPaused else { return }
            hide()
        }
    }

    private func open(_ newPanel: Panel) {
        hideTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) { panel = newPanel }
    }

    private func closePanel() {
        withAnimation(.easeIn(duration: 0.2)) { panel = nil }
        showControls()
    }

    // MARK: - Actions

    private func togglePause() {
        engine.togglePlayPause()
        if mode == .hidden { showInfo() } else { scheduleHide() }
    }

    private func seek(by seconds: Double) {
        guard engine.canSeek else {
            showToast(engine.isLive ? "Turn on timeshift in Settings → Live TV to rewind" : "This stream can't seek")
            return
        }
        let target = max(0, clock.currentTime + seconds)
        Task { await engine.seek(to: target) }
        showInfo()
    }

    private func zap(by delta: Int) {
        guard let live = current.live, !live.channels.isEmpty else { return }
        let count = live.channels.count
        zap(to: ((live.index + delta) % count + count) % count)
    }

    private func zap(to index: Int) {
        guard let live = current.live, live.channels.indices.contains(index) else { return }
        let channel = live.channels[index]
        guard let url = settings.xtreamClient.liveURL(for: channel, format: prefs.liveFormat) else { return }
        retuneCount = 0
        lastRetuneAt = nil
        current = PlaybackRequest(
            url: url,
            title: channel.name,
            artworkURL: channel.icon.flatMap { URL(string: $0) },
            sourceName: current.sourceName,
            isLive: true,
            httpHeaders: current.httpHeaders,
            live: LiveContext(channels: live.channels, index: index)
        )
        showInfo()
    }

    private func reload() {
        var copy = current
        copy = PlaybackRequest(url: copy.url, title: copy.title, subtitle: copy.subtitle, overview: copy.overview,
                               artworkURL: copy.artworkURL, sourceName: copy.sourceName, isLive: copy.isLive,
                               httpHeaders: copy.httpHeaders, live: copy.live)
        retuneCount = 0
        current = copy
    }

    private func toggleAspect() {
        fillScreen.toggle()
        engine.videoGravity = fillScreen ? .resizeAspectFill : .resizeAspect
        showToast(fillScreen ? "Fill screen" : "Fit to screen")
    }

    private func toggleFavourite() {
        guard let id = current.live?.channel.id else { return }
        if settings.prefs.favouriteChannelIDs.contains(id) {
            settings.prefs.favouriteChannelIDs.remove(id)
            showToast("Removed from Favourites")
        } else {
            settings.prefs.favouriteChannelIDs.insert(id)
            showToast("Added to Favourites")
        }
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

    // MARK: - Formatting

    static func trackTitle(_ track: TrackInfo) -> String {
        if !track.name.isEmpty { return track.name }
        if let language = track.language, !language.isEmpty {
            return Locale.current.localizedString(forLanguageCode: language) ?? language.uppercased()
        }
        return "Track \(track.id)"
    }

    static func audioDescription(_ track: TrackInfo) -> String {
        if track.isAtmos { return "Dolby Atmos" }
        if track.isDTSX { return "DTS:X" }
        let codec: String
        switch track.codec.lowercased() {
        case "eac3": codec = "Dolby Digital+"
        case "ac3": codec = "Dolby Digital"
        case "truehd": codec = "Dolby TrueHD"
        case "dts": codec = "DTS"
        case "aac": codec = "AAC"
        case "flac": codec = "FLAC"
        case "opus": codec = "Opus"
        case "mp3", "mp2": codec = "MP3"
        default: codec = track.codec.uppercased()
        }
        switch track.channels {
        case 8: return "\(codec) 7.1"
        case 6: return "\(codec) 5.1"
        case 2: return "\(codec) Stereo"
        case 1: return "\(codec) Mono"
        default: return codec
        }
    }

    static func formatLabel(_ format: VideoFormat) -> String {
        switch format {
        case .sdr: return "SDR"
        case .hdr10: return "HDR10"
        case .hdr10Plus: return "HDR10+"
        case .dolbyVision: return "Dolby Vision"
        case .hlg: return "HLG"
        @unknown default: return "Video"
        }
    }

    static func speedLabel(_ speed: Float) -> String {
        speed == 1 ? "Normal" : "\(speed.formatted())×"
    }

    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    static func duration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

// MARK: - Small views

/// A button style with no system chrome; the label draws its own focus state.
private struct BareButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.7 : 1)
    }
}

private struct PillIcon: View {
    let systemName: String
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 28, weight: .semibold))
            .foregroundStyle(isFocused ? Color.black : Color.white)
            .frame(width: 76, height: 76)
            .background(Circle().fill(isFocused ? Color.white : Color.clear))
            .scaleEffect(isFocused ? 1.08 : 1)
            .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}

private struct PanelRow: View {
    let option: PanelOption
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(option.title).lineLimit(1)
                if let detail = option.detail {
                    Text(detail).font(.caption).opacity(0.7).lineLimit(1)
                }
            }
            Spacer()
            if option.selected {
                Image(systemName: "checkmark").font(.headline)
            }
        }
        .foregroundStyle(isFocused ? Color.black : Color.white)
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(isFocused ? Color.white : Color.white.opacity(0.06)))
        .animation(.easeOut(duration: 0.12), value: isFocused)
    }
}

private struct ProgressBar: View {
    let fraction: Double
    var highlighted = false

    var body: some View {
        let clamped = min(max(fraction, 0), 1)
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.25))
                Capsule().fill(.white)
                    .frame(width: geo.size.width * clamped)
                if highlighted {
                    Circle()
                        .fill(.white)
                        .frame(width: 26, height: 26)
                        .shadow(radius: 4)
                        .offset(x: geo.size.width * clamped - 13)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: highlighted ? 14 : 8)
        .animation(.easeOut(duration: 0.15), value: highlighted)
    }
}

/// "● 01:20" under the bar, at the playhead's position.
private struct PositionMarker: View {
    let fraction: Double
    let label: String
    let live: Bool

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 8) {
                if live { Circle().fill(.red).frame(width: 12, height: 12) }
                Text(label).font(.callout).bold().monospacedDigit()
            }
            .fixedSize()
            .position(x: min(max(geo.size.width * min(max(fraction, 0), 1), 70), geo.size.width - 70),
                      y: geo.size.height / 2)
        }
        .frame(height: 34)
    }
}
