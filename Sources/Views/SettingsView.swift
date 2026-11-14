import SwiftUI

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 34) {
                    Text("Settings")
                        .font(.title2).bold()
                        .padding(.top, 20)

                    SettingsGroup("Media") {
                        SettingsRow("Connections", icon: "link") { AccountsSettingsView() }
                        SettingsRow("Live TV", icon: "antenna.radiowaves.left.and.right") { LiveTVSettingsView() }
                        SettingsRow("Streams", icon: "list.bullet.rectangle") { StreamSettingsView() }
                        SettingsRow("Content", icon: "arrow.triangle.2.circlepath") { ContentSettingsView() }
                    }

                    SettingsGroup("Playback") {
                        SettingsRow("Player", icon: "play.rectangle") { PlayerSettingsView() }
                        SettingsRow("Subtitles", icon: "captions.bubble") { SubtitleSettingsView() }
                    }

                    SettingsGroup("About") {
                        SettingsInfoRow("Version", icon: "info.circle", value: Self.version)
                        SettingsInfoRow("Player engine", icon: "cpu", value: "AetherEngine")
                    }
                }
                .frame(maxWidth: 1100)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 60)
            }
        }
    }

    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }
}

// MARK: - Grouped card components

/// A rounded card with a small uppercase header, like tvOS / NOWseen settings.
struct SettingsGroup<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption).bold()
                .foregroundStyle(.secondary)
                .padding(.horizontal, 28)
                .padding(.top, 20)
                .padding(.bottom, 6)
            VStack(spacing: 2) {
                content
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 34, style: .continuous).fill(.white.opacity(0.1)))
        .overlay(RoundedRectangle(cornerRadius: 34, style: .continuous).stroke(.white.opacity(0.08), lineWidth: 1))
    }
}

/// A row that opens a settings page.
struct SettingsRow<Destination: View>: View {
    let title: String
    let icon: String
    let destination: Destination

    init(_ title: String, icon: String, @ViewBuilder destination: () -> Destination) {
        self.title = title
        self.icon = icon
        self.destination = destination()
    }

    var body: some View {
        NavigationLink {
            destination
        } label: {
            SettingsRowLabel(title: title, icon: icon, trailing: nil, showsChevron: true)
        }
        .buttonStyle(SettingsRowStyle())
    }
}

/// A row that only shows a value.
struct SettingsInfoRow: View {
    let title: String
    let icon: String
    let value: String

    init(_ title: String, icon: String, value: String) {
        self.title = title
        self.icon = icon
        self.value = value
    }

    var body: some View {
        Button {} label: {
            SettingsRowLabel(title: title, icon: icon, trailing: value, showsChevron: false)
        }
        .buttonStyle(SettingsRowStyle())
    }
}

private struct SettingsRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

private struct SettingsRowLabel: View {
    let title: String
    let icon: String
    let trailing: String?
    let showsChevron: Bool
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        HStack(spacing: 22) {
            Image(systemName: icon)
                .font(.system(size: 30, weight: .semibold))
                .frame(width: 44)
            Text(title)
                .font(.system(size: 32, weight: .medium))
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.system(size: 28))
                    .opacity(0.7)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 26, weight: .bold))
                    .opacity(isFocused ? 1 : 0.6)
            }
        }
        .foregroundStyle(isFocused ? Color.black : Color.white)
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(isFocused ? Color.white : Color.clear)
        )
        .scaleEffect(isFocused ? 1.02 : 1)
        .shadow(color: .black.opacity(isFocused ? 0.3 : 0), radius: 14, y: 6)
        .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}

// MARK: - Accounts

