import SwiftUI

struct HomeView: View {
    @EnvironmentObject var settings: AppSettings
    @State private var rails: [Rail] = []
    @State private var error: String?

    struct Rail: Identifiable {
        let id: String
        let items: [TMDBItem]
    }

    var body: some View {
        NavigationStack {
            Group {
                if settings.tmdbToken.isEmpty {
                    ContentUnavailableView("Add a TMDB token", systemImage: "key",
                                           description: Text("Open Settings and paste your TMDB API Read Access Token."))
                } else if let error {
                    ContentUnavailableView("Couldn't load", systemImage: "exclamationmark.triangle",
                                           description: Text(error))
                } else if rails.isEmpty {
                    ProgressView()
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 40) {
                            ForEach(rails) { rail in
                                RailView(title: rail.id, items: rail.items)
                            }
                        }
                        .padding(.vertical, 40)
                    }
                }
            }
            .navigationDestination(for: TMDBItem.self) { item in
                DetailView(item: item)
            }
            .task(id: settings.tmdbToken) { await load() }
        }
    }

    private func load() async {
        guard !settings.tmdbToken.isEmpty else { return }
        let client = TMDBClient(token: settings.tmdbToken)
        do {
            async let trendingMovies = client.trending(.movie)
            async let trendingShows = client.trending(.tv)
            async let popularMovies = client.popular(.movie)
            async let popularShows = client.popular(.tv)
            rails = [
                Rail(id: "Trending Movies", items: try await trendingMovies),
                Rail(id: "Trending Shows", items: try await trendingShows),
                Rail(id: "Popular Movies", items: try await popularMovies),
                Rail(id: "Popular Shows", items: try await popularShows),
            ]
            error = nil
        } catch {
            self.error = error.localizedDescription
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
                results = (try? await TMDBClient(token: settings.tmdbToken).search(query)) ?? []
            }
            .navigationDestination(for: TMDBItem.self) { item in
                DetailView(item: item)
            }
        }
    }
}
