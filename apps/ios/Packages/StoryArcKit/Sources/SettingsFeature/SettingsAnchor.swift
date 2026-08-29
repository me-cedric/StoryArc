internal import SwiftUI

/// One setting inside a group, named so that search can point at it and the group can
/// light it up when a reader arrives.
///
/// `settings-and-about`: a search result "navigates there and highlights it". The
/// highlight needs an identity the two halves agree on — the index says which setting
/// matched, the screen decides which row that is. A label would serve until someone
/// rewords a label; a case cannot be reworded by accident, and the compiler names every
/// screen that has to answer for a new one.
///
/// Only rows that are one thing are here. "Acknowledgements" is a section of a dozen
/// licences and "Language" is the whole group, so both stay group matches — pointing at
/// them would be pointing at a screen, which arriving there already does.
enum SettingsAnchor: String, CaseIterable, Identifiable, Sendable {
    case linkReadingTheme
    case volumeButtons
    case readingDefaults
    case downloadsWiFiOnly
    case downloadsRemoveAfterFinishing
    case downloadsLimit
    case clearCache
    case clearHistory
    case clearDownloads
    case diagnostic

    var id: String { rawValue }

    /// Where the setting lives. Declared once, so the index cannot claim a setting is on a
    /// screen that does not show it.
    var group: SettingsGroup {
        switch self {
        case .linkReadingTheme: .appearance
        case .volumeButtons, .readingDefaults: .reading
        case .downloadsWiFiOnly, .downloadsRemoveAfterFinishing, .downloadsLimit: .downloads
        case .clearCache, .clearHistory, .clearDownloads, .diagnostic: .privacy
        }
    }

    /// What a search result calls it: the row's own label, so the match reads as the thing
    /// the reader is about to see rather than as a synonym for it.
    var titleKey: LocalizedStringKey {
        switch self {
        case .linkReadingTheme: "appearance.linkTheme"
        case .volumeButtons: "reading.volumeButtons"
        case .readingDefaults: "reading.defaults"
        case .downloadsWiFiOnly: "downloads.wifiOnly"
        case .downloadsRemoveAfterFinishing: "downloads.removeAfter"
        case .downloadsLimit: "downloads.limit"
        case .clearCache: "privacy.clear.cache"
        case .clearHistory: "privacy.clear.history"
        case .clearDownloads: "privacy.clear.downloads"
        case .diagnostic: "privacy.diagnostic"
        }
    }
}
