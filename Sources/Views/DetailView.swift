import SwiftUI

struct StreamTarget: Identifiable, Hashable {
    let type: String   // "movie" or "series"
    let id: String     // Stremio id, e.g. "tt0903747:1:1"
    let title: String
    /// Episode line for the player, e.g. "S1E2 · Pilot".
    var subtitle: String? = nil
    var overview: String? = nil
    /// Shown on the stream page: "MOVIE · 2026" or "SEASON 1 · EPISODE 2".
    var kicker: String? = nil
    /// Episode name or year, under the title on the stream page.
    var detail: String? = nil
    var posterURL: URL? = nil
    var backdropURL: URL? = nil
}

struct DetailView: View {
    @EnvironmentObject var settings: AppSettings
    let item: TMDBItem

    @State private var details: TMDBDetails?
    @State private var selectedSeason = 1
    @State private var episodes: [TVEpisode] = []
    @State private var loadingEpisodes = false
    @State private var streamTarget: StreamTarget?
    @State private var error: String?

    private var tmdb: TMDBClient { settings.tmdb }
    private var imdbID: String? { details?.externalIds?.imdbId }
    private var seasons: [TVSeasonSummary] { (details?.seasons ?? []).filter { $0.seasonNumber > 0 } }
    private var inMyList: Bool { settings.prefs.myList.contains { $0.uid == item.uid } }

    private var recommendations: [TMDBItem] {
        (details?.recommendations?.results ?? []).map { rec in
            var copy = rec
            if copy.mediaType == nil { copy.mediaType = item.kind.rawValue }
            return copy
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            backdrop

            ScrollView {
                VStack(alignment: .leading, spacing: 40) {
                    header
                        .padding(.top, 360)

                    if item.kind == .tv {
                        seasonPicker
                        episodeRow
                    }

                    if !recommendations.isEmpty {
                        RailView(title: "More Like This", items: recommendations)
                    }
                }
                .padding(.bottom, 80)
            }
        }
        .ignoresSafeArea()
        .task { await load() }
        .task(id: selectedSeason) { await loadEpisodes() }
        .navigationDestination(item: $streamTarget) { target in
            StreamListView(target: target)
        }
    }

    // MARK: - Sections

