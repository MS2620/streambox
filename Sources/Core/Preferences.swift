import Foundation
import CoreGraphics

// MARK: - Option types

enum LiveStreamFormat: String, Codable, CaseIterable, Identifiable {
    case hls, ts
    var id: String { rawValue }
    var label: String { self == .hls ? "HLS (.m3u8)" : "MPEG-TS (.ts)" }
    var fileExtension: String { self == .hls ? "m3u8" : "ts" }
}

enum ChannelSwitching: String, Codable, CaseIterable, Identifiable {
    case fast, stable
    var id: String { rawValue }
    var label: String { self == .fast ? "Fast (quicker zapping)" : "Stable (bigger buffer)" }
}

enum ChannelSort: String, Codable, CaseIterable, Identifiable {
    case server, number, name
    var id: String { rawValue }
    var label: String {
        switch self {
        case .server: return "Provider order"
        case .number: return "Channel number"
        case .name: return "Name (A–Z)"
        }
    }
}

enum MaxResolution: String, Codable, CaseIterable, Identifiable {
    case any, uhd, fhd, hd
    var id: String { rawValue }
    var label: String {
        switch self {
        case .any: return "No limit"
        case .uhd: return "4K"
        case .fhd: return "1080p"
        case .hd: return "720p"
        }
    }
    var maxLines: Int {
        switch self {
        case .any: return .max
        case .uhd: return 2160
        case .fhd: return 1080
        case .hd: return 720
        }
    }
}

enum StreamSort: String, Codable, CaseIterable, Identifiable {
    case addon, quality
    var id: String { rawValue }
    var label: String { self == .addon ? "Addon order" : "Best quality first" }
}

enum SubtitleSize: String, Codable, CaseIterable, Identifiable {
    case small, medium, large
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var points: CGFloat {
        switch self {
        case .small: return 34
        case .medium: return 44
        case .large: return 56
        }
    }
}

enum LiveLayout: String, Codable, CaseIterable, Identifiable {
    case guide, list
    var id: String { rawValue }
    var label: String { self == .guide ? "Guide" : "List" }
}

enum BackgroundStyle: String, Codable, CaseIterable, Identifiable {
    case frosted, dark
    var id: String { rawValue }
    var label: String { self == .frosted ? "Frosted" : "Dark" }
}

/// A Live TV group the user made from channels in the provider's groups.
struct ChannelFolder: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var channelIDs: [Int]
}

/// The rows that can appear on Home, in their default order.
enum HomeRow: String, CaseIterable, Identifiable {
    case myList, trending, channels, teams, popularMovies, popularSeries, cinemas, airingToday, topRated

    var id: String { rawValue }

    var title: String {
        switch self {
        case .myList: return "My List"
        case .trending: return "Trending Now"
        case .channels: return "Favourite Channels"
        case .teams: return "My Teams"
        case .popularMovies: return "Popular Movies"
        case .popularSeries: return "Popular Series"
        case .cinemas: return "New in Cinemas"
        case .airingToday: return "Airing Today"
        case .topRated: return "Top Rated Movies"
        }
    }
}

// MARK: - Preferences

/// Non-secret app preferences, stored in UserDefaults.
/// New fields can be added freely: missing keys fall back to their defaults.
struct Preferences: Codable, Equatable {
    // Content
    var tmdbLanguage = "en-GB"
    var tmdbRegion = "GB"

    // Playback
    var audioLanguage = "en"
    var autoSubtitles = false
    var subtitleLanguage = "en"
    var subtitleSize: SubtitleSize = .medium
    var seekBackSeconds = 10
    var seekForwardSeconds = 30
    var matchContent = true
    var upscaleLowResolution = false
    var dialogueBoost = false
    var nightMode = false

    // Streams (Stremio addons)
    var maxResolution: MaxResolution = .any
    var streamSort: StreamSort = .quality
    var autoPlayFirstStream = false

    // My List (saved movies and series), most recent last
    var myList: [TMDBItem] = []

    // Sports
    var favouriteTeams: [FavouriteTeam] = []
    var sportsDaysAhead = 14

    // Calendar
    var calendarEpisodesPerSeries = 2
    var calendarDaysAhead = 90

    // Home screen: row ids in order, and the ones switched off
    var homeRows: [String] = HomeRow.allCases.map(\.rawValue)
    var hiddenHomeRows: Set<String> = []

    // Appearance
    var backgroundStyle: BackgroundStyle = .frosted

