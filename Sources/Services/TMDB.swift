import Foundation

enum MediaType: String, Codable, Hashable {
    case movie, tv
}

struct TMDBItem: Decodable, Hashable {
    let id: Int
    let title: String?
    let name: String?
    let overview: String?
    let posterPath: String?
    let backdropPath: String?
    let releaseDate: String?
    let firstAirDate: String?
    var mediaType: String?

    var kind: MediaType { MediaType(rawValue: mediaType ?? "") ?? (title != nil ? .movie : .tv) }
    var uid: String { "\(kind.rawValue)-\(id)" }
    var displayTitle: String { title ?? name ?? "Untitled" }
    var year: String? { (releaseDate ?? firstAirDate).flatMap { $0.count >= 4 ? String($0.prefix(4)) : nil } }
    var posterURL: URL? { posterPath.flatMap { URL(string: "https://image.tmdb.org/t/p/w342\($0)") } }
    var backdropURL: URL? { backdropPath.flatMap { URL(string: "https://image.tmdb.org/t/p/w1280\($0)") } }
}

struct TMDBPage<T: Decodable>: Decodable { let results: [T] }
struct TMDBExternalIDs: Decodable { let imdbId: String? }
struct TVDetails: Decodable { let seasons: [TVSeasonSummary] }

struct TVSeasonSummary: Decodable, Hashable, Identifiable {
    let id: Int
    let seasonNumber: Int
    let name: String?
}

struct TVSeason: Decodable { let episodes: [TVEpisode] }

struct TVEpisode: Decodable, Hashable, Identifiable {
    let id: Int
    let episodeNumber: Int
    let seasonNumber: Int
    let name: String?
    let overview: String?
}

/// Uses a TMDB "API Read Access Token" (v4 bearer token).
struct TMDBClient {
    let token: String
    var language: String = ""
    var region: String = ""

    private func get<T: Decodable>(_ path: String, _ query: [String: String] = [:]) async throws -> T {
        guard var comps = URLComponents(string: "https://api.themoviedb.org/3/\(path)") else { throw URLError(.badURL) }
        var query = query
        if !language.isEmpty, query["language"] == nil { query["language"] = language }
        if !region.isEmpty, query["region"] == nil { query["region"] = region }
        if !query.isEmpty { comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) } }
        guard let url = comps.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let data = try await URLSession.shared.fetch(request)
        return try JSONDecoder.snake.decode(T.self, from: data)
    }

    func trending(_ type: MediaType) async throws -> [TMDBItem] {
        let page: TMDBPage<TMDBItem> = try await get("trending/\(type.rawValue)/week")
        return page.results.map { var item = $0; item.mediaType = type.rawValue; return item }
    }

    func popular(_ type: MediaType) async throws -> [TMDBItem] {
        let page: TMDBPage<TMDBItem> = try await get("\(type.rawValue)/popular")
        return page.results.map { var item = $0; item.mediaType = type.rawValue; return item }
    }

    /// Any TMDB list endpoint, e.g. "movie/now_playing" or "tv/top_rated".
    func list(_ path: String, type: MediaType, _ query: [String: String] = [:]) async throws -> [TMDBItem] {
        let page: TMDBPage<TMDBItem> = try await get(path, query)
        return page.results.map { var item = $0; item.mediaType = type.rawValue; return item }
    }

    func discover(_ type: MediaType, genre: Int) async throws -> [TMDBItem] {
        try await list("discover/\(type.rawValue)", type: type, [
            "with_genres": String(genre),
            "sort_by": "popularity.desc",
            "include_adult": "false",
        ])
    }

    func search(_ query: String) async throws -> [TMDBItem] {
        let page: TMDBPage<TMDBItem> = try await get("search/multi", ["query": query])
        return page.results.filter { $0.mediaType == "movie" || $0.mediaType == "tv" }
    }

    func imdbID(for item: TMDBItem) async throws -> String? {
        let ids: TMDBExternalIDs = try await get("\(item.kind.rawValue)/\(item.id)/external_ids")
        return ids.imdbId
    }

    func seasons(tvID: Int) async throws -> [TVSeasonSummary] {
        let details: TVDetails = try await get("tv/\(tvID)")
        return details.seasons.filter { $0.seasonNumber > 0 }
    }

    func episodes(tvID: Int, season: Int) async throws -> [TVEpisode] {
        let s: TVSeason = try await get("tv/\(tvID)/season/\(season)")
        return s.episodes
    }
}