    private var backdrop: some View {
        GeometryReader { geo in
            AsyncImage(url: item.backdropURL) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Color.black
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .overlay(
                LinearGradient(colors: [.black.opacity(0.85), .black.opacity(0.35), .clear],
                               startPoint: .leading, endPoint: .trailing)
            )
            .overlay(
                LinearGradient(colors: [.clear, .black.opacity(0.55), .black],
                               startPoint: .center, endPoint: .bottom)
            )
        }
        .ignoresSafeArea()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(item.kind == .movie ? "MOVIE" : "SERIES")
                .font(.caption).bold()
                .foregroundStyle(.secondary)

            Text(item.displayTitle)
                .font(.system(size: 72, weight: .bold))
                .lineLimit(2)

            metadataLine

            if let tagline = details?.tagline, !tagline.isEmpty {
                Text(tagline).italic().foregroundStyle(.secondary)
            }

            Text(item.overview ?? "")
                .font(.callout)
                .lineLimit(4)
                .frame(maxWidth: 1100, alignment: .leading)

            if let cast = details?.credits?.cast, !cast.isEmpty {
                Text("Starring " + cast.prefix(4).map(\.name).joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if let error {
                Text(error).foregroundStyle(.red)
            }

            HStack(spacing: 28) {
                playButton
                Button {
                    toggleMyList()
                } label: {
                    Label(inMyList ? "In My List" : "My List",
                          systemImage: inMyList ? "checkmark" : "plus")
                }
            }
            .padding(.top, 8)
        }
        .padding(.horizontal, 90)
    }

    private var metadataLine: some View {
        var parts: [String] = []
        if let year = item.year { parts.append(year) }
        if item.kind == .movie, let runtime = details?.runtime, runtime > 0 {
            parts.append(runtime >= 60 ? "\(runtime / 60)h \(runtime % 60)m" : "\(runtime)m")
        }
        if item.kind == .tv, let count = details?.numberOfSeasons, count > 0 {
            parts.append(count == 1 ? "1 Season" : "\(count) Seasons")
        }
        if let genres = details?.genres, !genres.isEmpty {
            parts.append(genres.prefix(3).map(\.name).joined(separator: ", "))
        }
        return HStack(spacing: 14) {
            Text(parts.joined(separator: "  ·  "))
            if let rating = item.rating {
                Label(rating, systemImage: "star.fill").labelStyle(.titleAndIcon)
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var playButton: some View {
        if item.kind == .movie {
            Button {
                if let imdbID {
                    streamTarget = StreamTarget(type: "movie", id: imdbID, title: item.displayTitle,
                                                subtitle: item.year, overview: item.overview,
                                                kicker: "MOVIE", detail: item.year,
                                                posterURL: item.posterURL, backdropURL: item.backdropURL)
                }
            } label: {
                Label("Play", systemImage: "play.fill")
            }
            .disabled(imdbID == nil)
        } else {
            Button {
                if let first = episodes.first { play(first) }
            } label: {
                Label("Play S\(selectedSeason) E1", systemImage: "play.fill")
            }
            .disabled(imdbID == nil || episodes.isEmpty)
        }
    }

    private var seasonPicker: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 20) {
                    ForEach(seasons) { season in
                        Button {
                            selectedSeason = season.seasonNumber
                        } label: {
                            HStack(spacing: 8) {
                                if season.seasonNumber == selectedSeason {
                                    Image(systemName: "checkmark")
                                }
                                Text(season.name ?? "Season \(season.seasonNumber)")
                            }
                        }
                        .id(season.seasonNumber)
                    }
                }
                .padding(.horizontal, 90)
                .padding(.vertical, 20)
            }
            .scrollClipDisabled()
            .onChange(of: seasons.count) { _, _ in
                proxy.scrollTo(selectedSeason, anchor: .leading)
            }
        }
    }

