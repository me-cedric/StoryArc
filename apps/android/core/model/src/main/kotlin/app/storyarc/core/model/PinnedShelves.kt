package app.storyarc.core.model

import java.util.UUID

/**
 * Which shelf a reader has pinned to the home surface.
 *
 * A collection and a reading list are deliberately different types — `Shelves.kt` says why at
 * length — so a pin has to name which kind it is. Two UUIDs colliding across the two is not a
 * thing that happens, and a pin that silently followed the wrong one would be a bug nobody
 * could reproduce.
 */
sealed interface ShelfPin {

    val id: UUID

    data class Collection(override val id: UUID) : ShelfPin

    data class ReadingListPin(override val id: UUID) : ShelfPin

    /**
     * The token this pin is written down as.
     *
     * A string rather than an ordinal, because these are stored in the same preferences both
     * platforms already use for scalars. `collection:` and `list:` so a stored value can be
     * read by a person looking at the file, and so reordering the declarations cannot
     * silently repoint every pin a reader has.
     */
    val token: String
        get() = when (this) {
            is Collection -> "collection:$id"
            is ReadingListPin -> "list:$id"
        }

    companion object {
        /**
         * A token read back, or `null` for anything this version does not understand.
         *
         * Null rather than a guess. An unreadable pin drops one shelf off the home surface,
         * which the reader can see and put back; a guessed one pins a shelf they never chose
         * and gives them nothing to undo.
         */
        fun of(token: String): ShelfPin? {
            val kind = token.substringBefore(':', missingDelimiterValue = "")
            val id = runCatching { UUID.fromString(token.substringAfter(':', "")) }.getOrNull()
                ?: return null
            return when (kind) {
                "collection" -> Collection(id)
                "list" -> ReadingListPin(id)
                else -> null
            }
        }
    }
}

/**
 * The shelves a reader has asked to see on the home surface, and the order that puts them in.
 *
 * `home-screen`, *Pinned shelves*: a pinned collection or reading list "appears on the home
 * surface as a shelf of its own, ahead of the unpinned ones", and "unpinning it removes the
 * shelf without altering the collection or the list".
 *
 * **That second clause is why this is a set of keys beside the shelves rather than a flag on
 * them.** An `isPinned` field on [PublicationCollection] and [ReadingList] would have to
 * survive a server pull, which rewrites a server-backed shelf wholesale — so pinning a Kavita
 * reading list and then syncing would either lose the pin or make the pull's overwrite
 * conditional, and a shelf's own record would carry a fact about the home screen. Held apart,
 * unpinning cannot alter a collection because it never touches one.
 *
 * Mirrors iOS's `PinnedShelves`, token for token, so the same preference read on either
 * platform means the same thing.
 */
@JvmInline
value class PinnedShelves(private val pins: Set<ShelfPin> = emptySet()) {

    val isEmpty: Boolean get() = pins.isEmpty()

    operator fun contains(pin: ShelfPin): Boolean = pin in pins

    /**
     * What to write down. Sorted, so two runs that pinned the same shelves produce the same
     * stored value and a diff of a preferences file is readable.
     */
    val tokens: List<String> get() = pins.map { it.token }.sorted()

    /**
     * Pinned if it was not, unpinned if it was. One action either way, because the control is
     * one control.
     */
    fun toggling(pin: ShelfPin): PinnedShelves =
        PinnedShelves(if (pin in pins) pins - pin else pins + pin)

    /**
     * The same shelves, pinned ones first.
     *
     * **Stable within each group**, which is the part worth stating: the reader's own order
     * survives inside the pinned run and inside the unpinned one, so pinning a shelf moves it
     * to the front and moves nothing else. A sort would have been shorter and would have
     * reshuffled everything the first time two shelves compared equal.
     *
     * Generic over the element so a collection and a reading list are ordered by one rule
     * asked twice, rather than by two rules that can disagree.
     */
    fun <T> ordering(shelves: List<T>, pin: (T) -> ShelfPin): List<T> =
        shelves.filter { pin(it) in pins } + shelves.filterNot { pin(it) in pins }

    companion object {
        /**
         * Where the choice is written down. Its own key, beside the other library
         * preferences, so nothing has to be migrated to add it.
         */
        const val STORAGE_KEY = "app.storyarc.pinnedShelves"

        /** Read back from stored tokens, dropping any this version cannot parse. */
        fun of(tokens: Collection<String>): PinnedShelves =
            PinnedShelves(tokens.mapNotNull(ShelfPin::of).toSet())
    }
}
