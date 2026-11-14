import SwiftUI

enum RailStyle { case poster, landscape, ranked }

/// One titled row, fetched lazily when it scrolls into view.
struct CatalogSection: Identifiable {
    let id: String
    var style: RailStyle = .poster
    let fetch: (TMDBClient) async throws -> [TMDBItem]
}

enum Catalog {
    /// The TMDB-backed Home rows (My List, channels and teams are built separately).
    static func homeSection(_ row: HomeRow) -> CatalogSection? {
        switch row {
        case .trending:
            return CatalogSection(id: row.title, style: .landscape) { try await $0.trendingAll() }
        case .popularMovies:
            return CatalogSection(id: row.title) { try await $0.popular(.movie) }
        case .popularSeries:
            return CatalogSection(id: row.title) { try await $0.popular(.tv) }
        case .cinemas:
            return CatalogSection(id: row.title, style: .landscape) { try await $0.list("movie/now_playing", type: .movie) }
        case .airingToday:
            return CatalogSection(id: row.title) { try await $0.list("tv/airing_today", type: .tv) }
        case .topRated:
            return CatalogSection(id: row.title) { try await $0.list("movie/top_rated", type: .movie) }
        case .myList, .channels, .teams:
            return nil
        }
    }

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

    static let trendingMovies = CatalogSection(id: "Trending Movies", style: .ranked) { try await $0.trending(.movie) }
    static let trendingSeries = CatalogSection(id: "Trending Series", style: .ranked) { try await $0.trending(.tv) }

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

// MARK: - Hero

/// What the big banner at the top shows: always the card that has focus.
struct HeroContent: Equatable {
    var key: String
    var kicker: String
    var title: String
    var chips: [String] = []
    var overview: String = ""
    var imageURL: URL? = nil
}

extension HeroContent {
    init(item: TMDBItem, row: String) {
        var chips: [String] = []
        if let year = item.year { chips.append(year) }
        chips += item.genreNames
        if let rating = item.rating { chips.append("★ \(rating)") }
        self.init(key: "\(row)|\(item.uid)",
                  kicker: (item.kind == .movie ? "MOVIE" : "SERIES") + " · " + row.uppercased(),
                  title: item.displayTitle,
                  chips: chips,
                  overview: item.overview ?? "",
                  imageURL: item.backdropURL)
    }
}

/// Used by the Home, Movies and Series tabs. The banner follows focus: moving
/// along a row swaps its artwork, title and details to the focused card.
struct CatalogView: View {
    enum Mode { case home, movies, series }

    @EnvironmentObject var settings: AppSettings
    let mode: Mode

    @State private var hero: HeroContent?
    @State private var pending: HeroContent?

    /// Height of the banner's text area; the rows scroll underneath it.
    private static let heroHeight: CGFloat = 590

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Theme.base.ignoresSafeArea()

                if settings.tmdbToken.isEmpty {
                    ContentUnavailableView("Add a TMDB token", systemImage: "key",
                                           description: Text("Open Settings → Connections and paste your TMDB API Read Access Token."))
                } else {
                    HeroBackdrop(hero: hero)

                    VStack(alignment: .leading, spacing: 0) {
                        HeroInfo(hero: hero)
                            .frame(height: Self.heroHeight)

                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 30) {
                                rows
                            }
                            .padding(.top, 4)
                            .padding(.bottom, 90)
                        }
                        .contentMargins(.horizontal, 0, for: .scrollContent)
                        .ignoresSafeArea()
                    }
                    .ignoresSafeArea()
                }
            }
            .navigationDestination(for: TMDBItem.self) { item in
                DetailView(item: item)
            }
            .navigationDestination(for: XtreamSeries.self) { series in
                ProviderSeriesView(series: series)
            }
            .task(id: pending?.key) {
                guard let next = pending else { return }
                // Wait a moment so skimming along a row doesn't flash every backdrop.
                if hero != nil {
                    try? await Task.sleep(for: .milliseconds(180))
                }
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.3)) { hero = next }
            }
        }
    }

    @ViewBuilder
    private var rows: some View {
        switch mode {
        case .home:
            ForEach(settings.visibleHomeRows) { row in
                homeRow(row)
            }
        case .movies:
            LazyRail(section: Catalog.trendingMovies, onFocus: focus, onLoaded: loaded)
            MyListRow(kind: .movie, onFocus: focus)
            if settings.prefs.showProviderMovies {
                ProviderMoviesRow(onFocus: focus)
            }
            ForEach(Catalog.movies) { section in
                LazyRail(section: section, onFocus: focus, onLoaded: loaded)
            }
        case .series:
            MyListRow(kind: .tv, onFocus: focus)
            LazyRail(section: Catalog.trendingSeries, onFocus: focus, onLoaded: loaded)
            if settings.prefs.showProviderSeries {
                ProviderSeriesRow(onFocus: focus)
            }
            ForEach(Catalog.series) { section in
                LazyRail(section: section, onFocus: focus, onLoaded: loaded)
            }
        }
    }

    @ViewBuilder
    private func homeRow(_ row: HomeRow) -> some View {
        switch row {
        case .myList:
            MyListRow(kind: nil, onFocus: focus)
        case .channels:
            FavouriteChannelsRow(onFocus: focus)
        case .teams:
            UpcomingFixturesRow(onFocus: focus)
        default:
            if let section = Catalog.homeSection(row) {
                LazyRail(section: section, onFocus: focus, onLoaded: loaded)
            }
        }
    }

    private func focus(_ content: HeroContent) {
        pending = content
    }

    /// The first row to load fills the banner until something is focused.
    private func loaded(_ content: HeroContent) {
        if hero == nil && pending == nil { pending = content }
    }
}

