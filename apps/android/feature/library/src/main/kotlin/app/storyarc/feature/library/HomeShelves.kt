package app.storyarc.feature.library

import app.storyarc.core.model.LibraryIndex
import app.storyarc.core.model.PinnedShelves
import app.storyarc.core.model.Publication
import app.storyarc.core.model.ReadState
import app.storyarc.core.model.ReadingPosition
import app.storyarc.core.model.ReadingProgress
import app.storyarc.core.model.ShelfPin
import app.storyarc.core.model.Shelves
import kotlin.math.roundToInt

/**
 * One publication as the home surface offers it.
 *
 * The publication plus the three things a home shelf says about it that the library grid
 * does not: whether it can be opened *right now*, how much of it is left, and how far
 * through it the reader is. `home-screen` asks for the first two by name — a shelf that
 * shrank when the Wi-Fi went "reads as lost reading", so an entry that cannot be opened
 * stays and says so.
 *
 * @property isReadableNow false when the publication is neither on the device nor served
 *   by a source that is currently answering. It is still drawn, dimmed.
 * @property pagesRemaining null when the publication does not say how many pages it has,
 *   which is normal for a reflowable book. The surface then says nothing rather than
 *   falling back to a percentage, which `home-screen` refuses on its own.
 * @property state whether the library considers this read, part-read or untouched.
 *
 *   **Carried rather than inferred from [pagesRemaining] or [fraction], and that is what
 *   this field is for.** A caption assembled from those two announced every cover on Home
 *   as "Part-read" — including books nobody had ever opened, because a publication with no
 *   record has no page count either and the fallback for "does not say" was the same
 *   sentence as the fallback for "part way through". Measured on an emulator with a freshly
 *   cleared app: all three cells on *Recently added* said it.
 */
data class HomeEntry(
    val publication: Publication,
    val isReadableNow: Boolean,
    val pagesRemaining: Int?,
    val fraction: Double,
    val state: ReadState = ReadState.UNREAD,
    /**
     * Whether a page or less is left, which changes what the hero card offers.
     *
     * [HomeShelves.isAtTheEnd]. False by default, so a shelf that has no reason to ask the
     * question -- every shelf but Keep reading -- is not obliged to answer it.
     */
    val isAtTheEnd: Boolean = false,
    /**
     * The next issue of the same series, where the library holds one and this entry is at
     * its end. Null everywhere else, including on every shelf that is not Keep reading.
     */
    val nextInSeries: Publication? = null,
) {
    val id: String get() = publication.id
}

/**
 * How long ago a publication was finished.
 *
 * `home-screen` asks for finished publications "grouped by when they were finished". Three
 * relative buckets rather than formatted dates: a date needs a locale-aware formatter to
 * become a heading, and three buckets are what a reader actually scans for — recently,
 * lately, and everything before that.
 */
enum class HomeFinishedPeriod { THIS_WEEK, THIS_MONTH, EARLIER }

/** Finished publications from one period, most recently finished first. */
data class HomeFinishedGroup(val period: HomeFinishedPeriod, val entries: List<HomeEntry>)

/**
 * One pinned collection or reading list, resolved to what the home surface can draw.
 *
 * Carries its own name because that is the heading -- the shelf is the reader's, so no string
 * resource can name it -- and its own entries because a reading list keeps an order and a
 * collection does not, and that difference has to survive the trip to this screen.
 *
 * A shelf that resolves to nothing is not built at all, per *A shelf that would be empty*.
 * That is not only about a collection the reader emptied: a pinned shelf whose members live
 * on a source no scan has reached yet resolves to nothing too, and a heading over no covers
 * would be the surface looking like it was waiting for something -- the one thing it must
 * never look like it is doing.
 */
data class HomePinnedShelf(
    val pin: ShelfPin,
    val name: String,
    val entries: List<HomeEntry>,
)

/**
 * Everything the home surface draws, assembled and ready.
 *
 * A value rather than a set of flows: `home-screen` requires the surface to "render
 * complete and immediately", with no shelf that "appears, reorders or grows once" a source
 * answers. One value computed from local data alone is how that is true by construction —
 * there is no partial state for a slow source to complete.
 *
 * Every list is empty rather than absent when it has nothing: a section with no entries is
 * not drawn at all, which is the degradation the spec asks for in five separate scenarios.
 */
