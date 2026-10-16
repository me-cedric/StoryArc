import Foundation

/// The tabs of the preferences window, in toolbar order.
enum SettingsTab: String, CaseIterable, Sendable, Identifiable {
    case sources, appearance, reading, downloads, language, privacy

    var id: String { rawValue }

    var titleKey: String { "desktop.settings.\(rawValue)" }

    var symbolName: String {
        switch self {
        case .sources: "externaldrive.connected.to.line.below"
        case .appearance: "paintpalette"
        case .reading: "book"
        case .downloads: "arrow.down.circle"
        case .language: "globe"
        case .privacy: "hand.raised"
        }
    }
}

/// One setting a search can find: its tab, its title and the words it answers to.
struct SettingsEntry: Identifiable, Equatable, Sendable {
    let id: String
    let tab: SettingsTab
    let title: String
    let keywords: [String]
}

/// The searchable index of the preferences.
///
/// `desktop-experience`, *Searching the preferences*: only the settings that match show,
/// grouped under their sections, and an empty result says so in grey. The words are the
/// English titles and a few synonyms; the catalogue's localised titles join at draw time.
/// Task 2.21.
enum SettingsIndex {
    static let entries: [SettingsEntry] = [
        SettingsEntry(id: "folders", tab: .sources, title: "Folders", keywords: ["folder", "source", "library", "add"]),
        SettingsEntry(id: "appearance", tab: .appearance, title: "Appearance",
                      keywords: ["light", "dark", "system", "theme"]),
        SettingsEntry(id: "accent", tab: .appearance, title: "Accent", keywords: ["colour", "color", "tint", "brand"]),
        SettingsEntry(id: "textSize", tab: .appearance, title: "Text size",
                      keywords: ["font", "larger", "smaller", "size"]),
        SettingsEntry(id: "clickZones", tab: .reading, title: "Edge click zones",
                      keywords: ["click", "tap", "turn", "edge"]),
        SettingsEntry(id: "transition", tab: .reading, title: "Page transition",
                      keywords: ["curl", "slide", "fade", "motion"]),
        SettingsEntry(id: "coverAlone", tab: .reading, title: "Cover alone", keywords: ["spread", "two pages", "pair"]),
        SettingsEntry(id: "readingTheme", tab: .reading, title: "Reading theme",
                      keywords: ["paper", "sepia", "theme", "night"]),
        SettingsEntry(id: "metered", tab: .downloads, title: "Metered connections",
                      keywords: ["wi-fi", "wifi", "cellular", "download"]),
        SettingsEntry(id: "language", tab: .language, title: "Language",
                      keywords: ["english", "french", "german", "spanish"]),
        SettingsEntry(id: "history", tab: .privacy, title: "Reading history", keywords: ["clear", "privacy", "recent"]),
        SettingsEntry(id: "diagnostic", tab: .privacy, title: "Diagnostic", keywords: ["export", "problem", "report"]),
    ]

    /// The entries that match, in index order. Everything for an empty query.
    static func matches(_ query: String) -> [SettingsEntry] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return entries }
        return entries.filter { entry in
            entry.title.lowercased().contains(needle)
                || entry.keywords.contains { $0.contains(needle) }
                || entry.tab.rawValue.contains(needle)
        }
    }

    /// The matches under their tabs, tabs in toolbar order, empty tabs absent.
    static func grouped(_ query: String) -> [(tab: SettingsTab, entries: [SettingsEntry])] {
        let found = matches(query)
        return SettingsTab.allCases.compactMap { tab in
            let inTab = found.filter { $0.tab == tab }
            return inTab.isEmpty ? nil : (tab, inTab)
        }
    }
}
