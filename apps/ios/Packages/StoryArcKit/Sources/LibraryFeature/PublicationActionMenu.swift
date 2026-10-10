internal import SwiftUI

internal import DesignSystem
internal import StoryArcCore

/// Whether a publication's copy can be added to, or taken off, the device.
///
/// A folder of images is already on the device and has no single file to copy, and a
/// publication no decoder will open has nothing worth fetching either — offering either
/// action anyway would be a control that reports success and changes nothing.
///
/// Lifted out of ``DetailActions``, which had this exact rule under a different name
/// (`canCopy`) and no way for a second menu to ask it without copying the expression: the
/// owner's field report on v0.1.1 named that second menu, and a rule two places state
/// separately is a rule that can disagree the next time one of them changes.
enum PublicationActions {
    static func canDownload(_ publication: Publication) -> Bool {
        publication.isOpenable && publication.format != .imageFolder
    }

    /// Whether there is anything here a copy could be made of right now.
    ///
    /// Lifted out of ``DetailActions``' own `canCopy`, which answered this for the primary
    /// action's menu alone. ``PublicationActionMenu`` asked a second question beside it —
    /// `isLocalFile` — that was wrong the day ``LibraryModel/keepOffline(_:)`` grew a route
    /// for a Kavita chapter with no file of its own: `kavita-server`'s *Keeping a chapter on
    /// the device* fixed the primary menu and left this one still refusing the same row.
    ///
    /// **Every yes here names a route ``LibraryModel/keepOffline(_:)`` can actually take**,
    /// and it has four: it copies a file this device holds, it copies a share's file in chunks
    /// through the opener the app registered for `smb`, it queues a Kavita chapter whose
    /// origin the library can resolve, and it reads an OPDS feed again to queue a catalogue
    /// row. `FileManager.copyItem(at:to:)` cannot take a `smb://` address, which is why
    /// `isFileURL` and not the mere presence of a location decides the first and why the share
    /// is asked for separately. A library row built from a browse that never opened or kept it
    /// draws this exact button, and a tap that does nothing is worse than no button at all —
    /// which is why a row with no route of the four says no. Android states the remote half of
    /// the rule as its own `PublicationActions.isQueueableRemote`.
    ///
    /// **A share row said no here until task 7.7**, and that was honest only while
    /// ``LibraryModel/keepOffline(_:queue:)`` had no road for one: a bulk download quoted a
    /// count that left every share member out. It has the road now, so the count holds them
    /// again — ``ShelfBulkActions`` asks this same question to state it.
    @MainActor
    static func canCopy(_ publication: Publication, file: URL?, model: LibraryModel) -> Bool {
        guard canDownload(publication) else { return false }
        if file?.isFileURL == true { return true }
        if let file, ShareRead.isShare(file) { return true }
        guard let remote = publication.identity.serverIdentifier?.remoteID else { return false }
        if remote.hasPrefix("chapter:") { return model.canKeepKavitaChapter(publication) }
        return remote.hasPrefix("opds:")
    }
}

/// What a download action offers: to fetch a copy, to remove one, or neither.
///
/// A named value rather than two booleans compared inline, so a menu asks one question and a
/// test can state all three answers without constructing a view. Android's `DownloadOffer` is
/// the same three cases.
///
/// `canCopy`: whether ``PublicationActions/canCopy(_:file:model:)`` found a route the menu's
/// download — ``LibraryModel/keepOffline(_:)`` — can actually take. A file this device holds
/// is always one; a browsed Kavita chapter is one only when its origin is known; an OPDS row
/// is one because the queue can read its feed again; nothing else is, a network share least
/// of all.
enum DownloadOffer: Equatable {
    case download
    case remove
    case none

    static func of(_ publication: Publication, isKept: Bool, canCopy: Bool) -> DownloadOffer {
        if isKept { return .remove }
        return canCopy ? .download : .none
    }
}

