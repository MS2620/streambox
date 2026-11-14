import SwiftUI

// MARK: - Sports tab

struct SportsView: View {
    @EnvironmentObject var settings: AppSettings
    @State private var fixtures: [Fixture] = []
    @State private var loading = false
    @State private var selected: Fixture?

    private struct Day: Identifiable {
        let date: Date
        let fixtures: [Fixture]
        var id: Date { date }
    }

    private var favourites: [FavouriteTeam] { settings.prefs.favouriteTeams }

    private var days: [Day] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: fixtures) { calendar.startOfDay(for: $0.date) }
        return grouped.keys.sorted().map { date in
            Day(date: date, fixtures: grouped[date, default: []].sorted { $0.date < $1.date })
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 40) {
                    HStack {
                        Text("Sports").font(.title2).bold()
                        Spacer()
                        NavigationLink {
                            TeamsManagerView()
                        } label: {
                            Label("My Teams", systemImage: "star")
                        }
                    }
                    .padding(.horizontal, 90)
                    .padding(.top, 20)

                    if favourites.isEmpty {
                        message("Choose your teams with My Teams to see when they next play or race.")
                    } else if loading && fixtures.isEmpty {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                    } else if fixtures.isEmpty {
                        message("No upcoming fixtures found for your teams in the next 60 days.")
                    }

                    ForEach(days) { day in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(DayFormat.label(day.date))
                                .font(.title3).bold()
                                .padding(.horizontal, 90)
                            ScrollView(.horizontal) {
                                LazyHStack(spacing: 40) {
                                    ForEach(day.fixtures) { fixture in
                                        Button {
                                            selected = fixture
                                        } label: {
                                            FixtureCard(fixture: fixture)
                                        }
                                        .buttonStyle(.card)
                                    }
                                }
                                .padding(.horizontal, 90)
                                .padding(.vertical, 30)
                            }
                            .scrollClipDisabled()
                        }
                    }
                }
                .padding(.bottom, 60)
            }
            .task(id: favourites) { await load() }
            .sheet(item: $selected) { fixture in
                FixtureDetailView(fixture: fixture)
            }
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 90)
            .padding(.top, 40)
    }

    private func load() async {
        let teams = favourites
        guard !teams.isEmpty else {
            fixtures = []
            return
        }
        loading = true
        defer { loading = false }

        let espn = ESPNClient()
        let f1Teams = teams.filter(\.isF1).map(\.name)
        var found: [Fixture] = []

        await withTaskGroup(of: [Fixture].self) { group in
            for team in teams where !team.isF1 {
                group.addTask { await espn.upcomingFixtures(for: team) }
            }
            if !f1Teams.isEmpty {
                group.addTask {
                    guard let race = try? await F1Client().nextRace(followed: f1Teams) else { return [] }
                    return [race]
                }
            }
            for await list in group { found += list }
        }

        // Two followed teams in the same match: show it once, naming both.
        var merged: [String: Fixture] = [:]
        for fixture in found {
            if var existing = merged[fixture.id] {
                existing.followed = Array(Set(existing.followed + fixture.followed)).sorted()
                merged[fixture.id] = existing
            } else {
                merged[fixture.id] = fixture
            }
        }
        let horizon = Date().addingTimeInterval(60 * 86_400)
        fixtures = merged.values
            .filter { $0.date <= horizon }
            .sorted { $0.date < $1.date }
    }
}

// MARK: - Cards

private struct TeamBadge: View {
    let side: Fixture.Side?

    var body: some View {
        VStack(spacing: 10) {
            AsyncImage(url: side?.logo.flatMap { URL(string: $0) }) { image in
                image.resizable().aspectRatio(contentMode: .fit)
            } placeholder: {
                Image(systemName: "shield").font(.largeTitle).foregroundStyle(.secondary)
            }
            .frame(width: 80, height: 80)
            Text(side?.name ?? "TBC")
                .font(.caption).bold()
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(width: 200)
    }
}

private struct FixtureCard: View {
    let fixture: Fixture

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(fixture.competition)
                .font(.caption).bold()
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if fixture.isRace {
                HStack(spacing: 14) {
                    Image(systemName: "flag.checkered").font(.title2)
                    Text(fixture.title).font(.headline).lineLimit(2)
                }
                if let subtitle = fixture.subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            } else {
                HStack(alignment: .top, spacing: 8) {
                    TeamBadge(side: fixture.home)
                    Text("v").font(.headline).foregroundStyle(.secondary).padding(.top, 28)
                    TeamBadge(side: fixture.away)
                }
                .frame(maxWidth: .infinity)
            }

            Spacer(minLength: 0)

            HStack {
                Label(DayFormat.time(fixture.isRace ? fixture.guideTime : fixture.date), systemImage: "clock")
                    .font(.callout).bold()
                Spacer()
                if fixture.isRace, let next = fixture.sessions.first(where: { $0.date == fixture.guideTime }) {
                    Text(next.name).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(26)
        .frame(width: 560, height: 320, alignment: .topLeading)
    }
}

// MARK: - Fixture detail + TV guide matching

struct FixtureDetailView: View {
    @EnvironmentObject var settings: AppSettings
    let fixture: Fixture

