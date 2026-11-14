import SwiftUI

private struct CategoryEntry: Identifiable, Hashable {
    let id: String
    let name: String
}

struct LiveTVView: View {
    @EnvironmentObject var settings: AppSettings

    @State private var categories: [XtreamCategory] = []
    @State private var selectedID: String?
    @State private var channels: [XtreamChannel] = []
    @State private var nowPlaying: [Int: String] = [:]
    @State private var loadingChannels = false
    @State private var error: String?
    @State private var playback: PlaybackRequest?

    private static let favouritesID = "__favourites"

    private var client: XtreamClient { settings.xtreamClient }
    private var prefs: Preferences { settings.prefs }

    /// Visible categories, with a Favourites entry when there are any.
    private var visibleCategories: [CategoryEntry] {
        let shown = categories
            .filter { !prefs.hiddenCategoryIDs.contains($0.id) }
            .map { CategoryEntry(id: $0.id, name: $0.name) }
        guard !prefs.favouriteChannelIDs.isEmpty else { return shown }
        let favourites = CategoryEntry(id: Self.favouritesID, name: "★ Favourites")
        return prefs.favouritesFirst ? [favourites] + shown : shown + [favourites]
    }

    private var sortedChannels: [XtreamChannel] {
        switch prefs.channelSort {
        case .server:
            return channels
        case .number:
            return channels.sorted { ($0.number ?? .max) < ($1.number ?? .max) }
        case .name:
            return channels.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    var body: some View {
        Group {
            if !settings.xtream.isConfigured {
                ContentUnavailableView("Add your IPTV login", systemImage: "tv",
                                       description: Text("Open Settings → Accounts and enter your Xtream Codes server, username and password."))
            } else if let error {
                ContentUnavailableView("Couldn't load channels", systemImage: "exclamationmark.triangle",
                                       description: Text(error))
            } else {
                HStack(alignment: .top, spacing: 40) {
                    categoryList.frame(width: 520)
                    channelList
                }
            }
        }
        .task(id: settings.xtream) { await loadCategories() }
        .task(id: selectedID) { await loadChannels() }
        .onChange(of: prefs.favouriteChannelIDs) { _, _ in
            if selectedID == Self.favouritesID { Task { await loadChannels() } }
        }
        .fullScreenCover(item: $playback) { request in
            PlayerView(request: request).ignoresSafeArea()
        }
    }

    private var categoryList: some View {
        List(visibleCategories) { category in
            Button {
                selectedID = category.id
                if prefs.rememberLastCategory { settings.prefs.lastCategoryID = category.id }
            } label: {
                HStack {
                    Text(category.name).lineLimit(1)
                    Spacer()
                    if category.id == selectedID { Image(systemName: "checkmark") }
                }
            }
        }
    }

    private var channelList: some View {
        List {
            if loadingChannels && channels.isEmpty {
                ProgressView()
            } else if channels.isEmpty {
                Text(selectedID == Self.favouritesID
                     ? "No favourites yet. Long-press a channel to add it."
                     : "No channels in this category.")
                    .foregroundStyle(.secondary)
            }
            ForEach(sortedChannels) { channel in
                Button {
                    play(channel)
                } label: {
                    channelRow(channel)
                }
                .contextMenu {
                    if prefs.favouriteChannelIDs.contains(channel.id) {
                        Button("Remove from Favourites", systemImage: "star.slash") {
                            settings.prefs.favouriteChannelIDs.remove(channel.id)
                        }
                    } else {
                        Button("Add to Favourites", systemImage: "star") {
                            settings.prefs.favouriteChannelIDs.insert(channel.id)
                        }
                    }
                }
                .task {
                    if prefs.showEPG { await loadEPG(for: channel) }
                }
            }
        }
    }

    private func channelRow(_ channel: XtreamChannel) -> some View {
        HStack(spacing: 24) {
            if prefs.channelSort == .number, let number = channel.number {
                Text("\(number)")
                    .font(.caption).monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 70, alignment: .trailing)
            }
            AsyncImage(url: channel.icon.flatMap { URL(string: $0) }) { image in
                image.resizable().aspectRatio(contentMode: .fit)
            } placeholder: {
                Image(systemName: "tv").font(.title2)
            }
            .frame(width: 90, height: 56)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(channel.name).lineLimit(1)
                    if prefs.favouriteChannelIDs.contains(channel.id) {
                        Image(systemName: "star.fill").font(.caption).foregroundStyle(.yellow)
                    }
                }
                if prefs.showEPG, let now = nowPlaying[channel.id] {
                    Text(now).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
    }

    // MARK: - Actions

    private func play(_ channel: XtreamChannel) {
        guard let url = client.liveURL(for: channel, format: prefs.liveFormat) else { return }
        let list = sortedChannels
        let index = list.firstIndex(of: channel) ?? 0
        playback = PlaybackRequest(
            url: url,
            title: channel.name,
            artworkURL: channel.icon.flatMap { URL(string: $0) },
            sourceName: visibleCategories.first(where: { $0.id == selectedID })?.name,
            isLive: true,
            httpHeaders: client.requestHeaders,
            live: LiveContext(channels: list, index: index)
        )
    }

    private func loadCategories() async {
        guard settings.xtream.isConfigured else { return }
        do {
            categories = try await client.liveCategories()
            error = nil
            let ids = visibleCategories.map(\.id)
            if let selectedID, ids.contains(selectedID) { return }
            if prefs.rememberLastCategory, let last = prefs.lastCategoryID, ids.contains(last) {
                selectedID = last
            } else {
                selectedID = ids.first
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func loadChannels() async {
        guard let selectedID else { return }
        loadingChannels = true
        defer { loadingChannels = false }
        channels = []
        if selectedID == Self.favouritesID {
            let all = (try? await client.liveStreams(categoryID: nil)) ?? []
            channels = all.filter { prefs.favouriteChannelIDs.contains($0.id) }
        } else {
            channels = (try? await client.liveStreams(categoryID: selectedID)) ?? []
        }
    }

    private func loadEPG(for channel: XtreamChannel) async {
        guard nowPlaying[channel.id] == nil else { return }
        guard let entries = try? await client.shortEPG(streamID: channel.id, limit: 2) else { return }
        let now = Date()
        let current = entries.first { ($0.start ?? .distantPast) <= now && now < ($0.end ?? .distantFuture) } ?? entries.first
        if let current { nowPlaying[channel.id] = "Now: \(current.title)" }
    }
}