    private var episodeRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Episodes")
                .font(.title3).bold()
                .padding(.horizontal, 90)
            if loadingEpisodes && episodes.isEmpty {
                ProgressView()
                    .frame(height: 330)
                    .padding(.horizontal, 90)
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 44) {
                        ForEach(episodes) { episode in
                            Button {
                                play(episode)
                            } label: {
                                EpisodeCard(episode: episode, fallbackImage: item.backdropURL)
                            }
                            .buttonStyle(.borderless)
                            .disabled(imdbID == nil)
                        }
                    }
                    .padding(.horizontal, 90)
                    .padding(.vertical, 30)
                }
                .scrollClipDisabled()
            }
        }
    }

    // MARK: - Actions

    private func play(_ episode: TVEpisode) {
        guard let imdbID else { return }
        streamTarget = StreamTarget(
            type: "series",
            id: "\(imdbID):\(episode.seasonNumber):\(episode.episodeNumber)",
            title: item.displayTitle,
            subtitle: "S\(episode.seasonNumber)E\(episode.episodeNumber) · \(episode.name ?? "Episode \(episode.episodeNumber)")",
            overview: episode.overview,
            kicker: "SEASON \(episode.seasonNumber) · EPISODE \(episode.episodeNumber)",
            detail: episode.name,
            posterURL: item.posterURL,
            backdropURL: item.backdropURL
        )
    }

    private func toggleMyList() {
        if inMyList {
            settings.prefs.myList.removeAll { $0.uid == item.uid }
        } else {
            settings.prefs.myList.append(item)
        }
    }

    private func load() async {
        do {
            let loaded = try await tmdb.details(for: item)
            details = loaded
            if loaded.externalIds?.imdbId == nil {
                error = "No IMDb id for this title, so addons can't look it up."
            }
            if item.kind == .tv, let first = seasons.first,
               !seasons.contains(where: { $0.seasonNumber == selectedSeason }) {
                selectedSeason = first.seasonNumber
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func loadEpisodes() async {
        guard item.kind == .tv else { return }
        loadingEpisodes = true
        defer { loadingEpisodes = false }
        episodes = (try? await tmdb.episodes(tvID: item.id, season: selectedSeason)) ?? []
    }
}

/// A 16:9 episode thumbnail with its number, title, runtime and synopsis.
private struct EpisodeCard: View {
    let episode: TVEpisode
    let fallbackImage: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            AsyncImage(url: episode.stillURL ?? fallbackImage) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                ZStack {
                    Color.gray.opacity(0.3)
                    Image(systemName: "play.rectangle").font(.largeTitle)
                }
            }
            .frame(width: 440, height: 248)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            Text("E\(episode.episodeNumber) · \(episode.name ?? "Episode \(episode.episodeNumber)")")
                .font(.callout).bold()
                .lineLimit(1)

            HStack(spacing: 12) {
                if let runtime = episode.runtime, runtime > 0 { Text("\(runtime)m") }
                if let airDate = episode.airDate, !airDate.isEmpty { Text(airDate) }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let overview = episode.overview, !overview.isEmpty {
                Text(overview)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(width: 440, alignment: .leading)
    }
}

struct StreamListView: View {
    @EnvironmentObject var settings: AppSettings
    let target: StreamTarget

    @State private var results: [FoundStream] = []
    @State private var loading = true
    @State private var status: String?
    @State private var playback: PlaybackRequest?

    /// The quality filter: nil shows everything.
    @State private var filter: StreamQuality?

    private var counts: [StreamQuality: Int] {
        Dictionary(grouping: results, by: { StreamQuality($0.stream.resolution) }).mapValues(\.count)
    }

    private var shown: [FoundStream] {
        guard let filter else { return results }
        return results.filter { StreamQuality($0.stream.resolution) == filter }
    }

    private var addonCount: Int {
        Set(results.map(\.addonName)).count
    }

    var body: some View {
        ZStack {
            backdrop
            HStack(alignment: .top, spacing: 80) {
                summary
                    .frame(width: 620, alignment: .leading)
                list
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 90)
            .padding(.top, 70)
        }
        .task { await search() }
        .fullScreenCover(item: $playback) { request in
            PlayerView(request: request).ignoresSafeArea()
        }
    }

    private var backdrop: some View {
        ZStack {
            Theme.base
            AsyncImage(url: target.backdropURL) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Color.clear
            }
            .blur(radius: 40)
            .opacity(0.7)
            LinearGradient(colors: [Theme.base.opacity(0.92), Theme.base.opacity(0.75), Theme.base.opacity(0.55)],
                           startPoint: .leading, endPoint: .trailing)
        }
        .ignoresSafeArea()
    }

    /// The title on the left, with the quality filters.
    private var summary: some View {
        VStack(alignment: .leading, spacing: 20) {
            AsyncImage(url: target.posterURL) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                RoundedRectangle(cornerRadius: 20).fill(Theme.glass)
            }
            .frame(width: 240, height: 360)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.45), radius: 20, y: 12)

            if let kicker = target.kicker {
                Text(kicker)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white.opacity(0.65))
            }
            Text(target.title)
                .font(.system(size: 52, weight: .heavy))
                .lineLimit(2)
                .minimumScaleFactor(0.6)
            if let detail = target.detail, !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
            }

            if !results.isEmpty {
                ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    Button {
                        filter = nil
                    } label: {
                        PillLabel(title: "All · \(results.count)", selected: filter == nil)
                    }
                    .buttonStyle(PlainPressStyle())
                    ForEach(StreamQuality.allCases.filter { (counts[$0] ?? 0) > 0 }, id: \.self) { quality in
                        Button {
                            filter = quality
                        } label: {
                            PillLabel(title: "\(quality.label) · \(counts[quality] ?? 0)", selected: filter == quality)
                        }
                        .buttonStyle(PlainPressStyle())
                    }
                }
                .padding(.vertical, 10)
                }
                .scrollClipDisabled()

                Text(settings.prefs.streamSort == .quality
                     ? "Sorted best quality first · change in Settings › Streams"
                     : "In addon order · change in Settings › Streams")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
    }

    @ViewBuilder
    private var list: some View {
        VStack(alignment: .leading, spacing: 16) {
            if loading {
                ProgressView("Searching \(settings.addons.count) addon\(settings.addons.count == 1 ? "" : "s")…")
                    .frame(maxWidth: .infinity)
                    .padding(.top, 80)
            } else if results.isEmpty {
                Text(settings.addons.isEmpty
                     ? "No addons yet. Add a Stremio addon in Settings › Connections."
                     : "No playable streams found.")
                    .font(.system(size: 30, weight: .bold))
                    .padding(.top, 40)
            } else {
                Text("\(results.count) STREAM\(results.count == 1 ? "" : "S") FROM \(addonCount) ADDON\(addonCount == 1 ? "" : "S")")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
            }
            if let status {
                Text(status)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
            }
            if !shown.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(shown) { result in
                            Button {
                                Task { await play(result) }
                            } label: {
                                StreamCard(result: result)
                            }
                            .buttonStyle(PlainPressStyle())
                        }
                    }
                    .padding(.vertical, 20)
                    .padding(.horizontal, 10)
                }
                .scrollClipDisabled()
            }
        }
    }

    private func search() async {
        loading = true
        var found: [FoundStream] = []
        var failures: [String] = []
        let type = target.type
        let id = target.id

        await withTaskGroup(of: (String, [StremioStream]?).self) { group in
            for addon in settings.addons {
                guard let url = URL(string: addon.manifestURL) else { continue }
                let name = addon.name
                group.addTask {
                    let streams = try? await StremioAddonClient(manifestURL: url).streams(type: type, id: id)
                    return (name, streams)
                }
            }
            for await (name, streams) in group {
                if let streams {
                    found += streams.map { FoundStream(addonName: name, stream: $0) }
                } else {
                    failures.append(name)
                }
            }
        }

        // Only direct links can be played; torrent-only results are left out.
        let playable = found.filter { $0.stream.playableURL != nil }
        let skipped = found.count - playable.count
        results = arrange(playable)
        loading = false
        var notes: [String] = []
        if !failures.isEmpty { notes.append("Failed to reach: " + failures.joined(separator: ", ")) }
        if skipped > 0 {
            notes.append("\(skipped) torrent-only result(s) hidden. Set your addon up to return direct links.")
        }
        if !notes.isEmpty { status = notes.joined(separator: "\n") }

        if settings.prefs.autoPlayFirstStream, let first = results.first {
            await play(first)
        }
    }

    /// Applies the resolution limit and sort order from Settings → Streams.
    private func arrange(_ streams: [FoundStream]) -> [FoundStream] {
        let prefs = settings.prefs
        var list = streams
        if prefs.maxResolution != .any {
            // Unknown resolution (0) is kept rather than hidden.
            list = list.filter { $0.stream.resolution <= prefs.maxResolution.maxLines }
        }
        if prefs.streamSort == .quality {
            // Stable sort: keeps addon order within the same resolution.
            list = list.enumerated()
                .sorted { a, b in
                    a.element.stream.resolution != b.element.stream.resolution
                        ? a.element.stream.resolution > b.element.stream.resolution
                        : a.offset < b.offset
                }
                .map(\.element)
        }
        return list
    }

    private func play(_ result: FoundStream) async {
        guard let url = result.stream.playableURL else { return }
        playback = PlaybackRequest(url: url, title: target.title, subtitle: target.subtitle,
                                   overview: target.overview, sourceName: result.addonName)
    }
}