    @State private var matches: [ChannelMatch] = []
    @State private var searching = false
    @State private var searched = false
    @State private var playback: PlaybackRequest?

    /// Providers' guides rarely go more than about a week ahead.
    private var tooFarAhead: Bool {
        fixture.guideTime > Date().addingTimeInterval(8 * 86_400)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text(fixture.competition.uppercased())
                    .font(.caption).bold()
                    .foregroundStyle(.secondary)
                Text(fixture.title)
                    .font(.system(size: 56, weight: .bold))
                    .lineLimit(2)
                if let subtitle = fixture.subtitle {
                    Text(subtitle).foregroundStyle(.secondary)
                }
                Text(fixture.date.formatted(date: .complete, time: .shortened))
                    .font(.headline)
                if !fixture.followed.isEmpty {
                    Label("Following: " + fixture.followed.joined(separator: ", "), systemImage: "star.fill")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                if fixture.isRace {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Weekend schedule").font(.title3).bold()
                        ForEach(fixture.sessions, id: \.self) { session in
                            HStack {
                                Text(session.name)
                                Spacer()
                                Text(session.date.formatted(.dateTime.weekday(.abbreviated).day().month().hour().minute()))
                                    .foregroundStyle(session.date < Date() ? Color.secondary : Color.primary)
                            }
                            .font(.callout)
                        }
                    }
                    .frame(maxWidth: 1000)
                }

                if !fixture.broadcasts.isEmpty {
                    Text("Listed broadcasters: " + fixture.broadcasts.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()

                Text("Watch on your channels").font(.title3).bold()
                guideSection
            }
            .padding(80)
        }
        .task { await search() }
        .fullScreenCover(item: $playback) { request in
            PlayerView(request: request).ignoresSafeArea()
        }
    }

    @ViewBuilder
    private var guideSection: some View {
        if !settings.xtream.isConfigured {
            Text("Add your IPTV login in Settings → Connections to find this in your TV guide.")
                .foregroundStyle(.secondary)
        } else if tooFarAhead {
            Text("It's not in your TV guide yet — guides usually only cover the next few days. Come back closer to the time.")
                .foregroundStyle(.secondary)
        } else if searching || !searched {
            ProgressView("Searching your TV guide…")
        } else if matches.isEmpty {
            Text("Couldn't find this in your TV guide yet. Listings can appear late — come back later.")
                .foregroundStyle(.secondary)
        } else {
            VStack(spacing: 12) {
                ForEach(Array(matches.enumerated()), id: \.element.id) { index, match in
                    Button {
                        play(index)
                    } label: {
                        HStack(spacing: 24) {
                            AsyncImage(url: match.channel.icon.flatMap { URL(string: $0) }) { image in
                                image.resizable().aspectRatio(contentMode: .fit)
                            } placeholder: {
                                Image(systemName: "tv").font(.title2)
                            }
                            .frame(width: 110, height: 60)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(match.channel.name).font(.headline).lineLimit(1)
                                Text(programmeLine(match.programme))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: "play.fill")
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
        }
    }

    private func programmeLine(_ entry: XtreamEPGEntry) -> String {
        let times = [entry.start, entry.end].compactMap { $0 }.map(DayFormat.time).joined(separator: "–")
        return times.isEmpty ? entry.title : "\(times)  \(entry.title)"
    }

    private func search() async {
        guard settings.xtream.isConfigured, !tooFarAhead, !searched else { return }
        searching = true
        matches = await ChannelFinder.matches(for: fixture, client: settings.xtreamClient)
        searching = false
        searched = true
    }

    private func play(_ index: Int) {
        let client = settings.xtreamClient
        let channels = matches.map(\.channel)
        let channel = channels[index]
        guard let url = client.liveURL(for: channel, format: settings.prefs.liveFormat) else { return }
        playback = PlaybackRequest(
            url: url,
            title: channel.name,
            artworkURL: channel.icon.flatMap { URL(string: $0) },
            sourceName: fixture.competition,
            isLive: true,
            httpHeaders: client.requestHeaders,
            live: LiveContext(channels: channels, index: index)
        )
    }
}

// MARK: - Choosing teams

struct TeamsManagerView: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        List {
            Section {
                if settings.prefs.favouriteTeams.isEmpty {
                    Text("No teams yet. Add some below.").foregroundStyle(.secondary)
                }
                ForEach(settings.prefs.favouriteTeams) { team in
                    TeamRow(name: team.name, detail: team.leagueName, logo: team.logo, isFavourite: true)
                        .contextMenu {
                            Button("Remove", role: .destructive) {
                                settings.prefs.favouriteTeams.removeAll { $0.id == team.id }
                            }
                        }
                }
            } header: {
                Text("My Teams")
            } footer: {
                Text("Long-press a team to remove it.")
            }

            Section("Add teams") {
                NavigationLink {
                    FootballLeaguesView()
                } label: {
                    Label("Football", systemImage: "soccerball")
                }
                NavigationLink {
                    F1TeamsView()
                } label: {
                    Label("Formula 1", systemImage: "flag.checkered")
                }
                NavigationLink {
                    LeagueListView(title: "Rugby", leagues: SportsCatalog.rugby)
                } label: {
                    Label("Rugby", systemImage: "figure.rugby")
                }
                ForEach(SportsCatalog.us) { league in
                    NavigationLink {
                        TeamPickerView(league: league)
                    } label: {
                        Label(league.name, systemImage: "sportscourt")
                    }
                }
            }
        }
        .navigationTitle("My Teams")
    }
}

private struct TeamRow: View {
    let name: String
    let detail: String?
    let logo: String?
    let isFavourite: Bool

