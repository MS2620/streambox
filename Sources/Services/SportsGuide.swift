import Foundation

// Finds which of the user's IPTV channels show a fixture, by reading the
// provider's whole TV guide (one XMLTV file) and matching team names in many
// languages, the competition, and the kick-off time.

// MARK: - Text

enum GuideText {
    /// Lower-case, accents removed, punctuation turned into single spaces, with a
    /// space at each end so whole words can be found with `contains(" word ")`.
    static func normalize(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                                  locale: nil).lowercased()
        var out = String.UnicodeScalarView()
        out.append(" ")
        var lastWasSpace = true
        for scalar in folded.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                out.append(scalar)
                lastWasSpace = false
            } else if !lastWasSpace {
                out.append(" ")
                lastWasSpace = true
            }
        }
        if !lastWasSpace { out.append(" ") }
        return String(out)
    }

    /// `normalize` without the padding spaces.
    static func phrase(_ text: String) -> String {
        normalize(text).trimmingCharacters(in: .whitespaces)
    }

    /// "Portugal x Dinamarca", "Arsenal v Spurs", "Lakers @ Celtics"…
    static func hasVersus(_ raw: String) -> Bool {
        let lower = " " + raw.lowercased() + " "
        return [" v ", " v. ", " vs ", " vs. ", " x ", " - ", " – ", " — ", " @ "].contains { lower.contains($0) }
    }
}

/// A set of names that can be looked for quickly in normalized text.
struct KeywordSet {
    private var single: Set<String> = []
    /// First word → whole padded phrases starting with it.
    private var phrases: [String: [String]] = [:]

    init(_ words: [String]) {
        for word in words {
            let phrase = GuideText.phrase(word)
            guard phrase.count >= 2 else { continue }
            let parts = phrase.split(separator: " ")
            if parts.count == 1 {
                single.insert(phrase)
            } else if let first = parts.first {
                let padded = " " + phrase + " "
                if !(phrases[String(first)] ?? []).contains(padded) {
                    phrases[String(first), default: []].append(padded)
                }
            }
        }
    }

    var isEmpty: Bool { single.isEmpty && phrases.isEmpty }

    /// `text` must come from `GuideText.normalize`.
    func matches(_ text: String) -> Bool {
        for word in text.split(separator: " ") {
            let key = String(word)
            if single.contains(key) { return true }
            if let list = phrases[key], list.contains(where: { text.contains($0) }) { return true }
        }
        return false
    }

    /// Identifies the set, so a guide read with it can be reused.
    var signature: String {
        (single.sorted() + phrases.values.flatMap { $0 }.sorted()).joined(separator: "|")
    }
}

// MARK: - Names in other languages

enum TeamNames {
    /// Club prefixes and suffixes that guides often leave out.
    private static let affixes: Set<String> = [
        "fc", "afc", "cf", "sc", "ac", "as", "ss", "cd", "ud", "sd", "fk", "sk", "bk", "sv", "rcd", "ca", "club", "cp",
        "sl", "rc", "us", "if", "ik",
    ]
    /// A last word that can be dropped: "Newcastle United" → "Newcastle".
    private static let genericLast: Set<String> = [
        "united", "city", "town", "county", "rovers", "wanderers", "athletic", "albion", "hotspur",
    ]
    /// Short forms that would point at more than one team.
    private static let ambiguous: Set<String> = ["manchester", "sheffield", "bristol", "nottingham"]
    /// Never used on their own.
    private static let tooGeneric: Set<String> = [
        "united", "city", "town", "real", "club", "team", "national", "sport", "the", "de", "fc",
    ]

    /// Well-known clubs whose everyday names differ from their full ones.
    private static let clubs: [String: [String]] = [
        "manchester united": ["man utd", "man united"],
        "manchester city": ["man city"],
        "tottenham hotspur": ["spurs", "tottenham"],
        "wolverhampton wanderers": ["wolves"],
        "brighton hove albion": ["brighton"],
        "nottingham forest": ["nottm forest", "notts forest"],
        "west ham united": ["west ham"],
        "bayern munich": ["bayern", "bayern munchen", "bayern munique", "bayern de munich", "bayern monaco"],
        "inter milan": ["inter", "internazionale", "inter de milao", "inter de milan"],
        "internazionale": ["inter", "inter milan"],
        "ac milan": ["milan"],
        "juventus": ["juve"],
        "atletico madrid": ["atletico", "atletico de madrid", "atletico madrid"],
        "paris saint germain": ["psg", "paris sg", "paris"],
        "borussia dortmund": ["dortmund", "bvb"],
        "borussia monchengladbach": ["gladbach", "monchengladbach"],
        "bayer leverkusen": ["leverkusen"],
        "rb leipzig": ["leipzig"],
        "sporting cp": ["sporting", "sporting lisbon", "sporting clube de portugal"],
        "porto": ["fc porto"],
        "benfica": ["sl benfica"],
        "red star belgrade": ["crvena zvezda", "estrela vermelha"],
        "olympique marseille": ["marseille", "om"],
        "olympique lyonnais": ["lyon", "ol"],
        "napoli": ["ssc napoli"],
        "celtic": ["celtic fc"],
    ]

