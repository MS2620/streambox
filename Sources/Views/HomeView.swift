import SwiftUI

/// One titled row of posters, fetched lazily when it scrolls into view.
struct CatalogSection: Identifiable {
    let id: String
    let fetch: (TMDBClient) async throws -> [TMDBItem]
}

enum Catalog {
    static let home: [CatalogSection] = [
        CatalogSection(id: "Trending Movies") { try await $0.trending(.movie) },
        CatalogSection(id: "Trending Series") { try await $0.trending(.tv) },
        CatalogSection(id: "Popular Movies") { try await $0.popular(.movie) },
        CatalogSection(id: "Popular Series") { try await $0.popular(.tv) },
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
        CatalogSection(id: "Trending") { try await $0.trending(.movie) },
        CatalogSection(id: "Popular") { try await $0.popular(.movie) },
        CatalogSection(id: "Now Playing") { try await $0.list("movie/now_playing", type: .movie) },
        CatalogSection(id: "Upcoming") { try await $0.list("movie/upcoming", type: .movie) },
        CatalogSection(id: "Top Rated") { try await $0.list("movie/top_rated", type: .movie) },
    ] + movieGenres.map { name, id in
        CatalogSection(id: name) { try await $0.discover(.movie, genre: id) }
    }

    static let series: [CatalogSection] = [
        CatalogSection(id: "Trending") { try await $0.trending(.tv) },
        CatalogSection(id: "Popular") { try await $0.popular(.tv) },
        CatalogSection(id: "Airing Today") { try await $0.list("tv/airing_today", type: .tv) },
        CatalogSection(id: "On The Air") { try await $0.list("tv/on_the_air", type: .tv) },
        CatalogSection(id: "Top Rated") { try await $0.list("tv/top_rated", type: .tv) },
    ] + seriesGenres.map { name, id in
        CatalogSection(id: name) { try await $0.discover(.tv, genre: id) }
    }
}

/// Used by the Home, Movies and Series tabs.
struct CatalogView: View {
    @EnvironmentObject var settings: AppSettings
    let sections: [CatalogSection]

    var body: some View {
        NavigationStack {
            Group {
                if settings.tmdbToken.isEmpty {
                    ContentUnavailableView("Add a TMDB token", systemImage: "key",
                                           description: Text("Open Settings → Accounts and paste your TMDB API Read Access Token."))
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 40) {
                            ForEach(sections) { section in
                                LazyRail(section: section)
                            }
                        }
                        .padding(.vertical, 40)
                    }
                }
            }
            .navigationDestination(for: TMDBItem.self) { item in
                DetailView(item: item)
            }
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
                RailView(title: section.id, items: items)
            } else if items == nil {
                VStack(alignment: .leading, spacing: 12) {
                    Text(section.id).font(.title3).bold()
                    ProgressView().frame(height: 330)
                }
                .padding(.horizontal, 80)
            } else if failed {
                Text("\(section.id): couldn't load")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 80)
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

struct RailView: View {
    let title: String
    let items: [TMDBItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3).bold()
                .padding(.horizontal, 80)
            ScrollView(.horizontal) {
                LazyHStack(spacing: 40) {
                    ForEach(items, id: \.uid) { item in
                        NavigationLink(value: item) {
                            PosterCard(item: item)
                        }
                        .buttonStyle(.card)
                    }
                }
                .padding(.horizontal, 80)
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