data class HomeSurface(
    val keepReading: List<HomeEntry> = emptyList(),
    val upNext: List<HomeEntry> = emptyList(),
    val recentlyAdded: List<HomeEntry> = emptyList(),
    /**
     * The collections and reading lists the reader pinned, one shelf each.
     *
     * `home-screen`, *The rest of the home surface*, fixes where they go: "recently added
     * publications, the reader's pinned shelves, and what they have finished", in that order.
     * Empty rather than absent when nothing is pinned, like every other list here.
     */
    val pinned: List<HomePinnedShelf> = emptyList(),
    val finished: List<HomeFinishedGroup> = emptyList(),
) {
    /**
     * Nothing at all to offer, so the surface is itself the first-run screen.
     *
     * Note that this is not "no history": a reader who owns books but has read none of
     * them has a Recently added shelf, and `home-screen` says that shelf leads the surface
     * then. Bare means the library is genuinely empty.
     */
    val isBare: Boolean
        get() = keepReading.isEmpty() && upNext.isEmpty() &&
            recentlyAdded.isEmpty() && finished.isEmpty()

    /**
     * Whether Keep reading is one large card instead of a carousel.
     *
     * `home-screen`: with fewer in-progress publications "than a carousel needs to make
     * sense", Keep reading "presents as a single large card rather than as a carousel of
     * one". One is that number — a carousel with a single item has nothing to browse and
     * every affordance of a thing that does.
     */
    val leadsWithOneCard: Boolean get() = keepReading.size == 1
}

/**
 * The home surface, built from local reading history and local metadata alone.
 *
 * Pure and free of Compose so it can be asserted on a plain JVM, and so the whole of
 * `home-screen`'s ordering, disjointness and degradation rules are testable without a
 * device. Nothing here can reach a network: the only inputs are the library the app already
 * holds, the progress records it already read, and a predicate the caller answers from
 * state it already has. That is not a convenience — it is the requirement "the home
 * surface never waits on a source", kept by construction rather than by discipline.
 *
 * Deliberately not in `core:model`: iOS's home surface is being written against the same
 * spec but is not a line-for-line mirror of this the way `LibraryIndex` is, and pretending
 * otherwise would put a shared type under two owners. What *is* shared is reached through
 * [LibraryIndex], which both platforms already mirror.
 */
object HomeShelves {

    /**
     * How many entries a shelf holds. Home is never exhaustive; the library is, and every
     * heading leads there.
     */
    const val SHELF_LENGTH: Int = 12

    private const val DAY_MILLIS = 24L * 60L * 60L * 1000L
    private const val WEEK_MILLIS = 7L * DAY_MILLIS
    private const val MONTH_MILLIS = 30L * DAY_MILLIS

