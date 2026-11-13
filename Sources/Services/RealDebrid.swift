import Foundation

enum ResolveError: LocalizedError {
    case noPlayableLink
    case noDebridKey
    case notCached
    case torrentFailed(String)

    var errorDescription: String? {
        switch self {
        case .noPlayableLink: return "This stream has no playable link."
        case .noDebridKey: return "This is a torrent stream. Add a Real-Debrid API key in Settings."
        case .notCached: return "Not cached on Real-Debrid yet. It has been queued; try again later."
        case let .torrentFailed(status): return "Real-Debrid reported: \(status)"
        }
    }
}

/// Minimal Real-Debrid REST client: magnet -> select file -> unrestricted link.
struct RealDebridClient {
    let apiKey: String
    private let base = "https://api.real-debrid.com/rest/1.0"

    private struct AddMagnetResponse: Decodable { let id: String }
    private struct Unrestricted: Decodable { let download: String }
    struct TorrentInfo: Decodable {
        struct File: Decodable { let id: Int; let path: String; let bytes: Int; let selected: Int }
        let status: String
        let files: [File]?
        let links: [String]?
    }

    private func request(_ path: String, method: String = "GET", form: [String: String]? = nil) async throws -> Data {
        guard let url = URL(string: base + path) else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        if let form {
            req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            req.httpBody = form.map { "\($0.key)=\($0.value.formEncoded)" }
                .joined(separator: "&")
                .data(using: .utf8)
        }
        return try await URLSession.shared.fetch(req)
    }

    private func info(_ id: String) async throws -> TorrentInfo {
        try JSONDecoder().decode(TorrentInfo.self, from: try await request("/torrents/info/\(id)"))
    }

    private func waitFor(_ id: String, statuses: Set<String>, attempts: Int = 10) async throws -> TorrentInfo {
        let failures: Set<String> = ["magnet_error", "error", "virus", "dead"]
        for _ in 0..<attempts {
            let current = try await info(id)
            if statuses.contains(current.status) { return current }
            if failures.contains(current.status) { throw ResolveError.torrentFailed(current.status) }
            try await Task.sleep(for: .milliseconds(1500))
        }
        throw ResolveError.notCached
    }

    private static let videoExtensions = ["mkv", "mp4", "m4v", "avi", "mov", "ts", "webm"]

    private func pickFile(_ files: [TorrentInfo.File], fileIdx: Int?) -> TorrentInfo.File? {
        if let fileIdx, files.indices.contains(fileIdx) { return files[fileIdx] }
        let videos = files.filter { Self.videoExtensions.contains(($0.path as NSString).pathExtension.lowercased()) }
        return (videos.isEmpty ? files : videos).max(by: { $0.bytes < $1.bytes })
    }

    func unrestrict(_ link: String) async throws -> URL {
        let data = try await request("/unrestrict/link", method: "POST", form: ["link": link])
        let result = try JSONDecoder().decode(Unrestricted.self, from: data)
        guard let url = URL(string: result.download) else { throw ResolveError.noPlayableLink }
        return url
    }

    func resolve(infoHash: String, fileIdx: Int?) async throws -> URL {
        let addData = try await request("/torrents/addMagnet", method: "POST",
                                        form: ["magnet": "magnet:?xt=urn:btih:\(infoHash)"])
        let torrentID = try JSONDecoder().decode(AddMagnetResponse.self, from: addData).id

        var current = try await waitFor(torrentID, statuses: ["waiting_files_selection", "downloaded"])
        let target = pickFile(current.files ?? [], fileIdx: fileIdx)

        if current.status == "waiting_files_selection" {
            let selection = target.map { String($0.id) } ?? "all"
            _ = try await request("/torrents/selectFiles/\(torrentID)", method: "POST", form: ["files": selection])
            current = try await waitFor(torrentID, statuses: ["downloaded"], attempts: 6)
        }

        // RD returns one link per selected file, in file order.
        let selected = (current.files ?? []).filter { $0.selected == 1 }
        let index = selected.firstIndex(where: { $0.id == target?.id })
            ?? selected.indices.max(by: { selected[$0].bytes < selected[$1].bytes })
            ?? 0
        guard let links = current.links, links.indices.contains(index) else { throw ResolveError.noPlayableLink }
        return try await unrestrict(links[index])
    }
}

/// Turns an addon stream into a URL the player can open.
struct StreamResolver {
    let realDebridKey: String

    func resolve(_ stream: StremioStream) async throws -> URL {
        if let raw = stream.url, let url = URL(string: raw) { return url }
        guard let hash = stream.infoHash else { throw ResolveError.noPlayableLink }
        guard !realDebridKey.isEmpty else { throw ResolveError.noDebridKey }
        return try await RealDebridClient(apiKey: realDebridKey).resolve(infoHash: hash, fileIdx: stream.fileIdx)
    }
}