/// Quality groups for the stream filters.
enum StreamQuality: Int, CaseIterable, Hashable {
    case uhd = 2160, fhd = 1080, hd = 720, sd = 480, unknown = 0

    init(_ resolution: Int) {
        switch resolution {
        case 1440...: self = .uhd
        case 1080..<1440: self = .fhd
        case 720..<1080: self = .hd
        case 1..<720: self = .sd
        default: self = .unknown
        }
    }

    var label: String {
        switch self {
        case .uhd: return "4K"
        case .fhd: return "1080p"
        case .hd: return "720p"
        case .sd: return "SD"
        case .unknown: return "Other"
        }
    }

    /// The big badge on a stream card.
    var badge: String {
        switch self {
        case .uhd: return "4K"
        case .fhd: return "FHD"
        case .hd: return "HD"
        case .sd: return "SD"
        case .unknown: return "WEB"
        }
    }
}

/// One stream: quality badge, details as tags, the source and the addon.
private struct StreamCard: View {
    let result: FoundStream
    @Environment(\.isFocused) private var isFocused

    /// The addon's text, one entry per line, without decorative emoji.
    private var lines: [String] {
        let text = [result.stream.title, result.stream.description].compactMap { $0 }.first ?? ""
        return text
            .split(whereSeparator: \.isNewline)
            .map { line in
                String(String.UnicodeScalarView(line.unicodeScalars.filter { scalar in
                    !(scalar.properties.isEmojiPresentation || (scalar.properties.isEmoji && scalar.value > 0x2000))
                        && scalar.value != 0xFE0F
                }))
                .trimmingCharacters(in: .whitespaces)
            }
            .filter { !$0.isEmpty }
    }