private struct HeroBackdrop: View {
    let hero: HeroContent?

    private static let height: CGFloat = 860

    var body: some View {
        ZStack(alignment: .top) {
            if let url = hero?.imageURL {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Color.clear
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: Self.height)
                .clipped()
                .id(url)
                .transition(.opacity)
            }

            // Fades the artwork into the page background at the bottom…
            LinearGradient(
                stops: [
                    .init(color: Theme.base.opacity(0), location: 0.3),
                    .init(color: Theme.base.opacity(0.78), location: 0.7),
                    .init(color: Theme.base, location: 1),
                ],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: Self.height)

            // …and darkens the left so the text stays readable.
            LinearGradient(colors: [Theme.base.opacity(0.85), Theme.base.opacity(0)],
                           startPoint: .leading, endPoint: .center)
                .frame(height: Self.height)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
    }
}

private struct HeroInfo: View {
    let hero: HeroContent?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let hero {
                Text(hero.kicker)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)
                Text(hero.title)
                    .font(.system(size: 84, weight: .black))
                    .lineLimit(2)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: 1300, alignment: .leading)
                if !hero.chips.isEmpty {
                    HStack(spacing: 10) {
                        ForEach(Array(hero.chips.enumerated()), id: \.offset) { _, chip in
                            Chip(text: chip)
                        }
                    }
                }
                if !hero.overview.isEmpty {
                    Text(hero.overview)
                        .font(.system(size: 26, weight: .medium))
                        .lineLimit(3)
                        .frame(maxWidth: 900, alignment: .leading)
                }
            }
        }
        .padding(.leading, 90)
        .padding(.top, 150)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .id(hero?.key)
        .transition(.opacity)
    }
}

// MARK: - Rows

/// Saved titles, newest first.
private struct MyListRow: View {
    @EnvironmentObject var settings: AppSettings
    let kind: MediaType?
    let onFocus: (HeroContent) -> Void

    private var items: [TMDBItem] {
        settings.prefs.myList.reversed().filter { kind == nil || $0.kind == kind }
    }

    var body: some View {
        if items.isEmpty {
            Color.clear.frame(height: 1)
        } else {
            RailView(title: "My List", items: items, onFocus: { item in
                onFocus(HeroContent(item: item, row: "My List"))
            })
        }
    }
}

private struct LazyRail: View {
    @EnvironmentObject var settings: AppSettings
    let section: CatalogSection
    let onFocus: (HeroContent) -> Void
    var onLoaded: ((HeroContent) -> Void)? = nil

    @State private var items: [TMDBItem]?

    private var reloadKey: String {
        settings.tmdbToken + settings.prefs.tmdbLanguage + settings.prefs.tmdbRegion
    }

    var body: some View {
        Group {
            if let items, !items.isEmpty {
                RailView(title: section.id, items: items, style: section.style, onFocus: { item in
                    onFocus(HeroContent(item: item, row: section.id))
                })
            } else if items == nil {
                VStack(alignment: .leading, spacing: 12) {
                    Text(section.id).font(.title3).bold()
                    ProgressView().frame(height: section.style == .landscape ? 248 : 330)
                }
                .padding(.horizontal, 90)
            } else {
                Color.clear.frame(height: 1)
            }
        }
        .task(id: reloadKey) {
            do {
                let loaded = try await section.fetch(settings.tmdb)
                items = loaded
                if let first = loaded.first {
                    onLoaded?(HeroContent(item: first, row: section.id))
                }
            } catch {
                items = []
            }
        }
    }
}

