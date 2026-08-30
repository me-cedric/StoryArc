package app.storyarc.core.model

import java.util.UUID

/**
 * Which source the library is showing.
 *
 * `library-browsing`'s first requirement: the app "SHALL present a single library spanning
 * every source", and "SHALL let the user narrow it to one source". Both halves are this one
 * value — the library is everything unless a scope says otherwise.
 *
 * Two cases rather than a nullable identifier. `null` reads as "no source" where the meaning
 * is "all of them", and this value is written down and read back: a name survives a round
 * trip through a preference file in a way a null does not.
 *
 * iOS's `LibraryScope` mirrors it. The narrowing case is [OneSource] rather than `Source`
 * because [app.storyarc.core.model.Source] is next door in this package and one of the two
 * would have had to be qualified at every use.
 */
sealed interface LibraryScope {
    data object AllSources : LibraryScope

    data class OneSource(val id: UUID) : LibraryScope

    /** The source this narrows to, or `null` when it narrows to nothing. */
    val sourceId: UUID?
        get() = (this as? OneSource)?.id

    /**
     * What storage calls this scope.
     *
     * A name rather than a position, for the reason `LibraryPreferences` gives for storing
     * every other enum by name: an ordinal is a line number in a source file, and moving a
     * case would silently change what a reader's stored preference means. It is also the key
     * the per-scope layout hangs off, which is why it is one string and not two stored
     * fields.
     */
    val storageKey: String
        get() = when (this) {
            AllSources -> ALL
            is OneSource -> id.toString()
        }

    /**
     * Whether a publication is part of what this scope shows.
     *
     * A publication with no source is only ever in "all sources". It came from somewhere the
     * reader did not configure — a file another app handed over — and attributing it to
     * whichever source happens to be selected would be a guess.
     */
    fun contains(publication: Publication): Boolean = when (this) {
        AllSources -> true
        is OneSource -> publication.sourceId == id
    }

    /**
     * The same scope, or every source when the one it names has gone.
     *
     * Asked when the library is drawn rather than when a source is removed. Removal happens
     * in one place and the scope is read in several, and the case that matters — a scope
     * restored at launch that points at a source removed in the last session — has no
     * removal to hang off at all.
     */
    fun resolved(registry: SourceRegistry): LibraryScope = when (this) {
        AllSources -> this
        is OneSource -> if (registry[id] == null) AllSources else this
    }

    companion object {
        private const val ALL = "all"

        /**
         * A scope read back from storage.
         *
         * Anything that is not a source identifier is every source. A stored scope naming a
         * source the reader has since removed would otherwise open the library on an empty
         * shelf with nothing to explain it, which is the silent narrowing `library-browsing`
         * forbids — and "all sources" is the one answer that is never wrong.
         */
        fun of(storageKey: String?): LibraryScope {
            if (storageKey == null || storageKey == ALL) return AllSources
            return runCatching { OneSource(UUID.fromString(storageKey)) }.getOrDefault(AllSources)
        }
    }
}

/**
 * The publications one scope shows, before any filter or search.
 *
 * Separate from [LibraryIndex.arrange] because the continue-reading row needs the same
 * narrowing and none of the rest: `library-browsing` requires a scope to apply to "the view,
 * its search, and its filters", and a shortcut row that offered a publication from a source
 * the reader has scoped away is a row that leads out of the library they asked for.
 */
fun LibraryIndex.inScope(
    publications: List<Publication>,
    scope: LibraryScope,
): List<Publication> =
    if (scope == LibraryScope.AllSources) publications else publications.filter(scope::contains)

/**
 * Whether the library should say where each publication came from.
 *
 * `library-browsing`: a publication "shows its source only when more than one source is
 * configured". With one source the label is on every row and distinguishes nothing from
 * nothing, which is noise wearing the clothes of information.
 */
val SourceRegistry.attributesPublications: Boolean
    get() = sources.size > 1

/**
 * Every scope the library can be narrowed to, in the reader's own order.
 *
 * The registry's order, because `sources` makes that order meaningful and a selector that
 * reshuffled it would undo an arrangement the reader made by hand.
 */
val SourceRegistry.scopes: List<LibraryScope>
    get() = listOf(LibraryScope.AllSources) + sources.map { LibraryScope.OneSource(it.id) }

/**
 * What a source is called, for a row that carries its name.
 *
 * `null` for a publication no source claims, which a row draws as nothing at all rather than
 * as "Unknown" — the reader is not missing a fact, there is no fact.
 */
fun SourceRegistry.nameOf(id: UUID?): String? = id?.let { this[it]?.displayName }
