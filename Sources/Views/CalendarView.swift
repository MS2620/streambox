import SwiftUI

/// Upcoming (and the last week's) episodes for the series in My List,
/// grouped by day.
struct CalendarView: View {
    @EnvironmentObject var settings: AppSettings
    @State private var entries: [CalendarEntry] = []
    @State private var returning: [TMDBItem] = []
    @State private var loading = false

    struct CalendarEntry: Identifiable, Hashable {
        let show: TMDBItem
        let episode: TVEpisode
        let date: Date
        var id: String { "\(show.id)-\(episode.id)" }
    }

    private struct Day: Identifiable {
        let date: Date
        let entries: [CalendarEntry]
        var id: Date { date }
    }

    private var series: [TMDBItem] {
        settings.prefs.myList.filter { $0.kind == .tv }
    }

    private var days: [Day] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: entries) { calendar.startOfDay(for: $0.date) }
        return grouped.keys.sorted().map { date in
            Day(date: date, entries: grouped[date, default: []].sorted { $0.show.displayTitle < $1.show.displayTitle })
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 40) {
                    Text("Calendar")
                        .font(.title2).bold()
                        .padding(.horizontal, 90)
                        .padding(.top, 20)

                    if settings.tmdbToken.isEmpty {
                        message("Add your TMDB token in Settings → Connections to see release dates.")
                    } else if series.isEmpty {
                        message("Add series to My List (the ＋ My List button on a series) to see when their new episodes come out.")
                    } else if loading && entries.isEmpty && returning.isEmpty {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                    } else if entries.isEmpty && returning.isEmpty {
                        message("No new episodes coming up for the series in My List.")
                    }

                    ForEach(days) { day in
                        daySection(day)
                    }

                    if !returning.isEmpty {
                        RailView(title: "Returning — date not announced yet", items: returning)
                    }
                }
                .padding(.bottom, 60)
            }
            .navigationDestination(for: TMDBItem.self) { item in
                DetailView(item: item)
            }
            .task(id: series.map(\.id) + [settings.tmdbToken.count]) { await load() }
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 90)
            .padding(.top, 40)
    }

    private func daySection(_ day: Day) -> some View {
        let isPast = day.date < Calendar.current.startOfDay(for: Date())
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                Text(DayFormat.label(day.date))
                    .font(.title3).bold()
                if isPast {
                    Text("AIRED")
                        .font(.caption).bold()
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 90)

            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 44) {
                    ForEach(day.entries) { entry in
                        NavigationLink(value: entry.show) {
                            CalendarEpisodeCard(entry: entry)
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .padding(.horizontal, 90)
                .padding(.vertical, 30)
            }
            .scrollClipDisabled()
            .opacity(isPast ? 0.75 : 1)
        }
    }

    // MARK: - Loading

    private func load() async {
        guard !settings.tmdbToken.isEmpty, !series.isEmpty else {
            entries = []
            returning = []
            return
        }
        loading = true
        defer { loading = false }

        let tmdb = settings.tmdb
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let from = calendar.date(byAdding: .day, value: -7, to: today) ?? today
        let until = calendar.date(byAdding: .day, value: 90, to: today) ?? today

        var found: [CalendarEntry] = []
        var noDate: [TMDBItem] = []

        await withTaskGroup(of: ([CalendarEntry], TMDBItem?).self) { group in
            for show in series {
                group.addTask {
                    await Self.entries(for: show, tmdb: tmdb, from: from, until: until)
                }
            }
            for await (showEntries, returningShow) in group {
                found += showEntries
                if let returningShow { noDate.append(returningShow) }
            }
        }

        entries = found.sorted { $0.date < $1.date }
        returning = noDate.sorted { $0.displayTitle < $1.displayTitle }
    }

    /// Episodes of one series that air in the window, or the series itself
    /// if it's returning without a date.
    private static func entries(for show: TMDBItem, tmdb: TMDBClient,
                                from: Date, until: Date) async -> ([CalendarEntry], TMDBItem?) {
        guard let details = try? await tmdb.tvDetails(id: show.id) else { return ([], nil) }

        var seasons = Set<Int>()
        if let next = details.nextEpisodeToAir {
            seasons.insert(next.seasonNumber)
        }
        if let last = details.lastEpisodeToAir,
           let aired = DayFormat.parseDay(last.airDate), aired >= from {
            seasons.insert(last.seasonNumber)
        }

        var result: [CalendarEntry] = []
        for season in seasons.sorted() {
            let episodes = (try? await tmdb.episodes(tvID: show.id, season: season)) ?? []
            for episode in episodes {
                if let date = DayFormat.parseDay(episode.airDate), date >= from, date <= until {
                    result.append(CalendarEntry(show: show, episode: episode, date: date))
                }
            }
        }

        // A known next episode beyond the window still deserves a spot.
        if result.isEmpty, let next = details.nextEpisodeToAir,
           let date = DayFormat.parseDay(next.airDate) {
            result.append(CalendarEntry(show: show, episode: next, date: date))
        }

        let isReturningWithoutDate = result.isEmpty
            && details.nextEpisodeToAir == nil
            && details.status == "Returning Series"
        return (result, isReturningWithoutDate ? show : nil)
    }
}

private struct CalendarEpisodeCard: View {
    let entry: CalendarView.CalendarEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            AsyncImage(url: entry.episode.stillURL ?? entry.show.backdropURL) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                ZStack {
                    Color.gray.opacity(0.3)
                    Image(systemName: "tv").font(.largeTitle)
                }
            }
            .frame(width: 440, height: 248)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            Text(entry.show.displayTitle)
                .font(.callout).bold()
                .lineLimit(1)

            Text("S\(entry.episode.seasonNumber) E\(entry.episode.episodeNumber) · \(entry.episode.name ?? "Episode \(entry.episode.episodeNumber)")")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: 440, alignment: .leading)
    }
}
