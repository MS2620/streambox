import Foundation
import Combine

struct XtreamAccount: Codable, Hashable {
    var server = ""
    var username = ""
    var password = ""
    /// The user's own label for the account; empty shows the server name.
    var name = ""

    var isConfigured: Bool { !server.isEmpty && !username.isEmpty && !password.isEmpty }

    /// The server without "http://", port or path, e.g. "vpn.example.com".
    var host: String {
        URL(string: normalizedServer)?.host ?? server
    }

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? host : trimmed
    }

    var normalizedServer: String {
        var s = server.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.lowercased().hasPrefix("http") { s = "http://" + s }
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }
}

extension XtreamAccount {
    private enum CodingKeys: String, CodingKey {
        case server, username, password, name
    }

    /// Accounts saved by older versions have no name; every field is optional.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        server = (try? c.decodeIfPresent(String.self, forKey: .server)) ?? ""
        username = (try? c.decodeIfPresent(String.self, forKey: .username)) ?? ""
        password = (try? c.decodeIfPresent(String.self, forKey: .password)) ?? ""
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
    }
}

struct AddonEntry: Codable, Identifiable, Hashable {
    var id: String { manifestURL }
    let manifestURL: String
    var name: String
}

/// All user-supplied credentials. Everything is stored in the Keychain because
/// addon URLs can carry private configuration.
final class AppSettings: ObservableObject {
    @Published var tmdbToken: String { didSet { Keychain.set(tmdbToken, for: "tmdbToken") } }
    @Published var xtream: XtreamAccount { didSet { Keychain.setCodable(xtream, for: "xtream") } }
    @Published var addons: [AddonEntry] { didSet { Keychain.setCodable(addons, for: "addons") } }
    @Published var prefs: Preferences {
        didSet {
            prefs.save()
            if prefs.epgRefreshHours != oldValue.epgRefreshHours {
                let hours = prefs.epgRefreshHours
                Task {
                    await XtreamCache.shared.configure(refreshHours: hours)
                    await SportsGuide.shared.configure(refreshHours: hours)
                }
            }
        }
    }

    var tmdb: TMDBClient {
        TMDBClient(token: tmdbToken, language: prefs.tmdbLanguage, region: prefs.tmdbRegion)
    }

    var xtreamClient: XtreamClient {
        XtreamClient(account: xtream, userAgent: prefs.iptvUserAgent)
    }

    init() {
        tmdbToken = Keychain.string(for: "tmdbToken") ?? ""
        // Older versions stored a Real-Debrid key; StreamBox no longer uses one.
        Keychain.setData(nil, for: "realDebridKey")
        xtream = Keychain.codable(XtreamAccount.self, for: "xtream") ?? XtreamAccount()
        addons = Keychain.codable([AddonEntry].self, for: "addons") ?? []
        prefs = Preferences.load()
        let hours = prefs.epgRefreshHours
        Task {
            await XtreamCache.shared.configure(refreshHours: hours)
            await SportsGuide.shared.configure(refreshHours: hours)
        }
    }

    /// False for channels the user hid, or whose whole group is hidden.
    func isVisible(_ channel: XtreamChannel) -> Bool {
        if prefs.hiddenChannelIDs.contains(channel.id) { return false }
        if let category = channel.categoryID, prefs.hiddenCategoryIDs.contains(category) { return false }
        return true
    }

    /// Home rows in the user's order (rows added in newer versions go last).
    var homeRowOrder: [HomeRow] {
        var rows = prefs.homeRows.compactMap { HomeRow(rawValue: $0) }
        for row in HomeRow.allCases where !rows.contains(row) { rows.append(row) }
        return rows
    }

    /// Signs out of TMDB and IPTV and removes every addon. Preferences stay.
    func deleteAllConnections() {
        tmdbToken = ""
        xtream = XtreamAccount()
        addons = []
        Task {
            await XtreamCache.shared.clearGuide()
            await SportsGuide.shared.clear()
        }
    }

    var visibleHomeRows: [HomeRow] {
        homeRowOrder.filter { !prefs.hiddenHomeRows.contains($0.rawValue) }
    }
}
