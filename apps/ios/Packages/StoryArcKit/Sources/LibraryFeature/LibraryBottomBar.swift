internal import SwiftUI

/// The one line the foot of the shelf has to say.
///
/// Its own file rather than a computed property on ``LibraryView``, which was three lines
/// under the length the linter allows — and because this is a seam that was already there,
/// the same one `LibraryPanes.swift` and `LibraryContent.swift` were split along. The state
/// it reads is `internal` on `LibraryView` for exactly that reason.
///
/// **Six things can want this strip and exactly one gets it.** Two of them are not about
/// sources and outrank every one that is:
///
/// 1. **A selection in progress.** The bar is for acting on what was picked.
/// 2. **A folder that is no longer available.** `local-library`'s, and *named* rather than
///    counted: "a folder is no longer available" sends someone hunting through four of them.
///
/// The other four are ``LibraryNotice``'s, and the ranking between them lives there where a
/// test can reach it. It used to be an `else if` chain inside the view's body, which is how
/// the strip came to have no way of saying that a refresh nobody pulled was running — the
/// gap `sources`' *Refresh visibility* was written for.
///
/// The moment the sources were last checked is read off the registry rather than held
/// separately, so this line and the source detail screen's *Last sync* row cannot disagree.
extension LibraryView {
    @ViewBuilder
    var bottomBar: some View {
        if selection.isActive {
            BulkActionBar(model: model, selection: $selection)
        } else if let missing = model.unavailableFolders.first {
            UnavailableFolderNotice(name: missing) { picking = .folder }
        } else {
            switch LibraryNotice.of(
                refreshing: model.refreshing,
                waiting: sourcesStillBeingRead(
                    sources: model.registry.sources, publications: model.publications
                ),
                cachedAt: model.cachedAt,
                checkedAt: model.registry.sources.compactMap(\.lastSuccessfulSync).max()
            ) {
            case .stillBeingRead(let waiting): StillBeingReadNotice(waiting: waiting)
            case .cached(let at): CachedNotice(refreshedAt: at)
            case .refreshing: RefreshingNotice()
            case .checked(let at): CheckedNotice(checkedAt: at)
            case .none: EmptyView()
            }
        }
    }
}