    /**
     * @param publications everything the library holds, however it got there.
     * @param progress the local record for a publication, or null when it has never been
     *   opened. Local — ADR-0006 makes the on-device record authoritative, and a merge with
     *   a server arrives later as a new call with new records rather than as a wait.
     * @param isReadableNow whether the publication can be opened at this instant. The
     *   caller answers it, because whether a source is up is the app layer's knowledge and
     *   dragging the source registry in here would give this function a way to block.
     * @param nowEpochMillis the clock, passed in so the finished buckets are testable.
     */
    fun assemble(
        publications: List<Publication>,
        progress: (Publication) -> ReadingProgress?,
        isReadableNow: (Publication) -> Boolean,
        nowEpochMillis: Long,
        shelfLength: Int = SHELF_LENGTH,
        /** The reader's own groupings, so the pinned ones can be resolved. */
        shelves: Shelves = Shelves(),
        /** Which of them they asked to see here. */
        pinned: PinnedShelves = PinnedShelves(),
    ): HomeSurface {
        val state: (Publication) -> LibraryIndex.Progress = { LibraryIndex.Progress.of(progress(it)) }
        val entry: (Publication) -> HomeEntry = { entryOf(it, progress, isReadableNow) }

        // Straight through `LibraryIndex`, which both platforms already mirror and whose
        // ordering rule — most recently read first — is asserted in both test suites.
        // Nothing is dropped for being unreachable; that is what `isReadableNow` is for.
        // Keep reading, and only Keep reading, is asked the end-of-book question. It is the
        // one shelf whose card offers an action, and `LibraryIndex.next` is a scan of the
        // library per entry -- cheap over a shelf of six, wasteful over every shelf on the
        // surface for an answer nothing would draw.
        val keepReading = LibraryIndex
            .continueReading(publications, limit = shelfLength, progress = state)
            .map { publication ->
                val atTheEnd = isAtTheEnd(publication, progress(publication))
                entry(publication).copy(
                    isAtTheEnd = atTheEnd,
                    nextInSeries = if (atTheEnd) LibraryIndex.next(publication, publications) else null,
                )
            }

        return HomeSurface(
            keepReading = keepReading,
            upNext = upNext(publications, state, shelfLength).map(entry),
            recentlyAdded = recentlyAdded(publications, shelfLength).map(entry),
            pinned = pinnedShelves(publications, shelves, pinned, entry),
            finished = finished(publications, progress, nowEpochMillis, shelfLength)
                .map { (period, group) -> HomeFinishedGroup(period, group.map(entry)) },
        )
    }

    /**
     * The pinned collections and lists, resolved against the library.
     *
     * Collections first and then lists, which is the order the shelves screen shows them in
     * -- a reader who pinned two things should meet them here in the order they met them
     * there. Within each, `PinnedShelves.ordering` is *not* asked: it puts pinned ahead of
     * unpinned, and everything here is pinned already. The reader's own order is what the two
     * lists arrive in.
     *
     * **A collection is filtered out of the library and a reading list is walked**, and that
     * is the whole difference between the two types made concrete: a list's order carries
     * meaning, so its entries decide the order, and a member it names that the library does
     * not hold is skipped rather than left as a hole.
     */
    private fun pinnedShelves(
        publications: List<Publication>,
        shelves: Shelves,
        pinned: PinnedShelves,
        entry: (Publication) -> HomeEntry,
    ): List<HomePinnedShelf> {
        if (pinned.isEmpty) return emptyList()
        val byId = publications.associateBy { it.id }

        val collections = shelves.collections
            .filter { ShelfPin.Collection(it.id) in pinned }
            .map { collection ->
                HomePinnedShelf(
                    pin = ShelfPin.Collection(collection.id),
                    name = collection.name,
                    entries = publications.filter { it.id in collection.members }.map(entry),
                )
            }
        val lists = shelves.lists
            .filter { ShelfPin.ReadingListPin(it.id) in pinned }
            .map { list ->
                HomePinnedShelf(
                    pin = ShelfPin.ReadingListPin(list.id),
                    name = list.name,
                    entries = list.entries.mapNotNull { byId[it] }.map(entry),
                )
            }

        return (collections + lists).filter { it.entries.isNotEmpty() }
    }

    /**
     * The next unread issue of each series the reader has started.
     *
     * Three rules from `home-screen`, in the order they decide:
     *
     * 1. A series with something part-read contributes nothing — that issue is in Keep
     *    reading, and "the two shelves never offer the same publication at the same time".
     *    The successor waits until the part-read one is finished.
     * 2. A series with nothing finished has not been started, so there is no "next".
     * 3. The answer is the lowest-numbered unread issue *after* the highest-numbered
     *    finished one. A reader who has read #1 and #3 is offered #4, not #2: they skipped
     *    #2 on purpose, and a shelf that kept pushing it back at them is arguing.
     *
     * A series with nothing after it contributes nothing, silently — which is rule 3
     * finding no candidate, not a special case.
     *
     * Ordered by when the series was last touched, so the series a reader is actually
     * working through leads the shelf. `home-screen` fixes the order of Keep reading and
     * says nothing about this one; last-touched is the same answer for the same reason.
     */
    internal fun upNext(
        publications: List<Publication>,
        state: (Publication) -> LibraryIndex.Progress,
        shelfLength: Int,
    ): List<Publication> = publications
        .filter { it.series != null }
        .groupBy { it.series }
        .values
        .mapNotNull { issues -> nextInSeries(issues, state) }
        .sortedByDescending { it.second }
        .take(shelfLength)
        .map { it.first }

