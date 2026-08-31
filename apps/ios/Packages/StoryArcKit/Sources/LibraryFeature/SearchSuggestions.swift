internal import Foundation

internal import StoryArcCore

/// What the search screen offers before a letter is typed.
///
/// `navigation-shell`'s *What search opens onto*: recent searches, and "publications the
/// reader already has — at least one in progress, one never opened, and one that is next in a
/// series they have read". Recent searches are the model's own; these three are this type's.
///
/// **Nothing here fetches.** The requirement says every suggestion "comes from the device or
/// from a source the reader configured, and none is fetched in order to be suggested", so
/// this is a projection over publications the app already holds and reading records it
/// already wrote — no connection, no client, no completion handler. That is the same promise
/// ``HomeShelves`` makes, for the same reason: a suggestion that needed a server would be a
/// search page that is blank on a train.
///
/// **The arithmetic is `HomeShelves`', deliberately.** Two of these three questions are ones
/// Home already asks, and *what to start next* in particular is the one that is easy to get
/// subtly wrong and impossible to see wrong in a screenshot: issue numbers are strings, "3.5"
/// and "Annual 1" are both real, and the ordering is asserted against the same table on both
/// platforms. A second implementation of it on this screen is exactly how the two would
/// drift, which is the failure the format layer's comment in `AGENTS.md` §7 warns about.
///
/// **These three are a product choice, not a guideline.** Material knows only historical
/// suggestions before typing, and the change's `design.md` says so in as many words:
/// *permitted, not prescribed*. So they are specified as behaviour in `navigation-shell` and
/// asserted in `SearchScreenTests`, and nothing here claims Material or the HIG for them.
struct SearchSuggestions: Equatable {

    /// Where the reader stopped. Komga's *Keep reading*.
    let inProgress: [Publication]
    /// What they have never opened. The one section a reader with a fresh library still gets.
    let neverOpened: [Publication]
    /// The next unread issue of a series they have finished something in. Komga's *On Deck*.
    let nextInSeries: [Publication]

    /// How many each section holds.
    ///
    /// Search is never exhaustive; the library is, and typing a term is how a reader gets
    /// there. An unbounded *never opened* over nine hundred publications would be the shelf
    /// with a different heading over it.
    static let sectionLength = 8

    /// Nothing to offer at all — the case that gets one sentence rather than three empty
    /// headings, per `navigation-shell`'s *Nothing to suggest*.
    var isEmpty: Bool { all.isEmpty }

    /// Every suggestion, in the order the screen draws them.
    var all: [Publication] { inProgress + nextInSeries + neverOpened }

    /// The offer, computed from the library and its reading records.
    ///
    /// `progress` is a closure rather than a dictionary so the caller decides where records
    /// come from — the model in the app, a literal in a test — which is what makes the whole
    /// screen's content decidable on the host with no simulator.
    static func of(
        _ library: [Publication],
        limit: Int = sectionLength,
        progress: (Publication) -> ReadingProgress?
    ) -> SearchSuggestions {
        let inProgress = LibraryIndex.continueReading(library, limit: limit) {
            LibraryIndex.Progress.of(progress($0))
        }
        let next = HomeShelves.upNext(in: library, limit: limit, progress: progress)

        // **The one overlap the arithmetic does not remove for itself.** Two of the three
        // sections are already disjoint by construction: `upNext` contributes nothing for a
        // series holding anything part-read, so a volume is never both *in progress* and
        // *next*. But a publication that is next in a series **is** unread — that is half of
        // what qualified it — so *never opened* would offer it a second time, under a
        // heading that says less about it.
        //
        // Removed here rather than inside `HomeShelves.neverOpened`, because it is a fact
        // about *this screen's* three sections and not about the reading state. Home draws
        // no *never opened* shelf, so pushing the exclusion down would make one shelf's
        // rule depend on another screen's layout.
        //
        // The direction matters: *next in series* wins. "You finished volume 1, here is
        // volume 2" is a better thing to say about a book than "you have not opened this",
        // and `HomeShelves.upNext` earned the claim with three rules and a spec scenario.
        let alreadyOffered = Set((inProgress + next).map(\.identity))

        return SearchSuggestions(
            inProgress: inProgress,
            neverOpened: HomeShelves
                .neverOpened(in: library, limit: .max, progress: progress)
                .filter { !alreadyOffered.contains($0.identity) }
                .prefix(limit)
                .map { $0 },
            nextInSeries: next
        )
    }
}