    /// England, Scotland, Wales and Northern Ireland aren't countries in the locale data.
    private static let homeNations: [String: [String]] = [
        "england": ["england", "inglaterra", "angleterre", "inghilterra", "engeland", "anglia", "ingiltere"],
        "scotland": ["scotland", "escocia", "ecosse", "schottland", "scozia", "schotland", "szkocja", "iskocya"],
        "wales": ["wales", "pais de gales", "gales", "pays de galles", "galles", "walia", "galler"],
        "northern ireland": ["northern ireland", "irlanda do norte", "irlanda del norte", "irlande du nord",
                             "nordirland", "irlanda del nord", "noord ierland", "irlandia polnocna", "kuzey irlanda"],
    ]

    /// English names ESPN uses that differ from the locale's.
    private static let englishSynonyms: [String: String] = [
        "usa": "US", "united states": "US", "south korea": "KR", "korea republic": "KR", "north korea": "KP",
        "ivory coast": "CI", "cote d ivoire": "CI", "czech republic": "CZ", "czechia": "CZ", "turkey": "TR",
        "turkiye": "TR", "republic of ireland": "IE", "ireland": "IE", "bosnia herzegovina": "BA",
        "bosnia and herzegovina": "BA", "dr congo": "CD", "cape verde": "CV", "cape verde islands": "CV",
        "north macedonia": "MK", "russia": "RU", "iran": "IR", "china pr": "CN", "china": "CN",
        "chinese taipei": "TW", "curacao": "CW", "the gambia": "GM", "gambia": "GM",
    ]

    private static let languages = ["en", "pt", "es", "fr", "de", "it", "nl", "pl", "tr", "da", "sv", "nb", "ro", "hr", "cs"]

    private static let regionIndex: [String: String] = {
        var map: [String: String] = [:]
        let english = Locale(identifier: "en")
        for region in Locale.Region.isoRegions {
            let code = region.identifier
            guard code.count == 2, let name = english.localizedString(forRegionCode: code) else { continue }
            map[GuideText.phrase(name)] = code
        }
        for (name, code) in englishSynonyms { map[name] = code }
        return map
    }()

    /// The country's name in the languages IPTV guides are usually written in.
    static func countryNames(_ name: String) -> [String] {
        let key = GuideText.phrase(name)
        if let names = homeNations[key] { return names }
        guard let code = regionIndex[key] else { return [] }
        return languages.compactMap { Locale(identifier: $0).localizedString(forRegionCode: code) }
    }

    /// Every name a guide might use for the team.
    static func aliases(_ name: String, extra: [String] = []) -> [String] {
        var result: Set<String> = []
        func add(_ phrase: String) {
            guard phrase.count >= 3, !tooGeneric.contains(phrase) else { return }
            result.insert(phrase)
        }
        for raw in [name] + extra {
            let phrase = GuideText.phrase(raw)
            guard !phrase.isEmpty else { continue }
            add(phrase)
            let words = phrase.split(separator: " ").map(String.init)
            let core = words.filter { !affixes.contains($0) && Int($0) == nil }
            let coreName = core.joined(separator: " ")
            if !core.isEmpty, core.count < words.count { add(coreName) }
            if core.count >= 2, let last = core.last, genericLast.contains(last) {
                let shorter = core.dropLast().joined(separator: " ")
                if !ambiguous.contains(shorter) { add(shorter) }
            }
            for known in [phrase, coreName] {
                clubs[known]?.forEach(add)
            }
        }
        countryNames(name).map(GuideText.phrase).forEach(add)
        return Array(result)
    }
}

