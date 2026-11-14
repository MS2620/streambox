import SwiftUI

/// Search tab. Lives in a `Tab(role: .search)`, which lets tvOS place the
/// keyboard and results correctly and keeps the tab bar reachable.
struct SearchView: View {
    @EnvironmentObject var settings: AppSettings
    @State private var query = ""
    @State private var movies: [TMDBItem] = []
    @State private var series: [TMDBItem] = []
    @State private var channels: [XtreamChannel] = []
    @State private var trending: [TMDBItem] = []
    @State private var searching = false
    @State private var playback: PlaybackRequest?

    private var trimmed: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasResults: Bool {
        !movies.isEmpty || !series.isEmpty || !channels.isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 40) {
                    if trimmed.count < 2 {
                        if !trending.isEmpty {
                            LandscapeRail(title: "Trending", items: trending)
                        }
                    } else if hasResults {
                        if !movies.isEmpty { RailView(title: "Movies", items: movies) }
                        if !series.isEmpty { RailView(title: "Series", items: series) }
                        if !channels.isEmpty { channelRow }
                    } else if searching {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                    } else {
                        Text("No results for “\(trimmed)”")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                    }
                }
                .padding(.vertical, 30)
            }
            .searchable(text: $query, prompt: "Movies, series and channels")
            .navigationDestination(for: TMDBItem.self) { item in
                DetailView(item: item)
            }
            .task(id: settings.tmdbToken) { await loadTrending() }
            .task(id: trimmed) { await search() }
            .fullScreenCover(item: $playback) { request in
                PlayerView(request: request).ignoresSafeArea()
            }
        }
    }

    private var channelRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Live Channels")
                .font(.title3).bold()
                .padding(.horizontal, 90)
            ScrollView(.horizontal) {
                LazyHStack(spacing: 40) {
                    ForEach(Array(channels.enumerated()), id: \.element.id) { index, channel in
                        Button {
                            play(index)
                        } label: {
                            ChannelTile(channel: channel)
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .padding(.horizontal, 90)
                .padding(.vertical, 30)
            }
            .scrollClipDisabled()
        }
    }

    // MARK: - Loading

    private func loadTrending() async {
        guard !settings.tmdbToken.isEmpty else { return }
        trending = (try? await settings.tmdb.trendingAll()) ?? []
    }

    private func search() async {
        let text = trimmed
        // Clearing (or a single letter) empties the old results straight away.
        guard text.count >= 2 else {
            movies = []
            series = []
            channels = []
            searching = false
            return
        }
        searching = true
        // Debounce typing; a newer keystroke cancels this task.
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }

        async let catalogue = searchCatalogue(text)
        async let live = searchChannels(text)
        let (items, foundChannels) = await (catalogue, live)

        // Ignore results for a query the user has already changed.
        guard !Task.isCancelled, text == trimmed else { return }
        movies = items.filter { $0.kind == .movie }
        series = items.filter { $0.kind == .tv }
        channels = foundChannels
        searching = false
    }

    private func searchCatalogue(_ text: String) async -> [TMDBItem] {
        guard !settings.tmdbToken.isEmpty else { return [] }
        return (try? await settings.tmdb.search(text)) ?? []
    }

    private func searchChannels(_ text: String) async -> [XtreamChannel] {
        guard settings.xtream.isConfigured else { return [] }
        let all = (try? await XtreamCache.shared.liveStreams(settings.xtreamClient)) ?? []
        return Array(all.filter { $0.name.localizedCaseInsensitiveContains(text) }.prefix(40))
    }

    private func play(_ index: Int) {
        let client = settings.xtreamClient
        let channel = channels[index]
        guard let url = client.liveURL(for: channel, format: settings.prefs.liveFormat) else { return }
        playback = PlaybackRequest(
            url: url,
            title: channel.name,
            artworkURL: channel.icon.flatMap { URL(string: $0) },
            sourceName: "Search",
            isLive: true,
            httpHeaders: client.requestHeaders,
            live: LiveContext(channels: channels, index: index)
        )
    }
}

/// A channel logo card with its name underneath.
struct ChannelTile: View {
    let channel: XtreamChannel

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.white.opacity(0.1))
                AsyncImage(url: channel.icon.flatMap { URL(string: $0) }) { image in
                    image.resizable().aspectRatio(contentMode: .fit)
                } placeholder: {
                    Image(systemName: "tv").font(.largeTitle)
                }
                .padding(28)
            }
            .frame(width: 300, height: 170)
            Text(channel.name)
                .font(.caption).bold()
                .lineLimit(1)
                .frame(width: 300)
        }
    }
}