/// A horizontal row of titles. Reports the focused title through `onFocus`.
struct RailView: View {
    let title: String
    let items: [TMDBItem]
    let style: RailStyle
    /// Left and right padding; smaller where the row sits inside a narrower pane.
    let inset: CGFloat
    let onFocus: ((TMDBItem) -> Void)?

    @FocusState private var focusedID: String?

    init(title: String, items: [TMDBItem], style: RailStyle = .poster, inset: CGFloat = 90,
         onFocus: ((TMDBItem) -> Void)? = nil) {
        self.title = title
        self.items = items
        self.style = style
        self.inset = inset
        self.onFocus = onFocus
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3).bold()
                .padding(.horizontal, inset)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 40) {
                    ForEach(Array(items.enumerated()), id: \.element.uid) { index, item in
                        NavigationLink(value: item) {
                            switch style {
                            case .poster:
                                PosterTile(item: item)
                            case .landscape:
                                BackdropCard(item: item)
                            case .ranked:
                                HStack(alignment: .bottom, spacing: 0) {
                                    Text("\(index + 1)")
                                        .font(.system(size: 150, weight: .black))
                                        .foregroundStyle(.white.opacity(0.35))
                                        .padding(.bottom, 24)
                                    PosterTile(item: item)
                                }
                            }
                        }
                        .buttonStyle(PlainPressStyle())
                        .focused($focusedID, equals: item.uid)
                    }
                }
                .padding(.horizontal, inset)
                .padding(.vertical, 30)
            }
            .scrollClipDisabled()
        }
        .onChange(of: focusedID) { _, id in
            guard let id, let item = items.first(where: { $0.uid == id }) else { return }
            onFocus?(item)
        }
    }
}

/// Poster artwork only.
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

/// A poster with its title underneath; outlined while focused.
struct PosterTile: View {
    let item: TMDBItem

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            FocusFrame {
                PosterCard(item: item)
            }
            Text(item.displayTitle)
                .font(.system(size: 22, weight: .semibold))
                .lineLimit(1)
                .frame(width: 220, alignment: .leading)
        }
    }
}

/// A wide 16:9 card with the title underneath, for headline rows.
struct BackdropCard: View {
    let item: TMDBItem

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            FocusFrame(cornerRadius: 20) {
                AsyncImage(url: item.backdropURL) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    ZStack {
                        Color.gray.opacity(0.3)
                        Text(item.displayTitle).font(.caption).padding()
                    }
                }
                .frame(width: 440, height: 248)
                .clipped()
            }
            Text(item.displayTitle)
                .font(.system(size: 24, weight: .semibold))
                .lineLimit(1)
                .frame(width: 440, alignment: .leading)
        }
    }
}

/// Any poster-shaped artwork with a title (provider films and series).
struct ArtTile: View {
    let imageURL: URL?
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            FocusFrame {
                AsyncImage(url: imageURL) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    ZStack {
                        Color.gray.opacity(0.3)
                        Text(title).font(.caption).multilineTextAlignment(.center).padding()
                    }
                }
                .frame(width: 220, height: 330)
                .clipped()
            }
            Text(title)
                .font(.system(size: 22, weight: .semibold))
                .lineLimit(1)
                .frame(width: 220, alignment: .leading)
        }
    }
}

/// A channel logo card with its name underneath.
struct ChannelTile: View {
    let channel: XtreamChannel

    var body: some View {
        VStack(spacing: 12) {
            FocusFrame {
                ZStack {
                    Rectangle().fill(Theme.glass)
                    AsyncImage(url: channel.icon.flatMap { URL(string: $0) }) { image in
                        image.resizable().aspectRatio(contentMode: .fit)
                    } placeholder: {
                        Image(systemName: "tv").font(.largeTitle)
                    }
                    .padding(28)
                }
                .frame(width: 300, height: 170)
            }
            Text(channel.name)
                .font(.system(size: 20, weight: .bold))
                .lineLimit(1)
                .frame(width: 300)
        }
    }
}

// MARK: - Favourite channels (Home)

private struct FavouriteChannelsRow: View {
    @EnvironmentObject var settings: AppSettings
    let onFocus: (HeroContent) -> Void

    @State private var channels: [XtreamChannel] = []
    @State private var playback: PlaybackRequest?
    @FocusState private var focusedID: Int?

