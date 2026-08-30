internal import SwiftUI

/// One row of a search result: a group, or a setting inside one.
///
/// `settings-and-about` asks for matches to be listed "with their group path", which is
/// what `anchor == nil` distinguishes — a group match shows its current value, a setting
/// match shows the group it lives in and, once opened, lights the row up.
struct SettingMatch: Identifiable, Hashable {
    let group: SettingsGroup
    let anchor: SettingsAnchor?

    init(group: SettingsGroup) {
        self.group = group
        anchor = nil
    }

    init(anchor: SettingsAnchor) {
        group = anchor.group
        self.anchor = anchor
    }

    var id: String { anchor?.rawValue ?? group.rawValue }
}

extension SettingsGroup {
    /// Every group, and the settings inside them, that a query matches.
    ///
    /// The index is a list rather than a reflection over the screens, because the screens
    /// are SwiftUI views and a list is the only thing that can be *read* without building
    /// one. It is short enough to keep honest and long enough to be worth having: a reader
    /// looking for "volume" should not have to guess it lives under Reading.
    ///
    /// Matched against English terms rather than the localised strings. That is a known
    /// limit and the honest one — an index keyed on the current locale would miss a reader
    /// who searches in the language they think in, and matching both needs a catalogue
    /// this cannot see. ponytail: English terms; index translations when a reader
    /// complains.
    static func search(_ query: String) -> [SettingMatch] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return allCases.map { SettingMatch(group: $0) } }
        return searchable
            .filter { entry in entry.terms.contains { $0.contains(needle) } }
            .map(\.match)
    }

    /// Not private, so a test can assert that every anchor is reachable and that every
    /// term finds what it claims. An index nothing can read is an index that drifts.
    struct Entry {
        let terms: [String]
        let match: SettingMatch
    }

    /// What each row can be found by.
    ///
    /// Terms rather than one label, so "night" finds Appearance and "licence" finds About —
    /// a reader searches for the thing they want, not for what the screen calls it.
    /// Computed rather than stored, because `LocalizedStringKey` is not `Sendable` and a
    /// static array of them is shared mutable state as far as the compiler is concerned.
    /// A dozen entries built per keystroke is not a cost worth a lock.
    ///
    /// Mirrored term for term with Android's `SEARCHABLE`. The two indexes are the one
    /// place a reader can tell the platforms apart without opening a screen, and they have
    /// already drifted once: "cache" pointed at Downloads here and at Privacy there.
    static var searchable: [Entry] { [
        Entry(terms: ["sources", "folder", "share", "opds", "kavita", "server"],
              match: SettingMatch(group: .sources)),
        Entry(terms: ["appearance", "theme", "dark", "light", "night", "oled", "black",
                      "colour", "color"],
              match: SettingMatch(group: .appearance)),
        Entry(terms: ["link", "match", "chrome"], match: SettingMatch(anchor: .linkReadingTheme)),
        Entry(terms: ["reading", "page", "turn"], match: SettingMatch(group: .reading)),
        Entry(terms: ["volume", "buttons", "keys", "page turn"],
              match: SettingMatch(anchor: .volumeButtons)),
        Entry(terms: ["default", "defaults", "series", "preset"],
              match: SettingMatch(anchor: .readingDefaults)),
        Entry(terms: ["downloads", "offline"], match: SettingMatch(group: .downloads)),
        Entry(terms: ["wifi", "wi-fi", "metered", "mobile", "cellular"],
              match: SettingMatch(anchor: .downloadsWiFiOnly)),
        Entry(terms: ["finished", "remove", "tidy"],
              match: SettingMatch(anchor: .downloadsRemoveAfterFinishing)),
        Entry(terms: ["limit", "quota", "disk", "space"],
              match: SettingMatch(anchor: .downloadsLimit)),
        Entry(terms: ["language", "locale", "translation"], match: SettingMatch(group: .language)),
        Entry(terms: ["privacy", "analytics", "tracking", "account", "data"],
              match: SettingMatch(group: .privacy)),
        Entry(terms: ["cache", "clear"], match: SettingMatch(anchor: .clearCache)),
        Entry(terms: ["history", "progress", "position"], match: SettingMatch(anchor: .clearHistory)),
        Entry(terms: ["storage", "delete downloads"], match: SettingMatch(anchor: .clearDownloads)),
        Entry(terms: ["diagnostic", "diagnostics", "bug", "report", "log"],
              match: SettingMatch(anchor: .diagnostic)),
        Entry(terms: ["about", "version", "author", "licence", "license",
                      "acknowledgements", "credits", "support"],
              match: SettingMatch(group: .about)),
    ] }
}
