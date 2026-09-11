package app.storyarc.core.model

import java.util.UUID

/** Which of the two ideas a remembered shelf is. */
enum class RememberedShelfKind { COLLECTION, READING_LIST }

/**
 * A shelf a server told the app about, written down so the home surface can name it.
 *
 * `home-screen` requires the home surface to be assembled from "local curation alone" and to
 * render "with the same shelves in the same order as when the sources are up". A server's
 * collections and reading lists are fetched once per visit to the shelves screen and were
 * then discarded, so the home surface had no name to draw and could not get one without
 * asking a server -- which is the one thing that requirement forbids. `ShelfCard` names that
 * as a gap rather than a decision. This is the memory that closes it.
 *
 * **Not a [PublicationCollection] with [ShelfOrigin.Server].** [Shelves] is the reader's own
 * store: `AddToShelfSheet` offers every collection in it as a place to put a publication,
 * `ShelfEditQueue` tracks pending edits against it, and the shelves screen draws all of it as
 * locally owned. A server's shelf put in there would appear in all three and be honoured by
 * none. A record beside it costs one preference key.
 *
 * Mirrors iOS's `RememberedShelf`, token for token.
 */
data class RememberedShelf(
    val kind: RememberedShelfKind,
    /** The source the shelf came from, which is also how a removed source takes it away. */
    val sourceId: UUID,
    /** The server's own numbering for it, which is what opens it again. */
    val serverId: Int,
    val title: String,
) {

    /**
     * The token this shelf is written down as.
     *
     * Modelled on [ShelfPin.token]: a word and an identity, readable by a person looking at a
     * preferences file, and immune to a declaration being reordered. **The title is last**, so
     * a title holding a colon survives a parse that splits at most three times -- and
     * "Batman: Year One" is the ordinary case rather than the awkward one.
     */
    val token: String
        get() = "${kind.word}:$sourceId:$serverId:$title"

    companion object {

        /**
         * A token read back, or `null` for anything this version cannot read.
         *
         * Null rather than a guess, for [ShelfPin.of]'s reason: a shelf that goes missing from
         * the home surface reappears the next time the shelves screen asks a server, where a
         * guessed one would point at whatever the server now numbers that way.
         */
        fun of(token: String): RememberedShelf? {
            val parts = token.split(":", limit = 4)
            if (parts.size != 4) return null
            val kind = RememberedShelfKind.entries.firstOrNull { it.word == parts[0] } ?: return null
            val sourceId = runCatching { UUID.fromString(parts[1]) }.getOrNull() ?: return null
            val serverId = parts[2].toIntOrNull() ?: return null
            if (parts[3].isEmpty()) return null
            return RememberedShelf(kind, sourceId, serverId, parts[3])
        }

        /** Every shelf a stored record holds, dropping any token this version cannot read. */
        fun of(tokens: Collection<String>): List<RememberedShelf> = tokens.mapNotNull(::of)

        /**
         * What to write down. Sorted, so two fetches that found the same shelves produce the
         * same stored value and a diff of a preferences file is readable.
         */
        fun tokens(shelves: Collection<RememberedShelf>): List<String> =
            shelves.map { it.token }.sorted()
    }
}

/**
 * The word a kind is written down as.
 *
 * `collection` and `list` rather than an ordinal, and the same two words [ShelfPin] already
 * uses, so one reader of a preferences file learns one vocabulary.
 */
internal val RememberedShelfKind.word: String
    get() = when (this) {
        RememberedShelfKind.COLLECTION -> "collection"
        RememberedShelfKind.READING_LIST -> "list"
    }