struct AccountsSettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @State private var newAddonURL = ""
    @State private var addonStatus: String?
    @State private var xtreamStatus: String?

    var body: some View {
        Form {
            Section {
                SecureField("TMDB API Read Access Token", text: $settings.tmdbToken)
            } header: {
                Text("Metadata")
            } footer: {
                Text("Free from themoviedb.org → Settings → API. Use the long \"API Read Access Token\".")
            }

            Section {
                SecureField("Real-Debrid API key", text: $settings.realDebridKey)
            } header: {
                Text("Debrid")
            } footer: {
                Text("Used to resolve torrent-hash streams. Not needed if your addon already resolves through debrid.")
            }

            Section {
                ForEach(settings.addons) { addon in
                    Text(addon.name)
                        .contextMenu {
                            Button("Remove", role: .destructive) {
                                settings.addons.removeAll { $0 == addon }
                            }
                        }
                }
                TextField("Addon manifest URL", text: $newAddonURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Add addon") { Task { await addAddon() } }
                if let addonStatus {
                    Text(addonStatus).font(.caption)
                }
            } header: {
                Text("Stremio addons")
            } footer: {
                Text("Paste a manifest URL from any Stremio addon configured with your own debrid account. Long-press an addon to remove it.")
            }

            Section("IPTV (Xtream Codes)") {
                TextField("Server (http://host:port)", text: $settings.xtream.server)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Username", text: $settings.xtream.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Password", text: $settings.xtream.password)
                Button("Test login") { Task { await testXtream() } }
                if let xtreamStatus {
                    Text(xtreamStatus).font(.caption)
                }
            }
        }
        .navigationTitle("Connections")
    }

    private func addAddon() async {
        guard let url = StremioAddonClient.normalize(newAddonURL) else {
            addonStatus = "That doesn't look like a valid URL."
            return
        }
        guard !settings.addons.contains(where: { $0.manifestURL == url.absoluteString }) else {
            addonStatus = "Already added."
            return
        }
        addonStatus = "Checking…"
        do {
            let manifest = try await StremioAddonClient(manifestURL: url).manifest()
            settings.addons.append(AddonEntry(manifestURL: url.absoluteString, name: manifest.name))
            newAddonURL = ""
            addonStatus = "Added \(manifest.name)."
        } catch {
            addonStatus = "Couldn't load manifest: \(error.localizedDescription)"
        }
    }

    private func testXtream() async {
        xtreamStatus = "Checking…"
        do {
            xtreamStatus = try await settings.xtreamClient.authenticate()
        } catch {
            xtreamStatus = error.localizedDescription
        }
    }
}

// MARK: - Live TV

struct LiveTVSettingsView: View {
    @EnvironmentObject var settings: AppSettings

    private static let userAgentPresets: [Choice] = [
        Choice("", "Default"),
        Choice("VLC/3.0.21 LibVLC/3.0.21", "VLC"),
        Choice("TiviMate/5.1.6 (Android 12)", "TiviMate"),
        Choice("IPTVSmartersPro", "IPTV Smarters"),
    ]