enum CompetitionNames {
    /// Words in the competition's name → what guides call it.
    private static let table: [(keys: [String], names: [String])] = [
        (["nations league"], ["nations league", "liga das nacoes", "liga de las naciones", "ligue des nations",
                              "nations league", "liga delle nazioni", "liga narodow", "uluslar ligi"]),
        (["champions league"], ["champions league", "liga dos campeoes", "liga de campeones", "ligue des champions",
                                "champions"]),
        (["europa league"], ["europa league", "liga europa", "ligue europa"]),
        (["conference league"], ["conference league", "liga conferencia", "conference"]),
        (["premier league"], ["premier league", "liga inglesa"]),
        (["laliga", "la liga"], ["laliga", "la liga", "liga espanhola", "liga espanola", "liga ea sports"]),
        (["serie a"], ["serie a", "liga italiana"]),
        (["bundesliga"], ["bundesliga", "liga alema"]),
        (["ligue 1"], ["ligue 1", "liga francesa"]),
        (["primeira liga", "liga portugal"], ["liga portugal", "primeira liga", "i liga", "liga betclic"]),
        (["eredivisie"], ["eredivisie"]),
        (["scottish premiership", "premiership"], ["premiership", "spfl"]),
        (["world cup"], ["world cup", "mundial", "copa do mundo", "copa mundial", "coupe du monde",
                         "weltmeisterschaft", "wm", "coppa del mondo"]),
        (["qualifying", "qualifiers"], ["qualifying", "qualifiers", "qualificacao", "apuramento", "eliminatorias",
                                        "clasificacion", "qualifications", "qualifikation", "qualificazioni"]),
        (["euro", "european championship"], ["euro", "europeu", "eurocopa"]),
        (["fa cup"], ["fa cup", "taca de inglaterra"]),
        (["league cup", "carabao", "efl cup"], ["carabao cup", "league cup", "efl cup", "taca da liga inglesa"]),
        (["copa del rey"], ["copa del rey", "taca do rei"]),
        (["taca de portugal", "portuguese cup"], ["taca de portugal"]),
        (["dfb pokal"], ["dfb pokal", "taca da alemanha"]),
        (["coppa italia"], ["coppa italia", "taca de italia"]),
        (["six nations"], ["six nations", "6 nations", "seis nacoes", "seis naciones", "six nations",
                           "tournoi des six nations", "sei nazioni"]),
        (["champions cup"], ["champions cup"]),
        (["nfl"], ["nfl"]), (["nba"], ["nba"]), (["nhl"], ["nhl"]), (["mlb"], ["mlb"]),
    ]

    static func aliases(_ competition: String) -> [String] {
        let padded = GuideText.normalize(competition)
        var result: [String] = []
        for entry in table where entry.keys.contains(where: { padded.contains(" " + $0 + " ") }) {
            result += entry.names
        }
        return result
    }
}

// MARK: - Scoring a listing

struct FixtureMatcher {
    static let threshold = 50

    private static let raceWords = ["formula 1", "formula one", "f1", "formule 1", "formel 1", "grand prix",
                                    "grande premio", "gran premio", "gran premi"]
    private static let sessionWords = ["race", "corrida", "carrera", "course", "rennen", "gara", "qualifying",
                                       "qualificacao", "clasificacion", "qualifications", "qualifiche", "sprint",
                                       "practice", "treinos", "libres", "training", "libere"]
    private static let liveWords = ["live", "direto", "directo", "en directo", "en vivo", "ao vivo", "en direct",
                                    "diretta", "in diretta", "direkt"]

    private let home: KeywordSet
    private let away: KeywordSet
    private let competition: KeywordSet
    private let place: KeywordSet
    private let isRace: Bool

    private static let race = KeywordSet(raceWords)
    private static let session = KeywordSet(sessionWords)
    private static let live = KeywordSet(liveWords)

    init(fixture: Fixture) {
        isRace = fixture.isRace
        home = KeywordSet(fixture.home.map { TeamNames.aliases($0.name, extra: $0.aliases) } ?? [])
        away = KeywordSet(fixture.away.map { TeamNames.aliases($0.name, extra: $0.aliases) } ?? [])
        competition = KeywordSet(CompetitionNames.aliases(fixture.competition))
        // F1: the place ("Las Vegas", "Monza") from the race name and city.
        let racePhrases = Set(Self.raceWords.map(GuideText.phrase))
        let places = fixture.keywords
            .map { GuideText.phrase($0).replacingOccurrences(of: "grand prix", with: "").trimmingCharacters(in: .whitespaces) }
            .filter { $0.count >= 3 && !racePhrases.contains($0) }
        place = KeywordSet(places)
    }

