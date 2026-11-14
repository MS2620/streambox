import SwiftUI

enum RailStyle { case poster, landscape }

/// One titled row, fetched lazily when it scrolls into view.
struct CatalogSection: Identifiable {
    let id: String
    var style: RailStyle = .poster
    let fetch: (TMDBClient) async throws -> [TMDBItem]
}

enum Catalog {
    static let homeHero: (TMDBClient) async throws -> [TMDBItem] = { try await $0.trendingAll() }
    static let moviesHero: (TMDBClient) async throws -> [TMDBItem] = { try await $0.trending(.movie) }
    static let seriesHero: (TMDBClient) async throws -> [TMDBItem] = { try await $0.trending(.tv) }

    static let home: [CatalogSection] = [
        CatalogSection(id: "Trending Now", style: .landscape) { try await $0.trendingAll() },
        CatalogSection(id: "Popular Movies") { try await $0.popular(.movie) },
        CatalogSection(id: "Popular Series") { try await $0.popular(.tv) },
        CatalogSection(id: "New in Cinemas", style: .landscape) { try await $0.list("movie/now_playing", type: .movie) },
        CatalogSection(id: "Airing Today") { try await $0.list("tv/airing_today", type: .tv) },
        CatalogSection(id: "Top Rated Movies") { try await $0.list("movie/top_rated", type: .movie) },
    ]

    private static let movieGenres: [(String, Int)] = [
        ("Action", 28), ("Comedy", 35), ("Thriller", 53), ("Horror", 27),
        ("Science Fiction", 878), ("Drama", 18), ("Animation", 16), ("Family", 10751),
        ("Crime", 80), ("Romance", 10749), ("Documentary", 99),
    ]

    private static let seriesGenres: [(String, Int)] = [
        ("Drama", 18), ("Comedy", 35), ("Crime", 80), ("Action & Adventure", 10759),
        ("Sci-Fi & Fantasy", 10765), ("Mystery", 9648), ("Animation", 16),
        ("Documentary", 99), ("Reality", 10764), ("Kids", 10762),
    ]

    static let movies: [CatalogSection] = [
        CatalogSection(id: "Popular") { try await $0.popular(.movie) },
        CatalogSection(id: "Now Playing", style: .landscape) { try await $0.list("movie/now_playing", type: .movie) },
        CatalogSection(id: "Upcoming") { try await $0.list("movie/upcoming", type: .movie) },
        CatalogSection(id: "Top Rated") { try await $0.list("movie/top_rated", type: .movie) },
    ] + movieGenres.map { name, id in
        CatalogSection(id: name) { try await $0.discover(.movie, genre: id) }
    }

    static let series: [CatalogSection] = [
        CatalogSection(id: "Popular") { try await $0.popular(.tv) },
        CatalogSection(id: "Airing Today", style: .landscape) { try await $0.list("tv/airing_today", type: .tv) },
        CatalogSection(id: "On The Air") { try await $0.list("tv/on_the_air", type: .tv) },
        CatalogSection(id: "Top Rated") { try await $0.list("tv/top_rated", type: .tv) },
    ] + seriesGenres.map { name, id in
        CatalogSection(id: name) { try await $0.discover(.tv, genre: id) }
    }
}

/// Used by the Home, Movies and Series tabs: a featured banner, then rows.
struct CatalogView: View {
    @EnvironmentObject var settings: AppSettings
    let hero: (TMDBClient) async throws -> [TMDBItem]
    let sections: [CatalogSection]
    var showsFavouriteChannels = false
    /// Which saved titles to show in My List: nil shows movies and series.
    var myListKind: MediaType? = nil

    @State private var featured: [TMDBItem] = []

    private var reloadKey: String {
        settings.tmdbToken + settings.prefs.tmdbLanguage + settings.prefs.tmdbRegion
    }

