import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @State private var newAddonURL = ""
    @State private var addonStatus: String?
    @State private var xtreamStatus: String?

    var body: some View {
        NavigationStack {
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
            .navigationTitle("Settings")
        }
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
            xtreamStatus = try await XtreamClient(account: settings.xtream).authenticate()
        } catch {
            xtreamStatus = error.localizedDescription
        }
    }
}
