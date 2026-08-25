internal import SwiftUI

/// One row of a search result: a group, or a setting inside one.
///
/// `settings-and-about` asks for matches to be listed "with their group path", which is
/// what `setting == nil` distinguishes — a group match shows its current value, a setting
/// match shows the group it lives in.
struct SettingMatch: Identifiable {
    let group: SettingsGroup
    let setting: LocalizedStringKey?

    var id: String { "\(group.rawValue)-\(String(describing: setting))" }
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
        guard !needle.isEmpty else { return allCases.map { SettingMatch(group: $0, setting: nil) } }
        return searchable
            .filter { entry in entry.terms.contains { $0.contains(needle) } }
            .map { SettingMatch(group: $0.group, setting: $0.setting) }
    }

    private struct Entry {
        let terms: [String]
        let group: SettingsGroup
        let setting: LocalizedStringKey?
    }

    /// What each row can be found by.
    ///
    /// Terms rather than one label, so "night" finds Appearance and "licence" finds About —
    /// a reader searches for the thing they want, not for what the screen calls it.
    /// Computed rather than stored, because `LocalizedStringKey` is not `Sendable` and a
    /// static array of them is shared mutable state as far as the compiler is concerned.
    /// Nine entries built per keystroke is not a cost worth a lock.
    private static var searchable: [Entry] { [
        Entry(terms: ["sources", "folder", "share", "opds", "kavita", "server"],
              group: .sources, setting: nil),
        Entry(terms: ["appearance", "theme", "dark", "light", "night", "oled", "black",
                      "colour", "color"],
              group: .appearance, setting: nil),
        Entry(terms: ["reading", "page", "turn"], group: .reading, setting: nil),
        Entry(terms: ["volume", "buttons", "keys", "page turn"],
              group: .reading, setting: "reading.volumeButtons"),
        Entry(terms: ["default", "defaults", "series", "preset"],
              group: .reading, setting: "reading.defaults"),
        Entry(terms: ["downloads", "storage", "cache", "offline", "space"],
              group: .downloads, setting: nil),
        Entry(terms: ["language", "locale", "translation"], group: .language, setting: nil),
        Entry(terms: ["privacy", "analytics", "tracking", "account", "data"],
              group: .privacy, setting: nil),
        Entry(terms: ["about", "version", "author", "licence", "license",
                      "acknowledgements", "credits", "support"],
              group: .about, setting: nil),
    ] }
}
