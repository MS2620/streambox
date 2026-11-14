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

    var isEmpty: Bool { live.isEmpty && continueWatching.isEmpty && upcoming.isEmpty }

    init() {}

    /// Rows missing from an older snapshot read as empty.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        live = (try? c.decode([TopShelfItem].self, forKey: .live)) ?? []
        continueWatching = (try? c.decode([TopShelfItem].self, forKey: .continueWatching)) ?? []
        upcoming = (try? c.decode([TopShelfItem].self, forKey: .upcoming)) ?? []
    }
}

/// Shared between StreamBox and its Top Shelf extension through an App Group.
/// If the group isn't available (some sideloading setups), the extension sees nothing
/// and the Top Shelf shows the app's banner image as before.
enum TopShelfStore {
    static let appGroup = "group.com.mauro.streambox"
    private static let key = "topShelfSnapshot"

    static func write(_ snapshot: TopShelfSnapshot) {
        guard let defaults = UserDefaults(suiteName: appGroup),
              let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key)
    }

    static func read() -> TopShelfSnapshot? {
        guard let data = UserDefaults(suiteName: appGroup)?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(TopShelfSnapshot.self, from: data)
    }
}