    var body: some View {
        NavigationStack {
            Group {
                if settings.tmdbToken.isEmpty {
                    ContentUnavailableView("Add a TMDB token", systemImage: "key",
                                           description: Text("Open Settings → Connections and paste your TMDB API Read Access Token."))
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 46) {
                            if !featured.isEmpty {
                                HeroBanner(items: featured)
                            }
                            MyListRow(kind: myListKind)
                            if showsFavouriteChannels {
                                FavouriteChannelsRow()
                            }
                            ForEach(sections) { section in
                                LazyRail(section: section)
                            }
                        }
                        .padding(.bottom, 60)
                    }
                    .contentMargins(.horizontal, 0, for: .scrollContent)
                    .ignoresSafeArea(edges: [.top, .horizontal])
                }
            }
            .navigationDestination(for: TMDBItem.self) { item in
                DetailView(item: item)
            }
            .task(id: reloadKey) {
                guard !settings.tmdbToken.isEmpty else { return }
                let items = (try? await hero(settings.tmdb)) ?? []
                featured = Array(items.filter { $0.backdropPath != nil }.prefix(6))
            }
        }
    }
}

// MARK: - Featured banner

private struct HeroBanner: View {
    let items: [TMDBItem]
    @State private var index = 0

    private var item: TMDBItem { items[min(index, items.count - 1)] }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: item.backdropURL) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Color.black
            }
            .frame(height: 820)
            .frame(maxWidth: .infinity)
            .clipped()
            .id(item.uid)
            .transition(.opacity)

            LinearGradient(colors: [.clear, .black.opacity(0.35), .black], startPoint: .top, endPoint: .bottom)
            LinearGradient(colors: [.black.opacity(0.75), .clear], startPoint: .leading, endPoint: .center)

            VStack(alignment: .leading, spacing: 18) {
                Text(item.kind == .movie ? "MOVIE" : "SERIES")
                    .font(.caption).bold()
                    .foregroundStyle(.secondary)
                Text(item.displayTitle)
                    .font(.system(size: 66, weight: .bold))
                    .lineLimit(2)
                HStack(spacing: 14) {
                    if let year = item.year { Text(year) }
                    if let rating = item.rating {
                        Label(rating, systemImage: "star.fill")
                            .labelStyle(.titleAndIcon)
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                if let overview = item.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.callout)
                        .lineLimit(3)
                        .frame(maxWidth: 950, alignment: .leading)
                }
                HStack(spacing: 30) {
                    NavigationLink(value: item) {
                        Label("Watch", systemImage: "play.fill")
                            .font(.headline)
                            .padding(.horizontal, 16)
                    }

                    HStack(spacing: 10) {
                        ForEach(items.indices, id: \.self) { i in
                            Capsule()
                                .fill(i == index ? Color.white : Color.white.opacity(0.35))
                                .frame(width: i == index ? 34 : 12, height: 12)
                        }
                    }
                }
                .padding(.top, 10)
            }
            .padding(.horizontal, 90)
            .padding(.bottom, 50)
        }
        .frame(height: 820)
        .frame(maxWidth: .infinity)
        .ignoresSafeArea(edges: .horizontal)
        .animation(.easeInOut(duration: 0.6), value: index)
        .task(id: items.count) {
            // Rotate through the featured titles.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(9))
                guard !Task.isCancelled, items.count > 1 else { continue }
                index = (index + 1) % items.count
            }
        }
    }
}

// MARK: - Rows

/// Saved titles, newest first.
private struct MyListRow: View {
    @EnvironmentObject var settings: AppSettings
    let kind: MediaType?

    private var items: [TMDBItem] {
        settings.prefs.myList.reversed().filter { kind == nil || $0.kind == kind }
    }

    var body: some View {
        if items.isEmpty {
            Color.clear.frame(height: 1)
        } else {
            RailView(title: "My List", items: items)
        }
    }
}

private struct LazyRail: View {
    @EnvironmentObject var settings: AppSettings
    let section: CatalogSection
    @State private var items: [TMDBItem]?
    @State private var failed = false

    private var reloadKey: String {
        settings.tmdbToken + settings.prefs.tmdbLanguage + settings.prefs.tmdbRegion
    }

    var body: some View {
        Group {
            if let items, !items.isEmpty {
                switch section.style {
                case .poster: RailView(title: section.id, items: items)
                case .landscape: LandscapeRail(title: section.id, items: items)
                }
            } else if items == nil {
                VStack(alignment: .leading, spacing: 12) {
                    Text(section.id).font(.title3).bold()
                    ProgressView().frame(height: section.style == .poster ? 330 : 236)
                }
                .padding(.horizontal, 90)
            } else if failed {
                Text("\(section.id): couldn't load")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 90)
            } else {
                Color.clear.frame(height: 1)
            }
        }
        .task(id: reloadKey) {
            do {
                items = try await section.fetch(settings.tmdb)
                failed = false
            } catch {
                items = []
                failed = true
            }
        }
    }
}

