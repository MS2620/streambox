import Foundation
import Combine

struct XtreamAccount: Codable, Equatable {
    var server = ""
    var username = ""
    var password = ""

    var isConfigured: Bool { !server.isEmpty && !username.isEmpty && !password.isEmpty }

    var normalizedServer: String {
        var s = server.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.lowercased().hasPrefix("http") { s = "http://" + s }
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }
}

struct AddonEntry: Codable, Identifiable, Hashable {
    var id: String { manifestURL }
    let manifestURL: String
    var name: String
}

/// All user-supplied credentials. Everything is stored in the Keychain because
/// addon URLs usually embed a debrid key in their config.
final class AppSettings: ObservableObject {
    @Published var tmdbToken: String { didSet { Keychain.set(tmdbToken, for: "tmdbToken") } }
    @Published var realDebridKey: String { didSet { Keychain.set(realDebridKey, for: "realDebridKey") } }
    @Published var xtream: XtreamAccount { didSet { Keychain.setCodable(xtream, for: "xtream") } }
    @Published var addons: [AddonEntry] { didSet { Keychain.setCodable(addons, for: "addons") } }
    @Published var prefs: Preferences {
        didSet {
            prefs.save()
            if prefs.epgRefreshHours != oldValue.epgRefreshHours {
                let hours = prefs.epgRefreshHours
                Task { await XtreamCache.shared.configure(refreshHours: hours) }
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
        realDebridKey = Keychain.string(for: "realDebridKey") ?? ""
        xtream = Keychain.codable(XtreamAccount.self, for: "xtream") ?? XtreamAccount()
        addons = Keychain.codable([AddonEntry].self, for: "addons") ?? []
        prefs = Preferences.load()
        let hours = prefs.epgRefreshHours
        Task { await XtreamCache.shared.configure(refreshHours: hours) }
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

    var visibleHomeRows: [HomeRow] {
        homeRowOrder.filter { !prefs.hiddenHomeRows.contains($0.rawValue) }
    }
}
