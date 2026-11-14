import SwiftUI

struct StreamTarget: Identifiable {
    let type: String   // "movie" or "series"
    let id: String     // Stremio id, e.g. "tt0903747:1:1"
    let title: String
    var subtitle: String? = nil
    var overview: String? = nil
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
        .sheet(item: $streamTarget) { target in
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
                                                subtitle: item.year, overview: item.overview)
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
            overview: episode.overview
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

    var body: some View {
        NavigationStack {
            List {
                if loading {
                    ProgressView("Searching \(settings.addons.count) addon(s)…")
                } else if results.isEmpty {
                    Text(settings.addons.isEmpty
                         ? "No addons configured. Add a Stremio addon manifest URL in Settings."
                         : "No streams found.")
                }
                if let status {
                    Text(status).foregroundStyle(.secondary)
                }
                ForEach(results) { result in
                    Button {
                        Task { await play(result) }
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(result.stream.headline).font(.headline)
                            Text(result.stream.detail)
                                .font(.caption).foregroundStyle(.secondary).lineLimit(3)
                            Text(result.addonName).font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            .navigationTitle(target.title)
        }
        .task { await search() }
        .fullScreenCover(item: $playback) { request in
            PlayerView(request: request).ignoresSafeArea()
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

        results = arrange(found)
        loading = false
        if !failures.isEmpty { status = "Failed to reach: " + failures.joined(separator: ", ") }

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
        status = "Resolving…"
        do {
            let url = try await StreamResolver(realDebridKey: settings.realDebridKey).resolve(result.stream)
            status = nil
            playback = PlaybackRequest(url: url, title: target.title, subtitle: target.subtitle,
                                       overview: target.overview, sourceName: result.addonName)
        } catch {
            status = error.localizedDescription
        }
    }
}
