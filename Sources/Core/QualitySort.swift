import Foundation

/// The picture quality a provider writes in a channel's name.
enum ChannelQuality: String, CaseIterable, Codable {
    case uhd, fhd, hd, sd

    /// Shown in folder names: "UK | Sports FHD".
    var label: String {
        switch self {
        case .uhd: "4K"
        case .fhd: "FHD"
        case .hd: "HD"
        case .sd: "SD"
        }
    }
}

/// Settings › Content › Sort by quality: chosen provider groups are split into 4K, FHD, HD
/// and SD folders by the quality in each channel's name, and the names in those groups are
/// tidied (the country tag at the start and the quality words removed) everywhere.
enum QualitySort {
    /// The chosen groups of the IPTV account in use. Set by AppSettings whenever its
    /// preferences change, so the channel cache can tidy names without asking the main actor.
    nonisolated(unsafe) static var activeCategoryIDs: Set<String> = []

    // MARK: Folders

    private static let separator = "#quality="

    /// The Live TV id of one quality folder of a group.
    static func folderID(category: String, quality: ChannelQuality) -> String {
        category + separator + quality.rawValue
    }

    /// The group and quality a folder id stands for, or nil for any other id.
    static func parseFolderID(_ id: String) -> (category: String, quality: ChannelQuality)? {
        guard let range = id.range(of: separator),
              let quality = ChannelQuality(rawValue: String(id[range.upperBound...])) else { return nil }
        return (String(id[..<range.lowerBound]), quality)
    }

    /// The group a Live TV id belongs to, for locks: a quality folder counts as its group.
    static func baseCategory(of id: String) -> String {
        parseFolderID(id)?.category ?? id
    }

    /// "UK | Sports FHD · Now: Qualifying", leaving out missing parts; nil when nothing is left.
    static func joined(_ parts: [String?]) -> String? {
        let text = parts.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        return text.isEmpty ? nil : text
    }

    // MARK: Names

    /// "UK | Sports" → "UK"; nil when the group name doesn't start with a short tag.
    static func countryTag(ofGroup name: String) -> String? {
        let pattern = #"^\s*\|?\s*([A-Za-z]{2,3})\s*[|:]"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)),
              let range = Range(match.range(at: 1), in: name) else { return nil }
        return String(name[range])
    }

    private static let qualityWord = try! NSRegularExpression(
        pattern: #"(?<![A-Za-z0-9])(4K|UHD|FHD|HD\+|HD|SD|HEVC)(?![A-Za-z0-9])"#,
        options: [.caseInsensitive])

    /// The channel's name without the country tag and quality words, and the quality its name
    /// gives (no quality word means SD; HEVC alone doesn't count).
    /// `groupTag` is the group's own tag ("UK"); without one, only a "XX |" style tag is removed.
    static func tidy(_ name: String, groupTag: String?) -> (name: String, quality: ChannelQuality) {
        var text = name

        // The country tag at the start: "UK | ", "UK: ", "|UK| ".
        if let tag = groupTag {
            let escaped = NSRegularExpression.escapedPattern(for: tag)
            text = text.replacingOccurrences(of: #"^\s*\|?\s*"# + escaped + #"\s*[|:]\s*"#, with: "",
                                             options: [.regularExpression, .caseInsensitive])
        } else {
            text = text.replacingOccurrences(of: #"^\s*\|?\s*[A-Z]{2,3}\s*\|\s*"#, with: "",
                                             options: .regularExpression)
        }

        // The quality words.
        var found = Set<String>()
        let range = NSRange(text.startIndex..., in: text)
        for match in qualityWord.matches(in: text, range: range) {
            if let r = Range(match.range(at: 1), in: text) { found.insert(text[r].uppercased()) }
        }
        let quality: ChannelQuality
        if found.contains("4K") || found.contains("UHD") {
            quality = .uhd
        } else if found.contains("FHD") {
            quality = .fhd
        } else if found.contains("HD") || found.contains("HD+") {
            quality = .hd
        } else {
            quality = .sd
        }
        text = qualityWord.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text),
                                                    withTemplate: "")

        // Leftovers: empty brackets, doubled spaces, separators at either end.
        text = text.replacingOccurrences(of: #"\(\s*\)|\[\s*\]"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: " |:-–_/").union(.whitespaces))
        if text.isEmpty { text = name.trimmingCharacters(in: .whitespaces) }
        return (text, quality)
    }

    /// The channels with tidied names in the chosen groups. Each keeps its provider name in
    /// `originalName`, its quality, and the folder it's in ("UK | Sports FHD") for mixed lists.
    static func apply(_ channels: [XtreamChannel], chosen: Set<String>,
                      categories: [XtreamCategory]) -> [XtreamChannel] {
        guard !chosen.isEmpty else { return channels }
        let groupNames = Dictionary(categories.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        var tags: [String: String?] = [:]
        return channels.map { channel in
            guard let category = channel.categoryID, chosen.contains(category) else { return channel }
            let groupName = groupNames[category] ?? ""
            if tags[category] == nil { tags[category] = .some(countryTag(ofGroup: groupName)) }
            let (name, quality) = tidy(channel.originalName ?? channel.name, groupTag: tags[category] ?? nil)
            var copy = channel
            copy.originalName = channel.originalName ?? channel.name
            copy.name = name
            copy.quality = quality
            copy.folderName = groupName.isEmpty ? nil : "\(groupName) \(quality.label)"
            return copy
        }
    }
}
