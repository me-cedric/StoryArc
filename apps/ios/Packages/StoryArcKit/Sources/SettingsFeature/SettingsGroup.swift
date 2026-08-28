internal import SwiftUI

internal import StoryArcCore

/// The seven groups `settings-and-about` names, in the order it names them.
///
/// The order is the spec's, not alphabetical and not arbitrary: Sources first because it
/// is what a new reader needs, About last because it is what nobody needs twice.
enum SettingsGroup: String, CaseIterable, Identifiable {
    case sources
    case appearance
    case reading
    case downloads
    case language
    case privacy
    case about

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .sources: "settings.sources"
        case .appearance: "settings.appearance"
        case .reading: "settings.reading"
        case .downloads: "settings.downloads"
        case .language: "settings.language"
        case .privacy: "settings.privacy"
        case .about: "settings.about"
        }
    }

    var symbol: String {
        switch self {
        case .sources: "folder"
        case .appearance: "paintpalette"
        case .reading: "book"
        case .downloads: "arrow.down.circle"
        case .language: "globe"
        case .privacy: "lock"
        case .about: "info.circle"
        }
    }

    /// What a group that cannot be entered yet says instead of opening onto nothing.
    var pendingKey: LocalizedStringKey {
        switch self {
        case .sources: "settings.sources.pending"
        case .downloads: "settings.downloads.pending"
        case .language: "settings.language.pending"
        default: "settings.pending"
        }
    }

    /// The group's current value, in one line.
    ///
    /// `settings-and-about`: each summary row "states its current value, so a setting can
    /// be checked without entering the group". A group with nothing to state yet says
    /// what it will hold — which is a value too, and a more honest one than silence.
    func summaryKey(for settings: AppSettings, _ library: LibrarySummary = LibrarySummary()) -> LocalizedStringKey {
        switch self {
        case .appearance: settings.appearance.localizedNameKey
        // Not the volume setting: iOS cannot honour it, so a summary claiming it would be
        // a summary of something that does not happen.
        case .reading: "settings.reading.summary"
        case .language:
            settings.language == nil ? "settings.language.system" : "settings.language.custom"
        case .privacy: "settings.privacy.summary"
        case .about: "settings.about.summary"
        // Both of these are built now, so both state a value. A summary that still said
        // "not built yet" would be the one line on this screen a reader could check
        // against the group behind it and find wrong.
        case .sources:
            library.sources == 0 ? "settings.sources.none" : "settings.sources.summary \(library.sources)"
        case .downloads:
            library.bytesOnDisk == 0
                ? "settings.downloads.none"
                : "settings.downloads.summary \(library.formattedBytes)"
        }
    }
}

/// What the summary rows need to know about the library.
///
/// A value rather than two more parameters, because both numbers come from the same place
/// and a screen that took them separately would be one refactor away from showing a source
/// count next to another library's size.
public struct LibrarySummary: Sendable, Equatable {
    public let sources: Int
    public let bytesOnDisk: Int64

    public init(sources: Int = 0, bytesOnDisk: Int64 = 0) {
        self.sources = sources
        self.bytesOnDisk = bytesOnDisk
    }

    /// The size as a person reads it.
    var formattedBytes: String { bytesOnDisk.formatted(.byteCount(style: .file)) }
}