    // Search
    var recentSearches: [String] = []

    // Live TV
    var liveFormat: LiveStreamFormat = .hls
    var channelSwitching: ChannelSwitching = .fast
    var timeshiftMinutes = 0
    /// Switch the TV's refresh rate for live channels too. Off: avoids a black flash on every zap.
    var matchContentLive = false
    var showEPG = true
    var channelSort: ChannelSort = .server
    var favouritesFirst = true
    var rememberLastCategory = true
    var iptvUserAgent = ""
    var hiddenCategoryIDs: Set<String> = []

    // Parental controls (the PIN itself is in the Keychain)
    var parentalControlsOn = false
    var lockedCategoryIDs: Set<String> = []
    /// Manifest URLs of addons whose streams need the PIN.
    var lockedAddonIDs: Set<String> = []
    var hideLockedGroups = false
    var unlockMinutes = 15

    // Trakt (account details are in the Keychain)
    var traktProgress = true
    var traktHistory = true
    var traktWatchlist = true
    var traktScrobble = true
    var favouriteChannelIDs: Set<Int> = []
    /// Live channels played, newest first (up to 20).
    var recentChannelIDs: [Int] = []
    var lastCategoryID: String?
    var liveLayout: LiveLayout = .guide
    var guideHours = 2
    var guidePreview = true
    var showChannelNumbers = false
    var hiddenChannelIDs: Set<Int> = []
    var folders: [ChannelFolder] = []
    /// How often guide data is re-downloaded: hours, 0 = every launch, -1 = only manually.
    var epgRefreshHours = 6
    /// The provider's own movie and series libraries (VOD). Off by default.
    var showProviderMovies = false
    var showProviderSeries = false

    private static let key = "preferences.v1"

    static func load() -> Preferences {
        guard let data = UserDefaults.standard.data(forKey: key),
              let saved = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let defaultsData = try? JSONEncoder().encode(Preferences()),
              let defaults = try? JSONSerialization.jsonObject(with: defaultsData) as? [String: Any] else {
            return Preferences()
        }
        // Saved values win; keys added in newer versions keep their defaults.
        let merged = defaults.merging(saved) { _, saved in saved }
        guard let mergedData = try? JSONSerialization.data(withJSONObject: merged),
              let prefs = try? JSONDecoder().decode(Preferences.self, from: mergedData) else {
            return Preferences()
        }
        return prefs
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}

/// A labelled choice for pickers.
struct Choice: Hashable, Identifiable {
    let code: String
    let name: String
    var id: String { code }
    init(_ code: String, _ name: String) { self.code = code; self.name = name }
}

/// Common choices for the language pickers.
enum LanguageOptions {
    static let audio: [Choice] = [
        Choice("en", "English"), Choice("pt", "Portuguese"), Choice("es", "Spanish"), Choice("fr", "French"),
        Choice("de", "German"), Choice("it", "Italian"), Choice("nl", "Dutch"), Choice("pl", "Polish"),
        Choice("tr", "Turkish"), Choice("ar", "Arabic"), Choice("hi", "Hindi"), Choice("ja", "Japanese"),
        Choice("ko", "Korean"), Choice("zh", "Chinese"),
    ]

    static let tmdb: [Choice] = [
        Choice("en-GB", "English (UK)"), Choice("en-US", "English (US)"), Choice("pt-PT", "Portuguese (Portugal)"),
        Choice("pt-BR", "Portuguese (Brazil)"), Choice("es-ES", "Spanish"), Choice("fr-FR", "French"),
        Choice("de-DE", "German"), Choice("it-IT", "Italian"), Choice("nl-NL", "Dutch"), Choice("pl-PL", "Polish"),
    ]

    static let regions: [Choice] = [
        Choice("GB", "United Kingdom"), Choice("IE", "Ireland"), Choice("US", "United States"), Choice("PT", "Portugal"),
        Choice("BR", "Brazil"), Choice("ES", "Spain"), Choice("FR", "France"), Choice("DE", "Germany"), Choice("IT", "Italy"),
        Choice("NL", "Netherlands"),
    ]
}

/// Date helpers shared by the Calendar and Sports screens.
enum DayFormat {
    private static let dayParser: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    /// Parses TMDB air dates ("2026-11-21") as local midnight.
    static func parseDay(_ string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        return dayParser.date(from: string)
    }

    /// "Today", "Tomorrow", "Yesterday" or "Friday 21 November".
    static func label(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}
