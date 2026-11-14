import SwiftUI

@main
struct StreamBoxApp: App {
    @StateObject private var settings = AppSettings()
    @StateObject private var player = PlayerEngineHolder()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
                .environmentObject(player)
                .preferredColorScheme(.dark)
        }
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            Tab("Home", systemImage: "house") {
                CatalogView(mode: .home)
            }
            Tab("Movies", systemImage: "film") {
                CatalogView(mode: .movies)
            }
            Tab("Series", systemImage: "play.tv") {
                CatalogView(mode: .series)
            }
            Tab("Live TV", systemImage: "antenna.radiowaves.left.and.right") {
                LiveTVView()
            }
            Tab("Sports", systemImage: "sportscourt") {
                SportsView()
            }
            Tab("Calendar", systemImage: "calendar") {
                CalendarView()
            }
            Tab("Search", systemImage: "magnifyingglass", role: .search) {
                SearchView()
            }
            Tab("Settings", systemImage: "gearshape") {
                SettingsView()
            }
        }
    }
}
