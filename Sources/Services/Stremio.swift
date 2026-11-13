import Foundation

struct AddonManifest: Decodable {
    let id: String
    let name: String
    let version: String?
}

/// A stream object as defined by the Stremio addon protocol.
struct StremioStream: Decodable, Hashable {
    let name: String?
    let title: String?
    let description: String?
    let url: String?
    let infoHash: String?
    let fileIdx: Int?

    var headline: String {
        (name ?? "Stream").replacingOccurrences(of: "\n", with: " · ")
    }

    var detail: String {
        (title ?? description ?? "").replacingOccurrences(of: "\n", with: "  ")
    }
}

private struct StreamResponse: Decodable { let streams: [StremioStream] }

struct FoundStream: Identifiable {
    let id = UUID()
    let addonName: String
    let stream: StremioStream
}

/// Talks to any Stremio-compatible addon (the user supplies the manifest URL,
/// typically with their own debrid key in the addon's config).
struct StremioAddonClient {
    let manifestURL: URL

    static func normalize(_ raw: String) -> URL? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.lowercased().hasPrefix("stremio://") { s = "https://" + s.dropFirst("stremio://".count) }
        if !s.hasSuffix("/manifest.json") {
            while s.hasSuffix("/") { s.removeLast() }
            s += "/manifest.json"
        }
        return URL(string: s)
    }

    private var base: String {
        String(manifestURL.absoluteString.dropLast("/manifest.json".count))
    }

    func manifest() async throws -> AddonManifest {
        let data = try await URLSession.shared.fetch(URLRequest(url: manifestURL))
        return try JSONDecoder().decode(AddonManifest.self, from: data)
    }

    /// - Parameters:
    ///   - type: "movie" or "series"
    ///   - id: IMDb id, e.g. "tt0111161" or "tt0903747:1:1" for an episode
    func streams(type: String, id: String) async throws -> [StremioStream] {
        guard let url = URL(string: "\(base)/stream/\(type)/\(id).json") else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        let data = try await URLSession.shared.fetch(request)
        return try JSONDecoder().decode(StreamResponse.self, from: data).streams
    }
}