    var body: some View {
        Form {
            Section {
                Picker("Stream format", selection: $settings.prefs.liveFormat) {
                    ForEach(LiveStreamFormat.allCases) { Text($0.label).tag($0) }
                }
                Picker("Channel switching", selection: $settings.prefs.channelSwitching) {
                    ForEach(ChannelSwitching.allCases) { Text($0.label).tag($0) }
                }
                Picker("Timeshift (pause & rewind)", selection: $settings.prefs.timeshiftMinutes) {
                    Text("Off").tag(0)
                    Text("30 minutes").tag(30)
                    Text("1 hour").tag(60)
                    Text("2 hours").tag(120)
                }
            } header: {
                Text("Streaming")
            } footer: {
                Text("Try MPEG-TS if channels fail on HLS. Stable switching starts slower but buffers more. Timeshift keeps recent video on the Apple TV so you can pause and rewind live channels.")
            }

            Section("Channel list") {
                Toggle("Show what's on now (EPG)", isOn: $settings.prefs.showEPG)
                Picker("Sort channels by", selection: $settings.prefs.channelSort) {
                    ForEach(ChannelSort.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Favourites at the top", isOn: $settings.prefs.favouritesFirst)
                Toggle("Remember last category", isOn: $settings.prefs.rememberLastCategory)
                NavigationLink("Show / hide categories") { HiddenCategoriesView() }
                Button("Clear favourites (\(settings.prefs.favouriteChannelIDs.count))", role: .destructive) {
                    settings.prefs.favouriteChannelIDs.removeAll()
                }
                .disabled(settings.prefs.favouriteChannelIDs.isEmpty)
            }

            Section {
                Picker("User agent", selection: $settings.prefs.iptvUserAgent) {
                    ForEach(Self.userAgentPresets) { preset in
                        Text(preset.name).tag(preset.code)
                    }
                    if !Self.userAgentPresets.contains(where: { $0.code == settings.prefs.iptvUserAgent }) {
                        Text("Custom").tag(settings.prefs.iptvUserAgent)
                    }
                }
                TextField("Custom user agent", text: $settings.prefs.iptvUserAgent)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("Provider compatibility")
            } footer: {
                Text("Some providers only allow certain players. Change this if your login works but channels don't.")
            }
        }
        .navigationTitle("Live TV")
    }
}

struct HiddenCategoriesView: View {
    @EnvironmentObject var settings: AppSettings
    @State private var categories: [XtreamCategory] = []
    @State private var error: String?

    var body: some View {
        Form {
            if let error {
                Text(error).foregroundStyle(.secondary)
            } else if categories.isEmpty {
                ProgressView()
            } else {
                Section {
                    Button("Show all") { settings.prefs.hiddenCategoryIDs.removeAll() }
                    Button("Hide all") { settings.prefs.hiddenCategoryIDs = Set(categories.map(\.id)) }
                }
                Section("Categories") {
                    ForEach(categories) { category in
                        Toggle(category.name, isOn: Binding(
                            get: { !settings.prefs.hiddenCategoryIDs.contains(category.id) },
                            set: { show in
                                if show {
                                    settings.prefs.hiddenCategoryIDs.remove(category.id)
                                } else {
                                    settings.prefs.hiddenCategoryIDs.insert(category.id)
                                }
                            }
                        ))
                    }
                }
            }
        }
        .navigationTitle("Categories")
        .task {
            guard settings.xtream.isConfigured else {
                error = "Add your Xtream login in Accounts first."
                return
            }
            do {
                categories = try await settings.xtreamClient.liveCategories()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

// MARK: - Player

struct PlayerSettingsView: View {
    @EnvironmentObject var settings: AppSettings

    private static let seekOptions = [5, 10, 15, 30, 60, 120]

    var body: some View {
        Form {
            Section("Audio language") {
                Picker("Preferred audio", selection: $settings.prefs.audioLanguage) {
                    ForEach(LanguageOptions.audio) { Text($0.name).tag($0.code) }
                }
            }

            Section("Remote") {
                Picker("Skip back (◀)", selection: $settings.prefs.seekBackSeconds) {
                    ForEach(Self.seekOptions, id: \.self) { Text("\($0) seconds").tag($0) }
                }
                Picker("Skip forward (▶)", selection: $settings.prefs.seekForwardSeconds) {
                    ForEach(Self.seekOptions, id: \.self) { Text("\($0) seconds").tag($0) }
                }
            }

            Section {
                Toggle("Match content (frame rate & HDR)", isOn: $settings.prefs.matchContent)
                Toggle("Upscale low-resolution video", isOn: $settings.prefs.upscaleLowResolution)
            } header: {
                Text("Video")
            } footer: {
                Text("Match content switches your TV to the video's frame rate and HDR mode, when Match Content is also on in the Apple TV's own settings.")
            }

            Section {
                Toggle("Dialogue boost", isOn: $settings.prefs.dialogueBoost)
                Toggle("Night mode (quieter loud scenes)", isOn: $settings.prefs.nightMode)
            } header: {
                Text("Audio")
            } footer: {
                Text("Either option decodes the audio on the Apple TV, so Dolby Atmos passthrough is off while they're on.")
            }
        }
        .navigationTitle("Player")
    }
}

// MARK: - Subtitles

struct SubtitleSettingsView: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Toggle("Turn subtitles on automatically", isOn: $settings.prefs.autoSubtitles)
                Picker("Subtitle language", selection: $settings.prefs.subtitleLanguage) {
                    ForEach(LanguageOptions.audio) { Text($0.name).tag($0.code) }
                }
                .disabled(!settings.prefs.autoSubtitles)
            } footer: {
                Text("When on, subtitles in this language are picked automatically if the video has them.")
            }

            Section("Appearance") {
                Picker("Size", selection: $settings.prefs.subtitleSize) {
                    ForEach(SubtitleSize.allCases) { Text($0.label).tag($0) }
                }
                Text("The quick brown fox jumps over the lazy dog")
                    .font(.system(size: settings.prefs.subtitleSize.points, weight: .semibold))
                    .shadow(color: .black, radius: 3)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            }
        }
        .navigationTitle("Subtitles")
    }
}

// MARK: - Streams

struct StreamSettingsView: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Picker("Maximum resolution", selection: $settings.prefs.maxResolution) {
                    ForEach(MaxResolution.allCases) { Text($0.label).tag($0) }
                }
                Picker("Sort streams", selection: $settings.prefs.streamSort) {
                    ForEach(StreamSort.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Play the first stream automatically", isOn: $settings.prefs.autoPlayFirstStream)
            } footer: {
                Text("Resolution is read from the addon's stream labels; streams without one are always shown.")
            }
        }
        .navigationTitle("Streams")
    }
}

// MARK: - Content

struct ContentSettingsView: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Picker("Language", selection: $settings.prefs.tmdbLanguage) {
                    ForEach(LanguageOptions.tmdb) { Text($0.name).tag($0.code) }
                }
                Picker("Region", selection: $settings.prefs.tmdbRegion) {
                    ForEach(LanguageOptions.regions) { Text($0.name).tag($0.code) }
                }
            } header: {
                Text("Catalogue")
            } footer: {
                Text("Language of titles and descriptions, and the region used for \"Now Playing\" and \"Upcoming\".")
            }
        }
        .navigationTitle("Content")
    }
}