    /** The successor for one series, with the series' most recent reading timestamp. */
    private fun nextInSeries(
        issues: List<Publication>,
        state: (Publication) -> LibraryIndex.Progress,
    ): Pair<Publication, Long>? {
        var lastRead = 0L
        var highestFinished: Double? = null
        for (issue in issues) {
            val progress = state(issue)
            if (progress.state == ReadState.IN_PROGRESS) return null
            if (progress.state == ReadState.FINISHED) {
                lastRead = maxOf(lastRead, progress.lastReadEpochMillis ?: 0L)
                val number = issueNumber(issue)
                if (highestFinished == null || number > highestFinished) highestFinished = number
            }
        }
        val read = highestFinished ?: return null

        val next = issues
            .filter {
                state(it).state == ReadState.UNREAD && it.isOpenable && issueNumber(it) > read
            }
            .minByOrNull { issueNumber(it) }
            ?: return null

        return next to lastRead
    }

    /**
     * The newest arrivals.
     *
     * Not filtered on having a date. A file system does not always answer *when did this
     * arrive* — a folder copied wholesale, an archive restored from a backup — and a shelf
     * that emptied itself over that would take the library away from a reader whose books
     * are all perfectly present. When nothing has a date the order is the library's own,
     * which is the best answer available and not a wrong one. iOS reasons the same way.
     */
    private fun recentlyAdded(publications: List<Publication>, shelfLength: Int): List<Publication> =
        publications
            .sortedByDescending(::arrived)
            .take(shelfLength)

    /**
     * When a publication turned up, as well as anything knows.
     *
     * `Long.MIN_VALUE` for one that says nothing, which sorts it last without dropping it —
     * see [recentlyAdded] for why a shelf must not empty itself over a missing date.
     *
     * Internal because [SearchSuggestions] orders its own *never opened* section by the same
     * answer. Two readings of "when did this arrive" would put one screen's newest arrival
     * halfway down another's.
     */
    internal fun arrived(publication: Publication): Long =
        publication.addedAtEpochMillis ?: publication.modifiedAtEpochMillis ?: Long.MIN_VALUE

    /**
     * One publication as a shelf offers it.
     *
     * Lifted out of [assemble]'s local lambda so [SearchSuggestions] builds its entries the
     * same way rather than the near-same way: `pagesRemaining` and the fraction are both easy
     * to get subtly differently, and a suggestion that disagreed with Home about how much of
     * a book is left would be the same book described twice.
     */
    internal fun entryOf(
        publication: Publication,
        progress: (Publication) -> ReadingProgress?,
        isReadableNow: (Publication) -> Boolean,
    ): HomeEntry = LibraryIndex.Progress.of(progress(publication)).let { record ->
        HomeEntry(
            publication = publication,
            isReadableNow = isReadableNow(publication),
            pagesRemaining = pagesRemaining(publication, progress(publication)),
            fraction = record.fraction,
            state = record.state,
        )
    }

    /**
     * What has been finished, newest first, in three buckets.
     *
     * A record with the finished flag but no completion timestamp — one written before
     * `reading-progress` grew the field, or synced from a server that does not keep it —
     * falls back to when it was last updated. Dropping it would take a book the reader
     * definitely finished off the only shelf that admits it.
     */
    private fun finished(
        publications: List<Publication>,
        progress: (Publication) -> ReadingProgress?,
        nowEpochMillis: Long,
        shelfLength: Int,
    ): List<Pair<HomeFinishedPeriod, List<Publication>>> {
        val dated = publications.mapNotNull { publication ->
            val record = progress(publication) ?: return@mapNotNull null
            if (!record.isFinished) return@mapNotNull null
            publication to (record.finishedAtEpochMillis ?: record.updatedAtEpochMillis)
        }

        return HomeFinishedPeriod.entries.mapNotNull { period ->
            val group = dated
                .filter { periodOf(nowEpochMillis - it.second) == period }
                .sortedByDescending { it.second }
                .take(shelfLength)
                .map { it.first }
            if (group.isEmpty()) null else period to group
        }
    }

