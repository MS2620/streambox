import SwiftUI

struct StreamTarget: Identifiable {
    let type: String   // "movie" or "series"
    let id: String     // Stremio id, e.g. "tt0903747:1:1"
    let title: String
}

struct DetailView: View {
    @EnvironmentObject var settings: AppSettings
    let item: TMDBItem

    @State private var imdbID: String?
    @State private var seasons: [TVSeasonSummary] = []
    @State private var selectedSeason = 1
    @State private var episodes: [TVEpisode] = []
    @State private var streamTarget: StreamTarget?
    @State private var error: String?

    private var tmdb: TMDBClient { TMDBClient(token: settings.tmdbToken) }

    var body: some View {
        ZStack {
            AsyncImage(url: item.backdropURL) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Color.black
            }
            .ignoresSafeArea()
            .overlay(
                LinearGradient(colors: [.black.opacity(0.2), .black.opacity(0.95)],
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Spacer(minLength: 280)
                    Text(item.displayTitle).font(.largeTitle).bold()
                    if let year = item.year {
                        Text(year).foregroundStyle(.secondary)
                    }
                    Text(item.overview ?? "")
                        .lineLimit(5)
                        .frame(maxWidth: 1100, alignment: .leading)
                    if let error {
                        Text(error).foregroundStyle(.red)
                    }
                    if item.kind == .movie {
                        Button {
                            if let imdbID {
                                streamTarget = StreamTarget(type: "movie", id: imdbID, title: item.displayTitle)
                            }
                        } label: {
                            Label("Find Streams", systemImage: "play.fill")
                        }
                        .disabled(imdbID == nil)
                    } else {
                        seasonsSection
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(80)
            }
        }
        .task { await load() }
        .sheet(item: $streamTarget) { target in
            StreamListView(target: target)
        }
    }

    private var seasonsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            ScrollView(.horizontal) {
                HStack(spacing: 20) {
                    ForEach(seasons) { season in
                        Button(season.name ?? "Season \(season.seasonNumber)") {
                            selectedSeason = season.seasonNumber
                        }
                        .tint(season.seasonNumber == selectedSeason ? Color.accentColor : nil)
                    }
                }
                .padding(20)
            }
            .scrollClipDisabled()

            ForEach(episodes) { episode in
                Button {
                    if let imdbID {
                        streamTarget = StreamTarget(
                            type: "series",
                            id: "\(imdbID):\(episode.seasonNumber):\(episode.episodeNumber)",
                            title: "\(item.displayTitle) S\(episode.seasonNumber)E\(episode.episodeNumber)"
                        )
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(episode.episodeNumber). \(episode.name ?? "Episode")").font(.headline)
                        if let overview = episode.overview, !overview.isEmpty {
                            Text(overview).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .disabled(imdbID == nil)
            }
        }
        .task(id: selectedSeason) { await loadEpisodes() }
    }

    private func load() async {
        do {
            imdbID = try await tmdb.imdbID(for: item)
            if imdbID == nil { error = "No IMDb id for this title, so addons can't look it up." }
            if item.kind == .tv {
                seasons = try await tmdb.seasons(tvID: item.id)
                if let first = seasons.first, !seasons.contains(where: { $0.seasonNumber == selectedSeason }) {
                    selectedSeason = first.seasonNumber
                }
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func loadEpisodes() async {
        guard item.kind == .tv else { return }
        episodes = (try? await tmdb.episodes(tvID: item.id, season: selectedSeason)) ?? []
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

        results = found
        loading = false
        if !failures.isEmpty { status = "Failed to reach: " + failures.joined(separator: ", ") }
    }

    private func play(_ result: FoundStream) async {
        status = "Resolving…"
        do {
            let url = try await StreamResolver(realDebridKey: settings.realDebridKey).resolve(result.stream)
            status = nil
            playback = PlaybackRequest(url: url, title: target.title)
        } catch {
            status = error.localizedDescription
        }
    }
}