/// Wide 16:9 cards with the title underneath, for headline rows.
struct LandscapeRail: View {
    let title: String
    let items: [TMDBItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3).bold()
                .padding(.horizontal, 90)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 44) {
                    ForEach(items, id: \.uid) { item in
                        NavigationLink(value: item) {
                            BackdropCard(item: item)
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
}

struct BackdropCard: View {
    let item: TMDBItem

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            AsyncImage(url: item.backdropURL) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                ZStack {
                    Color.gray.opacity(0.3)
                    Text(item.displayTitle).font(.caption).padding()
                }
            }
            .frame(width: 440, height: 248)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            Text(item.displayTitle)
                .font(.callout).bold()
                .lineLimit(1)
                .frame(width: 440, alignment: .leading)
        }
    }
}

// MARK: - Favourite channels (Home)

private struct FavouriteChannelsRow: View {
    @EnvironmentObject var settings: AppSettings
    @State private var channels: [XtreamChannel] = []
    @State private var playback: PlaybackRequest?

    var body: some View {
        Group {
            if !channels.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Favourite Channels")
                        .font(.title3).bold()
                        .padding(.horizontal, 90)
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 40) {
                            ForEach(Array(channels.enumerated()), id: \.element.id) { index, channel in
                                Button {
                                    play(index)
                                } label: {
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
                                .buttonStyle(.borderless)
                            }
                        }
                        .padding(.horizontal, 90)
                        .padding(.vertical, 30)
                    }
                    .scrollClipDisabled()
                }
            } else {
                Color.clear.frame(height: 1)
            }
        }
        .task(id: settings.prefs.favouriteChannelIDs) { await load() }
        .fullScreenCover(item: $playback) { request in
            PlayerView(request: request).ignoresSafeArea()
        }
    }

    private func load() async {
        let favourites = settings.prefs.favouriteChannelIDs
        guard settings.xtream.isConfigured, !favourites.isEmpty else {
            channels = []
            return
        }
        let all = (try? await settings.xtreamClient.liveStreams(categoryID: nil)) ?? []
        channels = all.filter { favourites.contains($0.id) }
    }

    private func play(_ index: Int) {
        let client = settings.xtreamClient
        let channel = channels[index]
        guard let url = client.liveURL(for: channel, format: settings.prefs.liveFormat) else { return }
        playback = PlaybackRequest(
            url: url,
            title: channel.name,
            artworkURL: channel.icon.flatMap { URL(string: $0) },
            sourceName: "Favourites",
            isLive: true,
            httpHeaders: client.requestHeaders,
            live: LiveContext(channels: channels, index: index)
        )
    }
}

struct RailView: View {
    let title: String
    let items: [TMDBItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3).bold()
                .padding(.horizontal, 90)
            ScrollView(.horizontal) {
                LazyHStack(spacing: 40) {
                    ForEach(items, id: \.uid) { item in
                        NavigationLink(value: item) {
                            PosterCard(item: item)
                        }
                        .buttonStyle(.card)
                    }
                }
                .padding(.horizontal, 90)
                .padding(.vertical, 30)
            }
            .scrollClipDisabled()
        }
    }
}

struct PosterCard: View {
    let item: TMDBItem

    var body: some View {
        AsyncImage(url: item.posterURL) { image in
            image.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
            ZStack {
                Color.gray.opacity(0.3)
                Text(item.displayTitle)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .padding()
            }
        }
        .frame(width: 220, height: 330)
        .clipped()
    }
}

struct SearchView: View {
    @EnvironmentObject var settings: AppSettings
    @State private var query = ""
    @State private var results: [TMDBItem] = []

    private let columns = Array(repeating: GridItem(.fixed(220), spacing: 40), count: 6)

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 50) {
                    ForEach(results, id: \.uid) { item in
                        NavigationLink(value: item) {
                            PosterCard(item: item)
                        }
                        .buttonStyle(.card)
                    }
                }
                .padding(60)
            }
            .searchable(text: $query)
            .task(id: query) {
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled, query.count >= 2, !settings.tmdbToken.isEmpty else { return }
                results = (try? await settings.tmdb.search(query)) ?? []
            }
            .navigationDestination(for: TMDBItem.self) { item in
                DetailView(item: item)
            }
        }
    }
}