    private fun periodOf(ageMillis: Long): HomeFinishedPeriod = when {
        ageMillis < WEEK_MILLIS -> HomeFinishedPeriod.THIS_WEEK
        ageMillis < MONTH_MILLIS -> HomeFinishedPeriod.THIS_MONTH
        else -> HomeFinishedPeriod.EARLIER
    }

    /**
     * How many pages are left, in the reader's own terms.
     *
     * `home-screen` requires what is left to be stated "as pages or time remaining — rather
     * than as a percentage alone". A paged publication answers exactly: the position holds
     * the index and the total. A reflowable one holds a fraction, because ADR-0006 says a
     * reflowable page number is a function of the reader's typography — so it is turned
     * into pages only when the publication itself declares a page count, and is null
     * otherwise. Null means the surface says nothing, which is honest; a percentage would
     * be the thing the spec refuses.
     */
    fun pagesRemaining(publication: Publication, record: ReadingProgress?): Int? {
        if (record == null || record.isFinished) return null
        return when (val position = record.position) {
            is ReadingPosition.Page ->
                if (position.total > 1) (position.total - 1 - position.index).coerceAtLeast(0) else null

            is ReadingPosition.Reflowable -> publication.pageCount?.let { pages ->
                ((1.0 - position.progression.coerceIn(0.0, 1.0)) * pages).roundToInt().coerceAtLeast(0)
            }

            // A book being listened to has no pages left, and the spec's other unit — time
            // remaining — is not derivable here: the position carries the current part's
            // length and nothing about the ones after it. Null, which is the surface saying
            // nothing, rather than a page count invented from a chapter index.
            is ReadingPosition.Listening -> null
        }
    }

    /**
     * Whether a page or less of this publication is left to read.
     *
     * `home-screen`, *A publication with nothing meaningful left*: at that point the card
     * "offers to finish it — marking it read — and offers the next in its series where there
     * is one, rather than offering to reopen its last page". Reopening the last page is a
     * resume that resumes nothing: the reader turns one page and the book is done, and the
     * card was the only thing standing between them and the next one.
     *
     * **Not `pagesRemaining(...) == 0`, and the difference is the whole point.** That returns
     * null for four different situations — never opened, finished, an audiobook, and a
     * reflowable book that declares no page count — and a card that offered to finish an
     * unopened book because two of those were spelled the same way would be worse than one
     * that offered nothing. This asks the narrower question and answers false wherever it
     * cannot honestly answer true.
     */
    fun isAtTheEnd(publication: Publication, record: ReadingProgress?): Boolean {
        if (record == null || record.isFinished) return false
        return when (val position = record.position) {
            is ReadingPosition.Page -> position.total > 0 && position.total - 1 - position.index <= 0

            // The unit is not pages, and *time remaining* is not derivable from what the
            // position carries — see `pagesRemaining` for the full reasoning.
            is ReadingPosition.Listening -> false

            is ReadingPosition.Reflowable -> publication.pageCount?.let { pages ->
                pages > 0 &&
                    ((1.0 - position.progression.coerceIn(0.0, 1.0)) * pages).roundToInt() <= 0
            } ?: false
        }
    }

    /**
     * An issue number as a number, so #10 follows #9.
     *
     * The same three lines as `LibraryIndex.issueNumber`, which is private there. Repeated
     * rather than widened: the ordering rule belongs to the shared index, and prising it
     * open for one caller in one feature module is how a mirrored type stops being mirrored.
     * A publication with no number sorts last, which keeps a one-off out of the middle of a
     * numbered run — and, here, keeps an unnumbered special out of Up next.
     */
    private fun issueNumber(publication: Publication): Double =
        publication.number?.filter { it.isDigit() || it == '.' }?.toDoubleOrNull() ?: Double.MAX_VALUE
}
