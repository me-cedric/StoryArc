package app.storyarc.feature.library

import app.storyarc.core.model.LibraryIndex
import app.storyarc.core.model.Publication
import app.storyarc.core.model.ReadState
import app.storyarc.core.model.ReadingProgress

/**
 * What the search page offers before a letter is typed.
 *
 * `navigation-shell`'s *What search opens onto*: recent searches, and "publications the
 * reader already has — at least one in progress, one never opened, and one that is next in a
 * series they have read". Recent searches are the model's own; these three are this type's.
 *
 * **Nothing here fetches.** The requirement says every suggestion "comes from the device or
 * from a source the reader configured, and none is fetched in order to be suggested" — so
 * this is a projection over publications the app already holds and reading records it already
 * read. No client, no store, no coroutine: [of] is an ordinary function that returns before it
 * gets back, which is what makes a search page that is not blank on a train true by
 * construction rather than by discipline.
 *
 * **Its own type, not a port of iOS's.** iOS's `SearchSuggestions` is a composition over its
 * own `HomeShelves` and hands the screen bare `[Publication]`s; this one carries [HomeEntry],
 * because Android's home cell is what draws a suggestion here and that cell needs to know
 * whether the book can be opened at this instant and how much of it is left. Same three
 * questions, each platform's own answer — [ADR-0001] forbids one drawing the other's.
 *
 * **The arithmetic is [HomeShelves]', deliberately.** Two of these three questions are ones
 * Home already asks, and *what to start next* in particular is the one that is easy to get
 * subtly wrong and impossible to see wrong in a screenshot: issue numbers are strings, "3.5"
 * and "Annual 1" are both real, and the three rules that decide the answer are asserted in
 * `HomeShelvesTest`. A second implementation of it on this screen is exactly how the two
 * would drift, which is the failure `AGENTS.md` §7 warns about for the format layer.
 *
 * **These three sections are a product choice, not a Material pattern.** Material knows only
 * historical suggestions before typing, and the change's `design.md` says so in as many
 * words: *permitted, not prescribed*. So they are specified as behaviour in
 * `navigation-shell` and asserted in `SearchSuggestionsTest`, and nothing here claims
 * Material or anyone else for them.
 */
data class SearchSuggestions(
    /** Where the reader stopped. */
    val inProgress: List<HomeEntry> = emptyList(),
    /** The next unread issue of a series they have finished something in. */
    val nextInSeries: List<HomeEntry> = emptyList(),
    /** What they have never opened. The one section a reader with a fresh library still gets. */
    val neverOpened: List<HomeEntry> = emptyList(),
) {
    /**
     * Nothing to offer at all — the case that gets one sentence rather than three empty
     * headings, per `navigation-shell`'s *Nothing to suggest*.
     *
     * One flag rather than three empty lists checked at the call site, so the screen cannot
     * get the question half right and draw a heading over nothing.
     */
    val isEmpty: Boolean
        get() = inProgress.isEmpty() && nextInSeries.isEmpty() && neverOpened.isEmpty()

    /** Every suggestion, in the order the screen draws them. */
    val all: List<HomeEntry> get() = inProgress + nextInSeries + neverOpened

    companion object {
        /**
         * How many each section holds.
         *
         * Search is never exhaustive; the library is, and typing a term is how a reader gets
         * there. An unbounded *never opened* over nine hundred publications would be the
         * shelf with a different heading over it — shorter than [HomeShelves.SHELF_LENGTH]
         * for the same reason, since three sections and a bar share one screen here.
         */
        const val SECTION_LENGTH: Int = 8

        /**
         * The offer, computed from the library and its reading records.
         *
         * @param publications everything the library holds, however it got there.
         * @param progress the local record for a publication, or null when it has never been
         *   opened. Local — ADR-0006 makes the on-device record authoritative.
         * @param isReadableNow whether the publication can be opened at this instant. The
         *   caller answers it, because whether a source is up is the app layer's knowledge
         *   and reaching for the registry in here would give this function a way to block.
         */
        fun of(
            publications: List<Publication>,
            progress: (Publication) -> ReadingProgress?,
            isReadableNow: (Publication) -> Boolean,
            sectionLength: Int = SECTION_LENGTH,
        ): SearchSuggestions {
            val state: (Publication) -> LibraryIndex.Progress =
                { LibraryIndex.Progress.of(progress(it)) }

            // Straight through the shared index, whose ordering rule — most recently read
            // first — is asserted in both platforms' suites.
            val reading = LibraryIndex.continueReading(publications, sectionLength, state)
            val next = HomeShelves.upNext(publications, state, sectionLength)

            // **The one overlap the arithmetic does not remove for itself.** Two of the three
            // sections are already disjoint by construction: `upNext` contributes nothing for
            // a series holding anything part-read, so a volume is never both *in progress*
            // and *next*. But a publication that is next in a series **is** unread — that is
            // half of what qualified it — so *never opened* would offer it a second time,
            // under a heading that says less about it.
            //
            // Removed here rather than inside `HomeShelves`, because it is a fact about
            // *this screen's* three sections and not about the reading state. Home draws no
            // *never opened* shelf, so pushing the exclusion down would make one shelf's rule
            // depend on another screen's layout.
            //
            // The direction matters: *next in series* wins. "You finished volume 1, here is
            // volume 2" is a better thing to say about a book than "you have not opened
            // this", and `HomeShelves.upNext` earned the claim with three rules and a spec
            // scenario.
            val offered = (reading + next).mapTo(mutableSetOf()) { it.id }

            val unopened = publications
                .filter { state(it).state == ReadState.UNREAD && it.id !in offered }
                // Newest arrival first, by the same reading of "when did this turn up" that
                // Home's Recently added uses. A publication that says nothing about its date
                // sorts last and is still offered.
                .sortedByDescending(HomeShelves::arrived)
                .take(sectionLength)

            val entry: (Publication) -> HomeEntry =
                { HomeShelves.entryOf(it, progress, isReadableNow) }

            return SearchSuggestions(
                inProgress = reading.map(entry),
                nextInSeries = next.map(entry),
                neverOpened = unopened.map(entry),
            )
        }
    }
}
