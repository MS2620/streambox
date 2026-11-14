import Foundation

struct AddonManifest: Decodable {
    let id: String
    let name: String
    let version: String?
    let description: String?
    let types: [String]?
}

/// A stream object as defined by the Stremio addon protocol.
struct StremioStream: Decodable, Hashable {
    let name: String?
    let title: String?
    let description: String?
    let url: String?
    /// Set on torrent-only results. StreamBox can't play those, so they are skipped.
    let infoHash: String?

    /// A direct web link the player can open, if the addon gave one.
    var playableURL: URL? {
        guard let url, let parsed = URL(string: url),
              let scheme = parsed.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return nil }
        return parsed
    }

    var headline: String {
        (name ?? "Stream").replacingOccurrences(of: "\n", with: " · ")
    }

    /// Vertical resolution guessed from the addon's labels (2160, 1440, 1080, 720, 480), or 0 if unknown.
    /// The addon's name is checked first, as that is where most addons put the quality.
    var resolution: Int {
        for text in [name, [title, description].compactMap { $0 }.joined(separator: " ")] {
            if let text, let found = Self.resolution(in: text) { return found }
        }
        return 0
    }

    /// Looks for whole words such as "4K", "UHD", "FHD", "1080p" or "HD". Addons
    /// often style labels with look-alike letters (𝗙𝗛𝗗); those are mapped back first.
    private static func resolution(in text: String) -> Int? {
        let plain = text.precomposedStringWithCompatibilityMapping.lowercased()
        let words = Set(plain.split { !$0.isLetter && !$0.isNumber }.map(String.init))
        func has(_ any: String...) -> Bool { any.contains { words.contains($0) } }
        if has("2160p", "2160", "4k", "uhd", "2160i") { return 2160 }
        if has("1440p", "1440", "2k", "qhd") { return 1440 }
        if has("1080p", "1080", "1080i", "fhd") { return 1080 }
        if has("720p", "720", "hd") { return 720 }
        if has("576p", "576", "480p", "480", "sd") { return 480 }
        return nil
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

/// Talks to any Stremio-compatible addon. The user supplies the manifest URL.
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
