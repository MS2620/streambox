import Foundation

struct XtreamCategory: Decodable, Identifiable, Hashable {
    let id: String
    let name: String

    private enum CodingKeys: String, CodingKey {
        case categoryID = "category_id"
        case categoryName = "category_name"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.flexString(.categoryID) ?? ""
        name = (try? c.decode(String.self, forKey: .categoryName)) ?? "Unknown"
    }
}

struct XtreamChannel: Decodable, Identifiable, Hashable {
    let id: Int
    let number: Int?
    let name: String
    let icon: String?
    let categoryID: String?

    private enum CodingKeys: String, CodingKey {
        case streamID = "stream_id"
        case num
        case name
        case streamIcon = "stream_icon"
        case categoryID = "category_id"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.flexInt(.streamID) ?? -1
        number = c.flexInt(.num)
        name = (try? c.decode(String.self, forKey: .name)) ?? "Channel"
        let rawIcon = try? c.decode(String.self, forKey: .streamIcon)
        icon = (rawIcon?.isEmpty ?? true) ? nil : rawIcon
        categoryID = c.flexString(.categoryID)
    }
}

struct XtreamEPGEntry: Decodable, Hashable {
    let title: String
    let description: String
    let start: Date?
    let end: Date?

    private enum CodingKeys: String, CodingKey {
        case title
        case description
        case startTimestamp = "start_timestamp"
        case stopTimestamp = "stop_timestamp"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Xtream returns EPG text base64-encoded.
        title = Self.decodeBase64((try? c.decode(String.self, forKey: .title)) ?? "")
        description = Self.decodeBase64((try? c.decode(String.self, forKey: .description)) ?? "")
        start = c.flexInt(.startTimestamp).map { Date(timeIntervalSince1970: TimeInterval($0)) }
        end = c.flexInt(.stopTimestamp).map { Date(timeIntervalSince1970: TimeInterval($0)) }
    }

    private static func decodeBase64(_ raw: String) -> String {
        Data(base64Encoded: raw).map { String(decoding: $0, as: UTF8.self) } ?? raw
    }
}

private struct ShortEPGResponse: Decodable {
    let epgListings: [XtreamEPGEntry]
    private enum CodingKeys: String, CodingKey { case epgListings = "epg_listings" }
}

struct XtreamClient {
    let account: XtreamAccount
    /// Optional User-Agent override; some providers only accept specific players.
    var userAgent: String = ""

    var requestHeaders: [String: String] {
        userAgent.isEmpty ? [:] : ["User-Agent": userAgent]
    }

    private func api(_ action: String?, _ extra: [String: String] = [:]) async throws -> Data {
        guard var comps = URLComponents(string: "\(account.normalizedServer)/player_api.php") else { throw URLError(.badURL) }
        var items = [
            URLQueryItem(name: "username", value: account.username),
            URLQueryItem(name: "password", value: account.password),
        ]
        if let action { items.append(URLQueryItem(name: "action", value: action)) }
        items += extra.map { URLQueryItem(name: $0.key, value: $0.value) }
        comps.queryItems = items
        guard let url = comps.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        for (key, value) in requestHeaders { request.setValue(value, forHTTPHeaderField: key) }
        return try await URLSession.shared.fetch(request)
    }

    /// Returns a short status string, e.g. "Active · expires 12 Mar 2027".
    func authenticate() async throws -> String {
        let data = try await api(nil)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let user = json["user_info"] as? [String: Any],
              "\(user["auth"] ?? "0")" == "1" else {
            return "Login failed"
        }
        var status = (user["status"] as? String) ?? "Active"
        if let exp = user["exp_date"].flatMap({ "\($0)" }), let seconds = TimeInterval(exp) {
            status += " · expires " + Date(timeIntervalSince1970: seconds).formatted(date: .abbreviated, time: .omitted)
        }
        return status
    }

    func liveCategories() async throws -> [XtreamCategory] {
        try JSONDecoder().decode([XtreamCategory].self, from: try await api("get_live_categories"))
    }

    func liveStreams(categoryID: String?) async throws -> [XtreamChannel] {
        let extra = categoryID.map { ["category_id": $0] } ?? [:]
        return try JSONDecoder().decode([XtreamChannel].self, from: try await api("get_live_streams", extra))
    }

    func shortEPG(streamID: Int, limit: Int = 4) async throws -> [XtreamEPGEntry] {
        let data = try await api("get_short_epg", ["stream_id": String(streamID), "limit": String(limit)])
        return try JSONDecoder().decode(ShortEPGResponse.self, from: data).epgListings
    }

    func liveURL(for channel: XtreamChannel, format: LiveStreamFormat = .hls) -> URL? {
        let user = account.username.formEncoded
        let pass = account.password.formEncoded
        return URL(string: "\(account.normalizedServer)/live/\(user)/\(pass)/\(channel.id).\(format.fileExtension)")
    }
}