    /// The first line, split into short tags ("Web Download", "3 GB", "DD+ 5.1").
    private var tags: [String] {
        guard let first = lines.first else { return [] }
        let separators = CharacterSet(charactersIn: "·|•")
        return first
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .prefix(4)
            .map { String($0.prefix(28)) }
    }

    private var source: String {
        if lines.count > 1 { return lines[1] }
        return result.stream.headline
    }

    private var extra: String? {
        lines.count > 2 ? lines.dropFirst(2).joined(separator: " · ") : nil
    }

    var body: some View {
        HStack(spacing: 24) {
            Text(StreamQuality(result.stream.resolution).badge)
                .font(.system(size: 26, weight: .heavy))
                .foregroundStyle(Color.white)
                .frame(width: 104, height: 64)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isFocused ? Theme.ink : Theme.glassStrong))
            VStack(alignment: .leading, spacing: 8) {
                if !tags.isEmpty {
                    HStack(spacing: 10) {
                        ForEach(tags, id: \.self) { tag in
                            Text(tag)
                                .font(.system(size: 18, weight: .semibold))
                                .lineLimit(1)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(isFocused ? Color.black.opacity(0.08) : Theme.glass))
                        }
                    }
                }
                Text(source)
                    .font(.system(size: 24, weight: .bold))
                    .lineLimit(1)
                if let extra {
                    Text(extra)
                        .font(.system(size: 18, weight: .medium))
                        .opacity(0.7)
                        .lineLimit(1)
                }
                Text(result.addonName)
                    .font(.system(size: 18, weight: .medium))
                    .opacity(0.65)
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            Image(systemName: "play.fill")
                .font(.system(size: 30, weight: .bold))
                .opacity(isFocused ? 1 : 0.6)
        }
        .foregroundStyle(isFocused ? Theme.ink : Color.white)
        .padding(.horizontal, 26)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(isFocused ? Color.white : Theme.glass)
        )
        .scaleEffect(isFocused ? 1.02 : 1)
        .shadow(color: .black.opacity(isFocused ? 0.4 : 0), radius: 18, y: 10)
        .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}
