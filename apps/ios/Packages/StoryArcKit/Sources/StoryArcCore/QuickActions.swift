public import Foundation

/// One entry in the menu the system shows when the app icon is held down.
///
/// `native-experience` names quick actions among the system affordances the app is
/// required to use rather than invent. What belongs in that menu is the short list of
/// things a reader opens the app *for*, which is why there are three of them and not
/// seven: a menu long enough to read is a menu, not a shortcut.
///
/// The payload is on ``continueReading`` alone, because it is the only entry that is
/// about a particular book. The other two are places.
///
/// Android's `QuickAction` mirrors this case for case.
public enum QuickAction: Sendable, Equatable {
    /// The publication the reader was in the middle of, named so the menu says which book.
    case continueReading(id: String, title: String)
    /// Everything on the device, whatever the app was showing when it was last left.
    case library
    /// What has been fetched, and what is still coming.
    case downloads

    /// The identifier the system stores this entry under.
    ///
    /// Reverse-DNS and written out rather than derived from the case name: these strings
    /// outlive a launch — iOS keeps them in `UIApplication.shortcutItems` and Android in
    /// the launcher's own shortcut store — so renaming a case must not silently orphan
    /// every menu already on a reader's home screen. Both platforms store these three.
    public var id: String {
        switch self {
        case .continueReading: QuickAction.continueID
        case .library: QuickAction.libraryID
        case .downloads: QuickAction.downloadsID
        }
    }

    public static let continueID = "app.storyarc.quickaction.continue"
    public static let libraryID = "app.storyarc.quickaction.library"
    public static let downloadsID = "app.storyarc.quickaction.downloads"
}

/// What a quick action asks the app to do, read back after the system has handed it over.
///
/// A separate type from ``QuickAction`` because the two travel in opposite directions and
/// carry different things: the app publishes a title so the menu can be read, and the
/// system hands back an identifier so the app can act. Collapsing them would mean
/// trusting a title the system stored a week ago to still name the right book.
public enum QuickActionRequest: Sendable, Equatable {
    case continueReading(id: String)
    case library
    case downloads

    /// Reads a request back from the identifier the system stored, and the publication
    /// the entry was carrying.
    ///
    /// `nil` rather than a default for anything unrecognised. A menu on a reader's home
    /// screen can be older than the app that is now handling it, and an unknown entry
    /// that quietly fell back to the library would look like the app ignoring a tap.
    /// A continue entry with no publication is refused for the stronger version of the
    /// same reason: opening *something* would be opening the wrong book.
    public init?(id: String, publicationID: String? = nil) {
        switch id {
        case QuickAction.continueID:
            guard let publicationID, !publicationID.isEmpty else { return nil }
            self = .continueReading(id: publicationID)
        case QuickAction.libraryID:
            self = .library
        case QuickAction.downloadsID:
            self = .downloads
        default:
            return nil
        }
    }
}

/// What the menu holds, given what the reader has.
///
/// Pure, and deliberately so: this is the half of the capability that has to be identical
/// on both platforms, and it is the half worth asserting against the same table in both
/// suites (ADR-0001). Everything else — a `UIApplicationShortcutItem` here, a
/// `ShortcutInfoCompat` there — is the platform's own vocabulary for the same list.
public enum QuickActions {

    /// The entries to publish, in the order the reader should meet them.
    ///
    /// Continue first, because it is the reason someone holds the icon down rather than
    /// tapping it. Library always, because it is the one destination that exists on a
    /// fresh install. Downloads only once there is something in it: a permanent entry
    /// that opens onto an empty screen is a promise the app cannot keep, and downloads
    /// only ever arrive from a catalogue, a server or a share.
    ///
    /// A publication with no usable title is not offered. The entry's whole job is to
    /// name the book, and one headed by a blank line would be a menu row a reader cannot
    /// read — `offline-downloads` has already met a whitespace-only title once.
    public static func offered(
        continuing publication: Publication?,
        hasDownloads: Bool
    ) -> [QuickAction] {
        var actions: [QuickAction] = []

        if let publication {
            let title = publication.displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty {
                actions.append(.continueReading(id: publication.id, title: title))
            }
        }

        actions.append(.library)
        if hasDownloads { actions.append(.downloads) }

        return actions
    }
}