    /// How well a listing fits the fixture; below `threshold` it isn't a match.
    func score(normalized: String, title: String) -> (score: Int, bothTeams: Bool) {
        let isLive = Self.live.matches(normalized)
        if isRace {
            guard Self.race.matches(normalized) else { return (0, false) }
            var score = 50
            if place.matches(normalized) { score += 30 }
            if Self.session.matches(normalized) { score += 10 }
            if isLive { score += 5 }
            return (score, false)
        }
        let homeHit = home.matches(normalized)
        let awayHit = away.matches(normalized)
        guard homeHit || awayHit else { return (0, false) }
        let competitionHit = competition.matches(normalized)
        var score: Int
        if homeHit && awayHit {
            score = 100
        } else if competitionHit || GuideText.hasVersus(title) {
            score = 50
        } else {
            return (0, false)
        }
        if competitionHit { score += 15 }
        if isLive { score += 10 }
        return (score, homeHit && awayHit)
    }

    /// The names worth keeping when reading the guide: every followed team, and
    /// Formula 1 words when a constructor is followed.
    static func indexKeywords(for teams: [FavouriteTeam]) -> KeywordSet {
        var words: [String] = []
        for team in teams {
            if team.isF1 {
                words += raceWords
            } else {
                words += TeamNames.aliases(team.name)
            }
        }
        return KeywordSet(words)
    }
}

// MARK: - The provider's guide

struct GuideProgramme {
    /// The XMLTV channel id, lower-cased.
    let channel: String
    let start: Date
    let end: Date
    let title: String
    let description: String
    /// Title, sub-title and description, normalized.
    let text: String
}

struct GuideIndex {
    let programmes: [GuideProgramme]
    /// When the last listing in the whole guide ends.
    let coverageEnd: Date?
}

/// Downloads the XMLTV guide (kept on disk between refreshes) and keeps only
/// the listings that mention a followed team.
actor SportsGuide {
    static let shared = SportsGuide()

    private var cached: (key: String, value: GuideIndex)?
    private var lastFailure: (account: String, date: Date)?
    /// Hours between downloads; 0 = once per launch, below 0 = only when asked.
    private var refreshHours = 6
    private let launch = Date()

    func configure(refreshHours: Int) {
        self.refreshHours = refreshHours
    }

    func clear() {
        cached = nil
        lastFailure = nil
        if let folder = Self.folder {
            try? FileManager.default.removeItem(at: folder)
        }
    }

    private static var folder: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("xmltv", isDirectory: true)
    }

    private static func file(for account: String) -> URL? {
        var hash: UInt64 = 5381
        for byte in account.utf8 { hash = (hash &* 33) &+ UInt64(byte) }
        return folder?.appendingPathComponent("\(hash).xml")
    }

    private static func modified(_ file: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date
    }

    private func isFresh(_ date: Date) -> Bool {
        if refreshHours < 0 { return true }
        if refreshHours == 0 { return date >= launch }
        return Date().timeIntervalSince(date) < TimeInterval(refreshHours) * 3600
    }

    /// - Parameter force: download the guide again even if the saved copy is fresh.
    func index(_ client: XtreamClient, keywords: KeywordSet, force: Bool = false) async throws -> GuideIndex {
        let account = client.account.normalizedServer + "|" + client.account.username
        guard let file = Self.file(for: account) else { throw URLError(.cannotCreateFile) }

        var saved = Self.modified(file)
        if force || saved.map({ !isFresh($0) }) ?? true {
            // After a failure, don't try the big download again for a few minutes.
            let recentlyFailed = lastFailure.map { $0.account == account && Date().timeIntervalSince($0.date) < 600 } ?? false
            if force || !recentlyFailed {
                do {
                    try await download(client, to: file)
                    saved = Self.modified(file)
                    lastFailure = nil
                } catch {
                    lastFailure = (account, Date())
                    // An older copy is better than nothing.
                    if saved == nil { throw error }
                }
            } else if saved == nil {
                throw URLError(.resourceUnavailable)
            }
        }
        guard let saved else { throw URLError(.cannotOpenFile) }

        let key = "\(account)|\(saved.timeIntervalSince1970)|\(keywords.signature)"
        if let cached, cached.key == key { return cached.value }
        let value = try XMLTVReader.read(file, keywords: keywords)
        cached = (key, value)
        return value
    }

    private func download(_ client: XtreamClient, to file: URL) async throws {
        guard let url = client.xmltvURL else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.timeoutInterval = 90
        for (key, value) in client.requestHeaders { request.setValue(value, forHTTPHeaderField: key) }
        let (temporary, response) = try await URLSession.shared.download(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            try? FileManager.default.removeItem(at: temporary)
            throw HTTPError.status(http.statusCode, "")
        }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: file)
        try FileManager.default.moveItem(at: temporary, to: file)
    }
}

