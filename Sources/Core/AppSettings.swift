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

    init() {
        tmdbToken = Keychain.string(for: "tmdbToken") ?? ""
        realDebridKey = Keychain.string(for: "realDebridKey") ?? ""
        xtream = Keychain.codable(XtreamAccount.self, for: "xtream") ?? XtreamAccount()
        addons = Keychain.codable([AddonEntry].self, for: "addons") ?? []
    }
}
