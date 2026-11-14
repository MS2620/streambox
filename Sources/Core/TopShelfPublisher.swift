import Foundation
import TVServices

/// Builds what the Top Shelf shows and tells tvOS it changed.
@MainActor
enum TopShelfPublisher {
    private static var lastPublished: TopShelfSnapshot?

    static func publish() {
        var snapshot = TopShelfSnapshot()

        snapshot.live = LiveScores.shared.liveFixtures.prefix(4).map { fixture in
            let score = LiveScores.shared.score(for: fixture)
            let title = score.map { "\(fixture.title.replacingOccurrences(of: " v ", with: " \($0.line) ")) · \($0.clock)" }
                ?? "\(fixture.title) · LIVE"
            return TopShelfItem(id: "match-\(fixture.id)", title: title,
                                imageURL: fixture.home?.logo,
                                link: "streambox://match?id=\(encode(fixture.id))")
        }

        snapshot.continueWatching = WatchHistory.shared.latestPerTitle
            .filter { $0.isResumable && !$0.context.imdbID.isEmpty }
            .prefix(10)
            .map { entry in
                let title = [entry.item.displayTitle, entry.episodeLabel].compactMap { $0 }.joined(separator: " · ")
                return TopShelfItem(id: "resume-\(entry.id)", title: title,
                                    imageURL: entry.item.backdropURL?.absoluteString,
                                    link: "streambox://resume?key=\(encode(entry.id))",
                                    progress: entry.fraction)
            }

        let liveIDs = Set(LiveScores.shared.liveFixtures.map(\.id))
        snapshot.upcoming = LiveScores.shared.upcomingFixtures
            .filter { !liveIDs.contains($0.id) }
            .prefix(6)
            .map { fixture in
                let time = fixture.guideTime
                // A race weekend names the session: "Qualifying · Tomorrow 04:00".
                let session = fixture.sessions.first { $0.date == time }?.name
                let when = [session, "\(DayFormat.label(time)) \(DayFormat.time(time))"].compactMap { $0 }.joined(separator: " · ")
                return TopShelfItem(id: "upcoming-\(fixture.id)", title: "\(fixture.title) · \(when)",
                                    imageURL: fixture.home?.logo,
                                    link: "streambox://match?id=\(encode(fixture.id))")
            }

        // Only bother tvOS when something actually changed.
        guard snapshot.live != lastPublished?.live || snapshot.continueWatching != lastPublished?.continueWatching
                || snapshot.upcoming != lastPublished?.upcoming else { return }
        lastPublished = snapshot
        TopShelfStore.write(snapshot)
        TVTopShelfContentProvider.topShelfContentDidChange()
    }

    private static func encode(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? text
    }
}

/// Where a streambox:// link leads.
enum DeepLink: Identifiable {
    case resume(StreamTarget)
    case match(Fixture)

    var id: String {
        switch self {
        case .resume(let target): return "resume-\(target.id)"
        case .match(let fixture): return "match-\(fixture.id)"
        }
    }

    /// streambox://resume?key=… and streambox://match?id=…
    @MainActor
    init?(url: URL) {
        guard url.scheme == "streambox",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return nil }
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        switch url.host {
        case "resume":
            guard let key = value("key"), let entry = WatchHistory.shared.entries[key] else { return nil }
            let item = entry.item
            let imdbID = entry.context.imdbID
            if let season = entry.context.season, let episode = entry.context.episode {
                self = .resume(.episode(item: item, imdbID: imdbID, season: season, episode: episode,
                                        name: entry.context.episodeName, overview: nil))
            } else {
                self = .resume(.movie(item: item, imdbID: imdbID))
            }
        case "match":
            guard let id = value("id"), let fixture = LiveScores.shared.fixture(id: id) else { return nil }
            self = .match(fixture)
        default:
            return nil
        }
    }
}