// MARK: - Reading XMLTV

enum XMLTVDate {
    /// "20261114194500 +0000"; the seconds and the offset are optional.
    static func parse(_ raw: String) -> Date? {
        let bytes = Array(raw.utf8)
        guard bytes.count >= 12 else { return nil }
        func number(_ from: Int, _ length: Int) -> Int? {
            guard from + length <= bytes.count else { return nil }
            var value = 0
            for index in from..<(from + length) {
                let byte = bytes[index]
                guard byte >= 48, byte <= 57 else { return nil }
                value = value * 10 + Int(byte - 48)
            }
            return value
        }
        guard let year = number(0, 4), let month = number(4, 2), let day = number(6, 2),
              let hour = number(8, 2), let minute = number(10, 2),
              (1...12).contains(month), (1...31).contains(day) else { return nil }
        let second = number(12, 2) ?? 0
        var offset = 0
        if let sign = bytes.firstIndex(where: { $0 == 43 || $0 == 45 }), sign >= 12,
           let hours = number(sign + 1, 2), let minutes = number(sign + 3, 2) {
            offset = (hours * 3600 + minutes * 60) * (bytes[sign] == 45 ? -1 : 1)
        }
        let seconds = daysFromCivil(year, month, day) * 86_400 + hour * 3600 + minute * 60 + second - offset
        return Date(timeIntervalSince1970: TimeInterval(seconds))
    }

    /// Days since 1970-01-01 for a Gregorian date (Howard Hinnant's algorithm).
    private static func daysFromCivil(_ year: Int, _ month: Int, _ day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yearOfEra = y - era * 400
        let shiftedMonth = (month + 9) % 12
        let dayOfYear = (153 * shiftedMonth + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }
}

/// Streams through the XMLTV file, keeping only listings that mention one of
/// the keywords, so even very large guides use little memory.
final class XMLTVReader: NSObject, XMLParserDelegate {
    private let keywords: KeywordSet
    private let windowStart = Date().addingTimeInterval(-6 * 3600)
    private let windowEnd = Date().addingTimeInterval(21 * 86_400)

    private var programmes: [GuideProgramme] = []
    private var latestEnd: Date?

    private var inProgramme = false
    private var channel = ""
    private var startText = ""
    private var stopText = ""
    private var field = ""
    private var buffer = ""
    private var title = ""
    private var subTitle = ""
    private var desc = ""

    private init(keywords: KeywordSet) {
        self.keywords = keywords
    }

