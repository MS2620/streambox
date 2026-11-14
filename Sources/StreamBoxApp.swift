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
            CatalogView(hero: Catalog.homeHero, sections: Catalog.home, showsFavouriteChannels: true)
                .tabItem { Label("Home", systemImage: "house") }
            CatalogView(hero: Catalog.moviesHero, sections: Catalog.movies)
                .tabItem { Label("Movies", systemImage: "film") }
            CatalogView(hero: Catalog.seriesHero, sections: Catalog.series)
                .tabItem { Label("Series", systemImage: "play.tv") }
            LiveTVView()
                .tabItem { Label("Live TV", systemImage: "antenna.radiowaves.left.and.right") }
            SearchView()
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}
