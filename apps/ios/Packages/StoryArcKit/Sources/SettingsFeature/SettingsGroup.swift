internal import SwiftUI

internal import Persistence
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
            settings.language.map { LocalizedStringKey(InterfaceLanguage.name(of: $0)) }
                ?? "settings.language.system"
        case .privacy: "settings.privacy.summary"
        case .about: "settings.about.summary"
        // Both of these are built now, so both state a value. A summary that still said
        // "not built yet" would be the one line on this screen a reader could check
        // against the group behind it and find wrong.
        case .sources:
            library.sources == 0 ? "settings.sources.none" : "settings.sources.summary \(library.sources)"
        // About **downloads**, not about the device. This row read "Nothing on this device"
        // over a device holding nine publications: the figure counts what StoryArc fetched
        // or imported, and a folder the reader added is readable with no network without
        // being any of it. Both readings were defensible and a reader could not see which
        // they had — see ``LibrarySummary``.
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
///
/// **``bytesOnDisk`` is what StoryArc's own files weigh, and nothing else.** It comes from
/// `DownloadStore.bytesOnDisk()`, which walks the app's downloads directory — so it counts
/// what was fetched from a source and what the reader imported, and it does not count a
/// folder the reader added. That folder is readable with no network and appears on the
/// Downloads destination's shelf, because `offline-downloads` asks that destination for
/// everything readable offline "whatever source it came from and however it got there";
/// its bytes are not the app's to count and not the app's to free, so *Clear downloads*
/// would not touch them and a total that included them would be a promise nothing keeps.
///
/// The September sweep photographed the two readings side by side and neither said which
/// it was — Settings claiming "Nothing on this device" while the destination showed nine
/// publications. The numbers were both right; the words were the defect, and every line
/// that states this figure now names downloads.
public struct LibrarySummary: Sendable, Equatable {
    public let sources: Int

    /// What the downloads directory weighs.
    public let bytesOnDisk: Int64

    public init(sources: Int = 0, bytesOnDisk: Int64 = 0) {
        self.sources = sources
        self.bytesOnDisk = bytesOnDisk
    }

    /// The size as a person reads it, through the one helper every screen uses.
    var formattedBytes: String { DownloadStore.formatted(bytesOnDisk) }
}