    var body: some View {
        Group {
            if !channels.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Favourite Channels")
                        .font(.title3).bold()
                        .padding(.horizontal, 90)
                    ScrollView(.horizontal) {
                        LazyHStack(alignment: .top, spacing: 40) {
                            ForEach(Array(channels.enumerated()), id: \.element.id) { index, channel in
                                Button {
                                    play(index)
                                } label: {
                                    ChannelTile(channel: channel)
                                }
                                .buttonStyle(PlainPressStyle())
                                .focused($focusedID, equals: channel.id)
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
        .onChange(of: focusedID) { _, id in
            guard let id, let channel = channels.first(where: { $0.id == id }) else { return }
            onFocus(HeroContent(key: "channel-\(id)", kicker: "LIVE TV · FAVOURITE CHANNEL", title: channel.name))
        }
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
        let all = (try? await XtreamCache.shared.liveStreams(settings.xtreamClient)) ?? []
        channels = all.filter { favourites.contains($0.id) && settings.isVisible($0) }
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

// MARK: - My teams' next fixtures (Home)

private struct UpcomingFixturesRow: View {
    @EnvironmentObject var settings: AppSettings
    let onFocus: (HeroContent) -> Void

    @State private var fixtures: [Fixture] = []
    @State private var selected: Fixture?
    @FocusState private var focusedID: String?

    private var loadKey: String {
        settings.prefs.favouriteTeams.map(\.id).joined(separator: ",") + "|\(settings.prefs.sportsDaysAhead)"
    }

    var body: some View {
        Group {
            if !fixtures.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("My Teams")
                        .font(.title3).bold()
                        .padding(.horizontal, 90)
                    ScrollView(.horizontal) {
                        LazyHStack(alignment: .top, spacing: 40) {
                            ForEach(fixtures) { fixture in
                                Button {
                                    selected = fixture
                                } label: {
                                    FixtureTile(fixture: fixture, width: 440)
                                }
                                .buttonStyle(PlainPressStyle())
                                .focused($focusedID, equals: fixture.id)
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
        .task(id: loadKey) {
            let teams = settings.prefs.favouriteTeams
            let all = await SportsLoader.upcoming(teams: teams, days: settings.prefs.sportsDaysAhead)
            fixtures = Array(all.prefix(12))
        }
        .onChange(of: focusedID) { _, id in
            guard let id, let fixture = fixtures.first(where: { $0.id == id }) else { return }
            onFocus(HeroContent(key: "fixture-\(id)",
                                kicker: fixture.competition.uppercased(),
                                title: fixture.title,
                                chips: [DayFormat.label(fixture.guideTime), DayFormat.time(fixture.guideTime)],
                                overview: fixture.subtitle ?? ""))
        }
        .sheet(item: $selected) { fixture in
            FixtureDetailView(fixture: fixture)
        }
    }
}

// MARK: - Provider library rows

/// Recently added films from the IPTV provider's own library.
private struct ProviderMoviesRow: View {
    @EnvironmentObject var settings: AppSettings
    let onFocus: (HeroContent) -> Void

    @State private var movies: [XtreamVOD] = []
    @State private var playback: PlaybackRequest?
    @FocusState private var focusedID: Int?

    var body: some View {
        Group {
            if !movies.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("From Your Provider · Recently Added")
                        .font(.title3).bold()
                        .padding(.horizontal, 90)
                    ScrollView(.horizontal) {
                        LazyHStack(alignment: .top, spacing: 40) {
                            ForEach(movies) { movie in
                                Button {
                                    play(movie)
                                } label: {
                                    ArtTile(imageURL: movie.icon.flatMap { URL(string: $0) }, title: movie.name)
                                }
                                .buttonStyle(PlainPressStyle())
                                .focused($focusedID, equals: movie.id)
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
        .task(id: settings.xtream) {
            guard settings.xtream.isConfigured else { return }
            movies = (try? await XtreamCache.shared.recentMovies(settings.xtreamClient)) ?? []
        }
        .onChange(of: focusedID) { _, id in
            guard let id, let movie = movies.first(where: { $0.id == id }) else { return }
            onFocus(HeroContent(key: "vod-\(id)", kicker: "MOVIE · FROM YOUR PROVIDER", title: movie.name))
        }
        .fullScreenCover(item: $playback) { request in
            PlayerView(request: request).ignoresSafeArea()
        }
    }

    private func play(_ movie: XtreamVOD) {
        let client = settings.xtreamClient
        guard let url = client.movieURL(for: movie) else { return }
        playback = PlaybackRequest(url: url, title: movie.name, sourceName: "Provider",
                                   httpHeaders: client.requestHeaders)
    }
}

/// Recently updated series from the IPTV provider's own library.
private struct ProviderSeriesRow: View {
    @EnvironmentObject var settings: AppSettings
    let onFocus: (HeroContent) -> Void

    @State private var series: [XtreamSeries] = []
    @FocusState private var focusedID: Int?

    var body: some View {
        Group {
            if !series.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("From Your Provider · Recently Updated")
                        .font(.title3).bold()
                        .padding(.horizontal, 90)
                    ScrollView(.horizontal) {
                        LazyHStack(alignment: .top, spacing: 40) {
                            ForEach(series) { show in
                                NavigationLink(value: show) {
                                    ArtTile(imageURL: show.cover.flatMap { URL(string: $0) }, title: show.name)
                                }
                                .buttonStyle(PlainPressStyle())
                                .focused($focusedID, equals: show.id)
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
        .task(id: settings.xtream) {
            guard settings.xtream.isConfigured else { return }
            series = (try? await XtreamCache.shared.recentSeries(settings.xtreamClient)) ?? []
        }
        .onChange(of: focusedID) { _, id in
            guard let id, let show = series.first(where: { $0.id == id }) else { return }
            onFocus(HeroContent(key: "pseries-\(id)", kicker: "SERIES · FROM YOUR PROVIDER",
                                title: show.name, overview: show.plot ?? ""))
        }
    }
}

/// Seasons and episodes of a series from the provider's library.
struct ProviderSeriesView: View {
    @EnvironmentObject var settings: AppSettings
    let series: XtreamSeries

    @State private var episodes: [XtreamEpisode] = []
    @State private var loading = true
    @State private var season: Int?
    @State private var playback: PlaybackRequest?

    private var seasons: [Int] {
        Array(Set(episodes.map(\.season))).sorted()
    }

    private var shown: [XtreamEpisode] {
        episodes.filter { $0.season == season }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                HStack(alignment: .top, spacing: 40) {
                    AsyncImage(url: series.cover.flatMap { URL(string: $0) }) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Color.gray.opacity(0.3)
                    }
                    .frame(width: 220, height: 330)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                    VStack(alignment: .leading, spacing: 16) {
                        Text("SERIES · FROM YOUR PROVIDER")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.white.opacity(0.62))
                        Text(series.name)
                            .font(.system(size: 60, weight: .black))
                            .lineLimit(2)
                        if let plot = series.plot, !plot.isEmpty {
                            Text(plot)
                                .font(.system(size: 24, weight: .medium))
                                .lineLimit(5)
                                .frame(maxWidth: 1100, alignment: .leading)
                        }
                    }
                }

                if loading {
                    ProgressView().frame(maxWidth: .infinity)
                } else if episodes.isEmpty {
                    Text("No episodes found for this series.")
                        .foregroundStyle(.white.opacity(0.62))
                } else {
                    ScrollView(.horizontal) {
                        HStack(spacing: 16) {
                            ForEach(seasons, id: \.self) { number in
                                Button {
                                    season = number
                                } label: {
                                    PillLabel(title: "Season \(number)", selected: number == season)
                                }
                                .buttonStyle(PlainPressStyle())
                            }
                        }
                        .padding(.vertical, 10)
                    }
                    .scrollClipDisabled()

                    GlassPanel("Episodes") {
                        ForEach(shown) { episode in
                            Button {
                                play(episode)
                            } label: {
                                ListRowLabel(title: "E\(episode.number) · \(episode.title)",
                                             subtitle: episode.plot,
                                             trailingIcon: "play.fill")
                            }
                            .buttonStyle(PlainPressStyle())
                        }
                    }
                }
            }
            .padding(.horizontal, 90)
            .padding(.vertical, 60)
        }
        .background(AppBackground())
        .task {
            episodes = (try? await settings.xtreamClient.seriesEpisodes(seriesID: series.id)) ?? []
            season = seasons.first
            loading = false
        }
        .fullScreenCover(item: $playback) { request in
            PlayerView(request: request).ignoresSafeArea()
        }
    }

    private func play(_ episode: XtreamEpisode) {
        let client = settings.xtreamClient
        guard let url = client.episodeURL(for: episode) else { return }
        playback = PlaybackRequest(
            url: url,
            title: series.name,
            subtitle: "S\(episode.season)E\(episode.number) · \(episode.title)",
            overview: episode.plot,
            sourceName: "Provider",
            httpHeaders: client.requestHeaders
        )
    }
}
