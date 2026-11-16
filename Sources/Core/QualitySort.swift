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
    /// Your own channel names (long-press › Rename…) for the account in use, by channel id.
    nonisolated(unsafe) static var activeCustomNames: [Int: String] = [:]

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
    static func tidy(_ name: String, groupTag: String?) -> (name: String, quality: ChannelQuality, hevc: Bool) {
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
        return (text, quality, found.contains("HEVC"))
    }

    // MARK: Twin groups

    /// A group's name without quality words: "UK | Entertainment HEVC" → "UK | Entertainment".
    static func baseGroupName(_ name: String) -> String {
        var text = qualityWord.stringByReplacingMatches(in: name, range: NSRange(name.startIndex..., in: name),
                                                        withTemplate: "")
        text = text.replacingOccurrences(of: #"\(\s*\)|\[\s*\]"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: " |:-–_/").union(.whitespaces))
        return text.isEmpty ? name : text
    }

    /// Groups listed once in Sort by quality: twins (names that only differ by quality words)
    /// together, in the provider's order. The first id leads; the name has no quality words.
    static func twinGroups(_ categories: [XtreamCategory]) -> [(ids: [String], name: String)] {
        var order: [String] = []
        var byKey: [String: (ids: [String], name: String)] = [:]
        for category in categories {
            let name = baseGroupName(category.name)
            let key = name.lowercased()
            if byKey[key] == nil {
                order.append(key)
                byKey[key] = ([], name)
            }
            byKey[key]?.ids.append(category.id)
        }
        return order.compactMap { byKey[$0] }
    }

    /// For each chosen group: the group that leads its merged folders, and their base name.
    static func mergedGroups(_ categories: [XtreamCategory], chosen: Set<String>) -> [String: (lead: String, name: String)] {
        var result: [String: (lead: String, name: String)] = [:]
        for twins in twinGroups(categories) {
            let picked = twins.ids.filter { chosen.contains($0) }
            guard let lead = picked.first else { continue }
            for id in picked { result[id] = (lead, twins.name) }
        }
        return result
    }

    /// The channels as Tellio shows them. In chosen groups: tidied names, each channel's
    /// quality, its merged folder ("UK | Sports FHD") and a key for sharing guide listings with
    /// the same channel elsewhere; an HEVC copy sharing a folder with another copy is tagged
    /// "· HEVC". Then your own names (Rename…) win everywhere. The provider's name is kept in
    /// `originalName` whenever the shown one differs.
    static func apply(_ channels: [XtreamChannel], chosen: Set<String>, customNames: [Int: String],
                      categories: [XtreamCategory]) -> [XtreamChannel] {
        guard !chosen.isEmpty || !customNames.isEmpty else { return channels }
        let groupNames = Dictionary(categories.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let merged = mergedGroups(categories, chosen: chosen)
        var tags: [String: String?] = [:]
        var hevc = Set<Int>()
        var result = channels.map { channel -> XtreamChannel in
            guard let category = channel.categoryID, let group = merged[category] else { return channel }
            if tags[category] == nil { tags[category] = .some(countryTag(ofGroup: groupNames[category] ?? "")) }
            let tag = tags[category] ?? nil
            let tidied = tidy(channel.providerName, groupTag: tag)
            var copy = channel
            copy.originalName = channel.providerName
            copy.name = tidied.name
            copy.quality = tidied.quality
            copy.folderGroupID = group.lead
            copy.folderName = "\(group.name) \(tidied.quality.label)"
            copy.guideKey = (tag ?? "").lowercased() + "|" + tidied.name.lowercased()
            if tidied.hevc { hevc.insert(channel.id) }
            return copy
        }

        // The same channel twice in one folder: tag the HEVC copy.
        if !hevc.isEmpty {
            var perFolder: [String: Int] = [:]
            for channel in result where channel.folderGroupID != nil {
                perFolder[folderSlot(channel), default: 0] += 1
            }
            for index in result.indices where hevc.contains(result[index].id) {
                if perFolder[folderSlot(result[index]), default: 0] > 1 { result[index].name += " · HEVC" }
            }
        }

        // Your own names last.
        if !customNames.isEmpty {
            for index in result.indices {
                guard let custom = customNames[result[index].id] else { continue }
                if result[index].originalName == nil { result[index].originalName = result[index].name }
                result[index].name = custom
            }
        }
        return result
    }

    private static func folderSlot(_ channel: XtreamChannel) -> String {
        "\(channel.folderGroupID ?? "")|\(channel.quality?.rawValue ?? "")|\(channel.name.lowercased())"
    }

    /// Channels that are the same channel in different versions (same tidied name and country
    /// tag), so one with no guide listings can use another's.
    static func guideTwins(_ channels: [XtreamChannel]) -> [Int: [Int]] {
        var byKey: [String: [Int]] = [:]
        for channel in channels {
            if let key = channel.guideKey { byKey[key, default: []].append(channel.id) }
        }
        var result: [Int: [Int]] = [:]
        for ids in byKey.values where ids.count > 1 {
            for id in ids { result[id] = ids.filter { $0 != id } }
        }
        return result
    }

    /// Your own names on a list fetched straight from the provider (not through the cache).
    static func applyCustomNames(_ channels: [XtreamChannel]) -> [XtreamChannel] {
        let names = activeCustomNames
        guard !names.isEmpty else { return channels }
        return channels.map { channel in
            guard let custom = names[channel.id] else { return channel }
            var copy = channel
            copy.originalName = channel.providerName
            copy.name = custom
            return copy
        }
    }
}
