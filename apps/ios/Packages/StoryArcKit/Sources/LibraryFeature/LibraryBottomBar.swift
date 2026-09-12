internal import SwiftUI

/// The one line the foot of the shelf has to say.
///
/// Its own file rather than a computed property on ``LibraryView``, which was three lines
/// under the length the linter allows — and because this is a seam that was already there,
/// the same one `LibraryPanes.swift` and `LibraryContent.swift` were split along. The state
/// it reads is `internal` on `LibraryView` for exactly that reason.
///
/// **Seven things can want this strip and exactly one gets it.** Three of them name
/// something, and each outranks every line that only states a moment:
///
/// 1. **A selection in progress.** The bar is for acting on what was picked.
/// 2. **A folder that is no longer available.** `local-library`'s, and *named* rather than
///    counted: "a folder is no longer available" sends someone hunting through four of them.
/// 3. **A source that has never been reached.** `library-browsing` asks the library to name
///    it and to offer to try again. It outranks the four below because it names a place and
///    carries an action where they state a time, and because it persists until the reader or
///    the network changes something — behind `.checked` it would be hidden by any *other*
///    source answering, which is the ordinary case of a folder that works and a server that
///    never has.
///
/// The other four are ``LibraryNotice``'s, and the ranking between them lives there where a
/// test can reach it. It used to be an `else if` chain inside the view's body, which is how
/// the strip came to have no way of saying that a refresh nobody pulled was running — the
/// gap `sources`' *Refresh visibility* was written for.
///
/// The strip is drawn whatever the shelf holds, which is what `library-browsing` asks for:
/// "the rest of the library is complete and usable while it says so".
///
/// The moment the sources were last checked is read off the registry rather than held
/// separately, so this line and the source detail screen's *Last sync* row cannot disagree.
extension LibraryView {
    /// The sources the library has never read, named. A property because a `@ViewBuilder`
    /// chain has nowhere to put a `let`, and the rule itself is ``sourcesNeverReached(in:)``.
    var neverReached: [String] { sourcesNeverReached(in: model.registry.sources) }

    @ViewBuilder
    var bottomBar: some View {
        if selection.isActive {
            BulkActionBar(model: model, selection: $selection)
        } else if let missing = model.unavailableFolders.first {
            UnavailableFolderNotice(name: missing) { picking = .folder }
        } else if !neverReached.isEmpty {
            // Every source, as ``LibraryAway``'s retry does. The reader is asking for the
            // library again, and the one that never answered is the one this line names.
            NeverReachedNotice(names: neverReached, retry: retrySources)
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
