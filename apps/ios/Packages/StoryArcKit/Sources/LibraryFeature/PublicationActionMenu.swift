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
}

/// What a download action offers: to fetch a copy, to remove one, or neither.
///
/// A named value rather than two booleans compared inline, so a menu asks one question and a
/// test can state all three answers without constructing a view. Android's `DownloadOffer` is
/// the same three cases.
///
/// `isLocalFile`: the menu's download is ``LibraryModel/keepOffline(_:)``, which copies a file
/// that is already on this device. A row whose bytes are on a server has no such file, so the
/// copy is skipped and nothing happens. The menu does not offer a download it cannot deliver.
enum DownloadOffer: Equatable {
    case download
    case remove
    case none

    static func of(_ publication: Publication, isKept: Bool, isLocalFile: Bool) -> DownloadOffer {
        if isKept { return .remove }
        return isLocalFile && PublicationActions.canDownload(publication) ? .download : .none
    }
}

/// The one action list a publication offers, wherever it is drawn.
///
/// `library-browsing`'s *A publication's actions wherever it is drawn*: the same actions —
/// open (the tap that already carries the cover, not a row in here), mark read or unread,
/// start from the beginning, add to a shelf, download or remove the download, and show
/// details — on the library grid and list, the home surface, a shelf, a collection or
/// reading-list page, and a server's own browser. A seventh, removing the publication from
/// the shelf this menu was opened on, is offered only where there is one.
///
/// **Wraps ``AddToShelfMenu`` rather than repeating what it already gets right.** The owner's
/// field report on v0.1.1 named the defect as "a long press ... offers its actions only in
/// the library grid", and the grid's own menu was already four of the six —
/// ``AddToShelfMenu`` carries mark read/unread, start from the beginning and add to a shelf.
/// This adds the two it does not, and is what every surface names in the report should call
/// instead of ``AddToShelfMenu`` alone.
struct PublicationActionMenu: View {
    /// Set by the Library split's shelf column, where a value link finds no destination —
    /// the same environment key ``CoverCell`` and ``ListRow`` already read for their own tap,
    /// and read here for the identical reason: *Show details* is the same route.
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
                    String(localized: "library.action.removeFromShelf", bundle: .module, locale: .storyArc),
                    systemImage: "minus.circle"
                )
            }
        }

        showDetails
    }

    /// Opens the publication's own page. `publication-detail` requires the page reachable
    /// "from every surface that shows a publication", and the cover's own tap already takes
    /// one of these two roads — see ``CoverCell``. A `NavigationLink` inside a menu still
    /// pushes onto the enclosing stack, which is what makes the ordinary road a menu row
    /// rather than a callback nobody here would have anywhere to send.
    @ViewBuilder
    private var showDetails: some View {
        let label = Label(
            String(localized: "library.action.showDetails", bundle: .module, locale: .storyArc),
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
            isLocalFile: model.location(of: publication)?.isFileURL ?? false
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
                    String(localized: "catalogue.acquire.download", bundle: .module, locale: .storyArc),
                    systemImage: "arrow.down.circle"
                )
            }
            .disabled(isDownloading)
        case .remove:
            Button(role: .destructive) {
                model.forgetKept([publication.id])
            } label: {
                Label(
                    String(localized: "downloads.remove", bundle: .module, locale: .storyArc),
                    systemImage: "trash"
                )
            }
        case .none:
            EmptyView()
        }
    }
}