/// The one action list a publication offers, wherever it is drawn.
///
/// `library-browsing`'s *A publication's actions wherever it is drawn*: the same actions —
/// open, mark read or unread, start from the beginning, add to a shelf, download or remove
/// the download, and show details — on the library grid and list, search results, the home
/// surface, a shelf, a collection or reading-list page, and a server's own browser. A
/// seventh, removing the publication from the shelf this menu was opened on, is offered only
/// where there is one.
///
/// **`open` names a row of its own.** The spec lists it as its own action beside *show
/// details*, and the two take the same route for the reason ``CoverCell`` already gives: a
/// cover "leads to the publication's page, not to the reader". They read as two names for
/// one door rather than a duplicate, because a reader who is already inside the long-press
/// interaction that drew this menu has no tap left to give — the cover under it is covered by
/// the preview, and *Open* is how the menu itself commits to it.
///
/// **Wraps ``AddToShelfMenu`` rather than repeating what it already gets right.** The owner's
/// field report on v0.1.1 named the defect as "a long press ... offers its actions only in
/// the library grid", and the grid's own menu was already four of the six —
/// ``AddToShelfMenu`` carries mark read/unread, start from the beginning and add to a shelf.
/// This adds the ones it does not, and is what every surface names in the report should call
/// instead of ``AddToShelfMenu`` alone.
struct PublicationActionMenu: View {
    /// Set by the Library split's shelf column, where a value link finds no destination —
    /// the same environment key ``CoverCell`` and ``ListRow`` already read for their own tap,
    /// and read here for the identical reason: *Open* and *Show details* are the same route.
    @Environment(\.openPublicationRoute) private var openRoute

    let model: LibraryModel
    let publication: Publication
    /// Removes the publication from the shelf this menu was opened on. `nil` where the menu
    /// was not opened from inside a shelf, a collection or a reading list the reader owns —
    /// the library grid and Home have nowhere to remove a publication *from*.
    var onRemoveFromShelf: (() -> Void)?
    let onRefused: (String, [Publication]) -> Void
    let onRestart: () -> Void

    @State private var isDownloading = false

    var body: some View {
        openAction

        AddToShelfMenu(
            model: model,
            publications: [publication],
            onRefused: onRefused,
            onRestart: onRestart
        )

        downloadAction

        if let onRemoveFromShelf {
            Button(role: .destructive, action: onRemoveFromShelf) {
                Label(
                    String(localized: "library.action.removeFromShelf",
                           bundle: .module.inChosenLanguage, locale: .storyArc),
                    systemImage: "minus.circle"
                )
            }
        }

        showDetails
    }

    /// *Open*, named for a reader who is already inside the long-press interaction this menu
    /// drew and has no tap left to give — the cover under it is covered by the preview. The
    /// same route *Show details* takes, below: `publication-detail` requires the page
    /// reachable "from every surface that shows a publication", and the cover's own tap
    /// already takes one of these two roads — see ``CoverCell``.
    @ViewBuilder
    private var openAction: some View {
        let label = Label(
            String(localized: "library.action.open", bundle: .module.inChosenLanguage, locale: .storyArc),
            systemImage: "arrow.up.forward.app"
        )
        if let openRoute {
            Button { openRoute(PublicationRoute(publication)) } label: { label }
        } else {
            NavigationLink(value: PublicationRoute(publication)) { label }
        }
    }

    /// Opens the publication's own page. `publication-detail` requires the page reachable
    /// "from every surface that shows a publication", and the cover's own tap already takes
    /// one of these two roads — see ``CoverCell``. A `NavigationLink` inside a menu still
    /// pushes onto the enclosing stack, which is what makes the ordinary road a menu row
    /// rather than a callback nobody here would have anywhere to send.
    @ViewBuilder
    private var showDetails: some View {
        let label = Label(
            String(localized: "library.action.showDetails", bundle: .module.inChosenLanguage, locale: .storyArc),
            systemImage: "info.circle"
        )
        if let openRoute {
            Button { openRoute(PublicationRoute(publication)) } label: { label }
        } else {
            NavigationLink(value: PublicationRoute(publication)) { label }
        }
    }

    @ViewBuilder
    private var downloadAction: some View {
        switch DownloadOffer.of(
            publication,
            isKept: model.isOnDevice(publication),
            canCopy: PublicationActions.canCopy(publication, file: model.location(of: publication), model: model)
        ) {
        case .download:
            Button {
                isDownloading = true
                Task {
                    _ = await model.keepOffline([publication.id])
                    isDownloading = false
                }
            } label: {
                Label(
                    String(localized: "catalogue.acquire.download",
                           bundle: .module.inChosenLanguage, locale: .storyArc),
                    systemImage: "arrow.down.circle"
                )
            }
            .disabled(isDownloading)
        case .remove:
            Button(role: .destructive) {
                model.forgetKept([publication.id])
            } label: {
                Label(
                    String(localized: "downloads.remove", bundle: .module.inChosenLanguage, locale: .storyArc),
                    systemImage: "trash"
                )
            }
        case .none:
            EmptyView()
        }
    }
}
