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
        }
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            Tab("Home", systemImage: "house") {
                CatalogView(hero: Catalog.homeHero, sections: Catalog.home, showsFavouriteChannels: true)
            }
            Tab("Movies", systemImage: "film") {
                CatalogView(hero: Catalog.moviesHero, sections: Catalog.movies, myListKind: .movie)
            }
            Tab("Series", systemImage: "play.tv") {
                CatalogView(hero: Catalog.seriesHero, sections: Catalog.series, myListKind: .tv)
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
            // The search role lets tvOS lay out the keyboard and results
            // itself and keeps the tab bar reachable from search.
            Tab("Search", systemImage: "magnifyingglass", role: .search) {
                SearchView()
            }
            Tab("Settings", systemImage: "gearshape") {
                SettingsView()
            }
        }
    }
}
