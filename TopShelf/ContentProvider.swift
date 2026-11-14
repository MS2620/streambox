import TVServices

/// Fills the Top Shelf with live games for the user's teams and Continue Watching,
/// from what StreamBox last published.
final class ContentProvider: TVTopShelfContentProvider {
    override func loadTopShelfContent(completionHandler: @escaping (TVTopShelfContent?) -> Void) {
        guard let snapshot = TopShelfStore.read(), !snapshot.isEmpty else {
            completionHandler(nil)
            return
        }
        var sections: [TVTopShelfItemCollection<TVTopShelfSectionedItem>] = []
        if !snapshot.live.isEmpty {
            let section = TVTopShelfItemCollection(items: snapshot.live.map(Self.item))
            section.title = "Live now"
            sections.append(section)
        }
        if !snapshot.continueWatching.isEmpty {
            let section = TVTopShelfItemCollection(items: snapshot.continueWatching.map(Self.item))
            section.title = "Continue Watching"
            sections.append(section)
        }
        completionHandler(TVTopShelfSectionedContent(sections: sections))
    }

    private static func item(_ source: TopShelfItem) -> TVTopShelfSectionedItem {
        let item = TVTopShelfSectionedItem(identifier: source.id)
        item.title = source.title
        item.imageShape = .hdtv
        if let string = source.imageURL, let url = URL(string: string) {
            item.setImageURL(url, for: .screenScale1x)
            item.setImageURL(url, for: .screenScale2x)
        }
        if let url = URL(string: source.link) {
            item.displayAction = TVTopShelfAction(url: url)
            item.playAction = TVTopShelfAction(url: url)
        }
        if let progress = source.progress {
            item.playbackProgress = progress
        }
        return item
    }
}
