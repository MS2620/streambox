import SwiftUI

struct LiveTVView: View {
    @EnvironmentObject var settings: AppSettings

    @State private var categories: [XtreamCategory] = []
    @State private var selectedCategory: XtreamCategory?
    @State private var channels: [XtreamChannel] = []
    @State private var nowPlaying: [Int: String] = [:]
    @State private var error: String?
    @State private var playback: PlaybackRequest?

    private var client: XtreamClient { XtreamClient(account: settings.xtream) }

    var body: some View {
        Group {
            if !settings.xtream.isConfigured {
                ContentUnavailableView("Add your IPTV login", systemImage: "tv",
                                       description: Text("Open Settings and enter your Xtream Codes server, username and password."))
            } else if let error {
                ContentUnavailableView("Couldn't load channels", systemImage: "exclamationmark.triangle",
                                       description: Text(error))
            } else {
                HStack(alignment: .top, spacing: 40) {
                    List(categories) { category in
                        Button {
                            selectedCategory = category
                        } label: {
                            HStack {
                                Text(category.name).lineLimit(1)
                                Spacer()
                                if category == selectedCategory {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                    .frame(width: 520)

                    List(channels) { channel in
                        Button {
                            if let url = client.liveURL(for: channel) {
                                playback = PlaybackRequest(url: url, title: channel.name)
                            }
                        } label: {
                            HStack(spacing: 24) {
                                AsyncImage(url: channel.icon.flatMap { URL(string: $0) }) { image in
                                    image.resizable().aspectRatio(contentMode: .fit)
                                } placeholder: {
                                    Image(systemName: "tv").font(.title2)
                                }
                                .frame(width: 90, height: 56)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(channel.name).lineLimit(1)
                                    if let now = nowPlaying[channel.id] {
                                        Text(now).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                }
                            }
                        }
                        .task { await loadEPG(for: channel) }
                    }
                }
            }
        }
        .task(id: settings.xtream) { await loadCategories() }
        .task(id: selectedCategory) { await loadChannels() }
        .fullScreenCover(item: $playback) { request in
            PlayerView(request: request).ignoresSafeArea()
        }
    }

    private func loadCategories() async {
        guard settings.xtream.isConfigured else { return }
        do {
            categories = try await client.liveCategories()
            error = nil
            if selectedCategory == nil || !categories.contains(where: { $0 == selectedCategory }) {
                selectedCategory = categories.first
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func loadChannels() async {
        guard let selectedCategory else { return }
        channels = (try? await client.liveStreams(categoryID: selectedCategory.id)) ?? []
    }

    private func loadEPG(for channel: XtreamChannel) async {
        guard nowPlaying[channel.id] == nil else { return }
        guard let entries = try? await client.shortEPG(streamID: channel.id, limit: 2) else { return }
        let now = Date()
        let current = entries.first { ($0.start ?? .distantPast) <= now && now < ($0.end ?? .distantFuture) } ?? entries.first
        if let current { nowPlaying[channel.id] = "Now: \(current.title)" }
    }
}
