import Foundation

/// One card on the Apple TV Top Shelf.
struct TopShelfItem: Codable, Hashable {
    let id: String
    let title: String
    var imageURL: String? = nil
    /// streambox:// link opened when the card is selected.
    let link: String
    /// 0–1 for a movie or episode in progress.
    var progress: Double? = nil
}

/// What the app last published for the Top Shelf.
struct TopShelfSnapshot: Codable {
    var live: [TopShelfItem] = []
    var continueWatching: [TopShelfItem] = []
    /// Followed teams' matches and races today and tomorrow.
    var upcoming: [TopShelfItem] = []
    var myList: [TopShelfItem] = []
    /// Only filled when everything above is empty, so the shelf is never blank.
    var trending: [TopShelfItem] = []

    var isEmpty: Bool { cardCount == 0 }
    var cardCount: Int { live.count + continueWatching.count + upcoming.count + myList.count + trending.count }

    init() {}

    /// Rows missing from an older snapshot read as empty.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        live = (try? c.decode([TopShelfItem].self, forKey: .live)) ?? []
        continueWatching = (try? c.decode([TopShelfItem].self, forKey: .continueWatching)) ?? []
        upcoming = (try? c.decode([TopShelfItem].self, forKey: .upcoming)) ?? []
        myList = (try? c.decode([TopShelfItem].self, forKey: .myList)) ?? []
        trending = (try? c.decode([TopShelfItem].self, forKey: .trending)) ?? []
    }
}

/// Shared between StreamBox and its Top Shelf extension through an App Group.
/// If the group isn't available (some sideloading setups), the extension sees nothing
/// and the Top Shelf shows the app's banner image as before.
enum TopShelfStore {
    /// The name the project asks for. Sideloading tools re-sign with their own team and often
    /// rename the group (e.g. adding the team ID), so the real one is read from the bundle.
    static let requestedGroup = "group.com.mauro.streambox"
    /// Every candidate the signing granted (this bundle's profile, then the containing app's for the
    /// extension, then AltStore-style Info.plist hints), sorted so the app and the extension agree;
    /// the first one whose container exists wins.
    static let appGroup: String = {
        var candidates = provisionedGroups() ?? []
        candidates += provisionedGroups(in: containingAppURL) ?? []
        candidates += (Bundle.main.object(forInfoDictionaryKey: "ALTAppGroups") as? [String]) ?? []
        candidates.append(requestedGroup)
        let unique = Array(Set(candidates)).sorted { a, b in
            // Prefer groups named for StreamBox, then alphabetical for a stable choice.
            let sa = a.lowercased().contains("streambox"), sb = b.lowercased().contains("streambox")
            return sa != sb ? sa : a < b
        }
        return unique.first { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) != nil }
            ?? unique.first ?? requestedGroup
    }()

    /// For the extension: the StreamBox.app that contains it (…/StreamBox.app/PlugIns/X.appex).
    private static var containingAppURL: URL? {
        let url = Bundle.main.bundleURL
        guard url.pathExtension == "appex" else { return nil }
        return url.deletingLastPathComponent().deletingLastPathComponent()
    }
    private static let key = "topShelfSnapshot"

    /// The shared container exists, so the Top Shelf can read what the app writes.
    static var isAvailable: Bool {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) != nil
    }

    /// App Groups granted by the provisioning profile the app (or extension) was signed with.
    static func provisionedGroups(in bundleURL: URL? = Bundle.main.bundleURL) -> [String]? {
        guard let url = bundleURL?.appendingPathComponent("embedded.mobileprovision"),
              let data = try? Data(contentsOf: url),
              // The profile is CMS-signed; the plist inside is plain XML.
              let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex),
              let plist = try? PropertyListSerialization.propertyList(
                  from: data.subdata(in: start.lowerBound..<end.upperBound), format: nil) as? [String: Any],
              let entitlements = plist["Entitlements"] as? [String: Any],
              let groups = entitlements["com.apple.security.application-groups"] as? [String],
              !groups.isEmpty else { return nil }
        return groups
    }

    static func write(_ snapshot: TopShelfSnapshot) {
        guard let defaults = UserDefaults(suiteName: appGroup),
              let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key)
    }

    /// The extension notes each time tvOS asks it for the shelf, so Settings can show it's working.
    static func recordRead(cards: Int) {
        let defaults = UserDefaults(suiteName: appGroup)
        defaults?.set(Date(), forKey: "topShelfLastRead")
        defaults?.set(cards, forKey: "topShelfLastReadCards")
    }

    static var lastRead: (date: Date, cards: Int)? {
        guard let defaults = UserDefaults(suiteName: appGroup),
              let date = defaults.object(forKey: "topShelfLastRead") as? Date else { return nil }
        return (date, defaults.integer(forKey: "topShelfLastReadCards"))
    }

    static func read() -> TopShelfSnapshot? {
        guard let data = UserDefaults(suiteName: appGroup)?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(TopShelfSnapshot.self, from: data)
    }
}