    var body: some View {
        HStack(spacing: 20) {
            AsyncImage(url: logo.flatMap { URL(string: $0) }) { image in
                image.resizable().aspectRatio(contentMode: .fit)
            } placeholder: {
                Image(systemName: "shield").foregroundStyle(.secondary)
            }
            .frame(width: 50, height: 50)
            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                if let detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: isFavourite ? "star.fill" : "star")
                .foregroundStyle(isFavourite ? Color.yellow : Color.secondary)
        }
    }
}

private struct FootballLeaguesView: View {
    @State private var leagues: [SportLeague] = []
    @State private var error: String?

    var body: some View {
        Group {
            if let error {
                Text(error).foregroundStyle(.secondary)
            } else if leagues.isEmpty {
                ProgressView()
            } else {
                LeagueListView(title: "Football", leagues: leagues)
            }
        }
        .task {
            do {
                leagues = try await ESPNClient().footballLeagues()
                if leagues.isEmpty { error = "No leagues found." }
            } catch {
                self.error = "Couldn't load leagues: \(error.localizedDescription)"
            }
        }
    }
}

private struct LeagueListView: View {
    let title: String
    let leagues: [SportLeague]

    var body: some View {
        List(leagues) { league in
            NavigationLink(league.name) {
                TeamPickerView(league: league)
            }
        }
        .navigationTitle(title)
    }
}

private struct TeamPickerView: View {
    @EnvironmentObject var settings: AppSettings
    let league: SportLeague
    @State private var teams: [ESPNTeam] = []
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        List {
            if loading {
                ProgressView()
            } else if let error {
                Text(error).foregroundStyle(.secondary)
            } else if teams.isEmpty {
                Text("No teams listed for this competition right now.").foregroundStyle(.secondary)
            }
            ForEach(teams, id: \.id) { team in
                let favourite = isFavourite(team)
                Button {
                    toggle(team)
                } label: {
                    TeamRow(name: team.displayName, detail: nil, logo: team.logoURL, isFavourite: favourite)
                }
            }
        }
        .navigationTitle(league.name)
        .task {
            do {
                teams = try await ESPNClient().teams(in: league)
            } catch {
                self.error = "Couldn't load teams: \(error.localizedDescription)"
            }
            loading = false
        }
    }

    private func favouriteID(_ team: ESPNTeam) -> String {
        "\(league.sport)/\(league.slug)/\(team.id)"
    }

    private func isFavourite(_ team: ESPNTeam) -> Bool {
        settings.prefs.favouriteTeams.contains { $0.id == favouriteID(team) }
    }

    private func toggle(_ team: ESPNTeam) {
        if isFavourite(team) {
            settings.prefs.favouriteTeams.removeAll { $0.id == favouriteID(team) }
        } else {
            settings.prefs.favouriteTeams.append(FavouriteTeam(
                sport: league.sport, league: league.slug, leagueName: league.name,
                teamID: team.id, name: team.displayName, logo: team.logoURL
            ))
        }
    }
}

private struct F1TeamsView: View {
    @EnvironmentObject var settings: AppSettings
    @State private var constructors: [F1Constructor] = []
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        List {
            Section {
                if loading {
                    ProgressView()
                } else if let error {
                    Text(error).foregroundStyle(.secondary)
                }
                ForEach(constructors) { constructor in
                    let favourite = isFavourite(constructor)
                    Button {
                        toggle(constructor)
                    } label: {
                        TeamRow(name: constructor.name, detail: nil, logo: nil, isFavourite: favourite)
                    }
                }
            } footer: {
                Text("Following any team shows each race weekend in Sports.")
            }
        }
        .navigationTitle("Formula 1")
        .task {
            do {
                constructors = try await F1Client().constructors()
            } catch {
                self.error = "Couldn't load teams: \(error.localizedDescription)"
            }
            loading = false
        }
    }

    private func isFavourite(_ constructor: F1Constructor) -> Bool {
        settings.prefs.favouriteTeams.contains { $0.isF1 && $0.teamID == constructor.id }
    }

    private func toggle(_ constructor: F1Constructor) {
        if isFavourite(constructor) {
            settings.prefs.favouriteTeams.removeAll { $0.isF1 && $0.teamID == constructor.id }
        } else {
            settings.prefs.favouriteTeams.append(FavouriteTeam(
                sport: "f1", league: "f1", leagueName: "Formula 1",
                teamID: constructor.id, name: constructor.name, logo: nil
            ))
        }
    }
}