    static func read(_ file: URL, keywords: KeywordSet) throws -> GuideIndex {
        // Some panels send the guide gzip-compressed without saying so.
        if let handle = try? FileHandle(forReadingFrom: file) {
            let head = (try? handle.read(upToCount: 2)) ?? Data()
            try? handle.close()
            if head.count == 2, head[head.startIndex] == 0x1f, head[head.startIndex + 1] == 0x8b {
                throw URLError(.cannotDecodeContentData)
            }
        }
        guard let stream = InputStream(url: file) else { throw URLError(.cannotOpenFile) }
        let reader = XMLTVReader(keywords: keywords)
        let parser = XMLParser(stream: stream)
        parser.delegate = reader
        parser.shouldResolveExternalEntities = false
        let finished = parser.parse()
        // A guide cut short still has everything read up to that point.
        if !finished && reader.latestEnd == nil {
            throw parser.parserError ?? URLError(.cannotParseResponse)
        }
        return GuideIndex(programmes: reader.programmes, coverageEnd: reader.latestEnd)
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        switch elementName {
        case "programme":
            inProgramme = true
            channel = (attributeDict["channel"] ?? "").trimmingCharacters(in: .whitespaces).lowercased()
            startText = attributeDict["start"] ?? ""
            stopText = attributeDict["stop"] ?? ""
            title = ""
            subTitle = ""
            desc = ""
        case "title", "sub-title", "desc":
            if inProgramme {
                field = elementName
                buffer = ""
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if !field.isEmpty { buffer += string }
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if !field.isEmpty { buffer += String(decoding: CDATABlock, as: UTF8.self) }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        switch elementName {
        case "title":
            // Guides can list a title per language; the first is kept.
            if title.isEmpty { title = buffer }
            field = ""
        case "sub-title":
            if subTitle.isEmpty { subTitle = buffer }
            field = ""
        case "desc":
            if desc.isEmpty { desc = String(buffer.prefix(400)) }
            field = ""
        case "programme":
            finishProgramme()
            inProgramme = false
        default:
            break
        }
    }

    private func finishProgramme() {
        guard let end = XMLTVDate.parse(stopText) else { return }
        if latestEnd.map({ end > $0 }) ?? true { latestEnd = end }
        guard end > windowStart, !channel.isEmpty,
              let start = XMLTVDate.parse(startText), start < windowEnd else { return }
        let text = GuideText.normalize(title + " " + subTitle + " " + desc)
        guard keywords.matches(text) else { return }
        programmes.append(GuideProgramme(
            channel: channel,
            start: start,
            end: end,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            description: desc.trimmingCharacters(in: .whitespacesAndNewlines),
            text: text
        ))
    }
}

// MARK: - Finding the fixture on the user's channels

struct ChannelMatch: Identifiable {
    let channel: XtreamChannel
    let programme: XtreamEPGEntry
    let score: Int
    var bothTeams = false
    var id: Int { channel.id }
}

struct ChannelSearch {
    var matches: [ChannelMatch] = []
    /// Where the provider's guide ends, when the whole guide could be read.
    var guideEnds: Date?
}

enum ChannelFinder {
    /// Category / channel name fragments that suggest a sports channel.
    private static let sportWords = [
        "sport", "f1", "formula", "football", "soccer", "futebol", "futbol", "rugby", "nfl", "nba", "nhl", "mlb",
        "premier", "dazn", "tnt", "espn", "bein", "eleven", "viaplay", "arena", "golf",
        "racing", "motor", "laliga", "serie a", "bundesliga", "ligue", "uefa", "ppv", "event",
    ]

    /// Listings on air at the start time count (allowing for build-up shows).
    private static func isOnAir(_ begins: Date, _ ends: Date, at start: Date) -> Bool {
        begins <= start.addingTimeInterval(20 * 60) && ends >= start.addingTimeInterval(5 * 60)
    }

    /// Looks for the fixture in the provider's TV guide.
    /// - Parameters:
    ///   - teams: the followed teams; the guide is read once for all of them.
    ///   - preferred: favourite and folder channels, listed first among equal matches.
    ///   - force: download the guide again first.
    static func search(for fixture: Fixture, client: XtreamClient, teams: [FavouriteTeam],
                       hiddenCategories: Set<String>, hiddenChannels: Set<Int>,
                       preferred: Set<Int>, force: Bool = false) async -> ChannelSearch {
        guard let all = try? await XtreamCache.shared.liveStreams(client) else { return ChannelSearch() }
        let streams = all.filter { channel in
            if hiddenChannels.contains(channel.id) { return false }
            if let category = channel.categoryID, hiddenCategories.contains(category) { return false }
            return true
        }
        let matcher = FixtureMatcher(fixture: fixture)
        let start = fixture.guideTime
        let keywords = FixtureMatcher.indexKeywords(for: teams)

        if !keywords.isEmpty,
           let guide = try? await SportsGuide.shared.index(client, keywords: keywords, force: force) {
            var byGuideID: [String: [XtreamChannel]] = [:]
            for channel in streams {
                if let id = channel.epgChannelID?.lowercased() { byGuideID[id, default: []].append(channel) }
            }
            var best: [Int: ChannelMatch] = [:]
            for programme in guide.programmes where isOnAir(programme.start, programme.end, at: start) {
                guard let channels = byGuideID[programme.channel] else { continue }
                let (score, both) = matcher.score(normalized: programme.text, title: programme.title)
                guard score >= FixtureMatcher.threshold else { continue }
                let entry = XtreamEPGEntry(title: programme.title, description: programme.description,
                                           start: programme.start, end: programme.end)
                for channel in channels where score > (best[channel.id]?.score ?? 0) {
                    best[channel.id] = ChannelMatch(channel: channel, programme: entry, score: score, bothTeams: both)
                }
            }
            return ChannelSearch(matches: rank(Array(best.values), preferred: preferred), guideEnds: guide.coverageEnd)
        }

        // The whole guide couldn't be read: ask channel by channel instead.
        let matches = await searchChannelByChannel(streams: streams, client: client, matcher: matcher,
                                                   start: start, preferred: preferred)
        return ChannelSearch(matches: matches, guideEnds: nil)
    }

    /// Best first; favourites and folder channels first among equals, then HD.
    private static func rank(_ matches: [ChannelMatch], preferred: Set<Int>) -> [ChannelMatch] {
        func isHD(_ channel: XtreamChannel) -> Bool {
            let name = channel.name.lowercased()
            return name.contains("hd") || name.contains("fhd") || name.contains("4k") || name.contains("uhd")
        }
        return Array(matches.sorted { a, b in
            if a.score != b.score { return a.score > b.score }
            let pa = preferred.contains(a.channel.id), pb = preferred.contains(b.channel.id)
            if pa != pb { return pa }
            let ha = isHD(a.channel), hb = isHD(b.channel)
            if ha != hb { return ha }
            return a.channel.name.localizedCaseInsensitiveCompare(b.channel.name) == .orderedAscending
        }
        .prefix(30))
    }

    /// Channels that look like sports channels (by name or group), A–Z.
    static func sportsChannels(client: XtreamClient, hiddenCategories: Set<String>,
                               hiddenChannels: Set<Int>) async -> [XtreamChannel] {
        let cache = XtreamCache.shared
        guard let all = try? await cache.liveStreams(client) else { return [] }
        let categories = (try? await cache.liveCategories(client)) ?? []
        let sportCategories = Set(categories
            .filter { category in sportWords.contains { category.name.lowercased().contains($0) } }
            .map(\.id))
        return all
            .filter { channel in
                if hiddenChannels.contains(channel.id) { return false }
                if let category = channel.categoryID {
                    if hiddenCategories.contains(category) { return false }
                    if sportCategories.contains(category) { return true }
                }
                let name = channel.name.lowercased()
                return sportWords.contains { name.contains($0) }
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func searchChannelByChannel(streams: [XtreamChannel], client: XtreamClient,
                                               matcher: FixtureMatcher, start: Date,
                                               preferred: Set<Int>) async -> [ChannelMatch] {
        let cache = XtreamCache.shared
        let categories = (try? await cache.liveCategories(client)) ?? []
        let sportCategories = Set(categories
            .filter { category in sportWords.contains { category.name.lowercased().contains($0) } }
            .map(\.id))
        var candidates = streams.filter { channel in
            if preferred.contains(channel.id) { return true }
            if let category = channel.categoryID, sportCategories.contains(category) { return true }
            let name = channel.name.lowercased()
            return sportWords.contains { name.contains($0) }
        }
        // Keep the downloads bounded on very large playlists.
        if candidates.count > 400 { candidates = Array(candidates.prefix(400)) }

        var results: [ChannelMatch] = []
        var queue = candidates.makeIterator()
        await withTaskGroup(of: ChannelMatch?.self) { group in
            for _ in 0..<8 {
                guard let channel = queue.next() else { break }
                group.addTask { await match(channel, start: start, matcher: matcher, client: client) }
            }
            while let result = await group.next() {
                if let result { results.append(result) }
                if let channel = queue.next() {
                    group.addTask { await match(channel, start: start, matcher: matcher, client: client) }
                }
            }
        }
        return rank(results, preferred: preferred)
    }

    private static func match(_ channel: XtreamChannel, start: Date, matcher: FixtureMatcher,
                              client: XtreamClient) async -> ChannelMatch? {
        let guide = await XtreamCache.shared.fullEPG(client, streamID: channel.id)
        var best: ChannelMatch?
        for entry in guide {
            guard let begins = entry.start, let ends = entry.end, isOnAir(begins, ends, at: start) else { continue }
            let text = GuideText.normalize(entry.title + " " + entry.description)
            let (score, both) = matcher.score(normalized: text, title: entry.title)
            if score >= FixtureMatcher.threshold, score > (best?.score ?? 0) {
                best = ChannelMatch(channel: channel, programme: entry, score: score, bothTeams: both)
            }
        }
        return best
    }
}
