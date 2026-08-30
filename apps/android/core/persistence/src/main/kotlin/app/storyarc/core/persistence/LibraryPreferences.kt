package app.storyarc.core.persistence

import android.content.Context
import android.content.SharedPreferences
import app.storyarc.core.model.LibraryLayout
import app.storyarc.core.model.LibraryQuery
import app.storyarc.core.model.LibraryScope
import app.storyarc.core.model.LibrarySort
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.ReadState
import app.storyarc.core.model.RecentSearches
import app.storyarc.core.model.YearRange

/**
 * How the library was left, remembered across launches.
 *
 * `library-browsing`: "when a user leaves the library and returns, active filters
 * are still applied", and a layout choice "persists per scope, so a dense list for
 * one library does not force it everywhere". Both are a handful of small values
 * read once at launch, so they live in [SharedPreferences] rather than the Room
 * database — opening the progress store before the first screen to learn a sort
 * order would be a strange trade. iOS's `LibraryPreferences` keeps the same values
 * in `UserDefaults`.
 *
 * The values are written as their enum names rather than their ordinals. An
 * ordinal is a position in a source file, and reordering [LibrarySort] would
 * silently change what a user's stored preference means.
 */
class LibraryPreferences(private val preferences: SharedPreferences) {

    companion object {
        fun open(context: Context): LibraryPreferences =
            LibraryPreferences(
                context.getSharedPreferences("app.storyarc.library", Context.MODE_PRIVATE),
            )

        private const val SORT = "sort"
        private const val ASCENDING = "ascending"
        private const val READ_STATES = "readStates"
        private const val FORMATS = "formats"
        private const val LANGUAGES = "languages"
        private const val SCOPE = "scope"
        private const val PUBLISHERS = "publishers"
        private const val GENRES = "genres"
        private const val TAGS = "tags"
        private const val YEAR_FROM = "yearFrom"
        private const val YEAR_TO = "yearTo"
        private const val LAYOUT = "layout"
        private const val RECENT_SEARCHES = "recentSearches"

        /**
         * What the stored searches are joined with.
         *
         * A set would lose the order, and the order is the whole point of a recent
         * list — [SharedPreferences] has no ordered collection, so one string it is.
         * A newline cannot appear in a term: the search field is single-line, and
         * the value is trimmed before it is kept.
         */
        private const val SEPARATOR = "\n"
    }

    /**
     * The stored query, or a fresh one.
     *
     * The search term is deliberately never stored. A filter is a decision that
     * outlives a session; a half-typed search is not, and reopening the app to a
     * library narrowed by a word typed yesterday reads as a bug.
     */
    fun query(): LibraryQuery = LibraryQuery(
        readStates = readStates(),
        formats = formats(),
        languages = strings(LANGUAGES),
        publishers = strings(PUBLISHERS),
        genres = strings(GENRES),
        tags = strings(TAGS),
        years = YearRange(from = year(YEAR_FROM), to = year(YEAR_TO)),
        sort = enumOrNull<LibrarySort>(preferences.getString(SORT, null)) ?: LibrarySort.TITLE,
        ascending = preferences.getBoolean(ASCENDING, true),
        // `library-browsing`: the scope "persists until changed", so it is stored with the
        // filters rather than forgotten with the session.
        scope = LibraryScope.of(preferences.getString(SCOPE, null)),
    )

    fun save(query: LibraryQuery) {
        val editor = preferences.edit()
            .putString(SORT, query.sort.name)
            .putBoolean(ASCENDING, query.ascending)
            .putStringSet(READ_STATES, query.readStates.map { it.name }.toSet())
            .putStringSet(FORMATS, query.formats.map { it.name }.toSet())
            .putStringSet(LANGUAGES, query.languages)
            .putStringSet(PUBLISHERS, query.publishers)
            .putStringSet(GENRES, query.genres)
            .putStringSet(TAGS, query.tags)
            .putString(SCOPE, query.scope.storageKey)
        // Removed rather than written as a sentinel. An absent bound is one of the
        // three states a range has, and a stored -1 would come back as a filter the
        // reader never set.
        putYear(editor, YEAR_FROM, query.years.from)
        putYear(editor, YEAR_TO, query.years.to)
        editor.apply()
    }

    /**
     * The searches offered when the reader opens the field.
     *
     * Kept although the half-typed term above is not, and the two are not in
     * conflict: a finished search is something the reader did, and a library that
     * forgot every one of them between launches would offer an empty list to
     * exactly the reader `library-browsing` wrote the requirement for.
     */
    fun recentSearches(): RecentSearches = RecentSearches(
        preferences.getString(RECENT_SEARCHES, null)
            ?.split(SEPARATOR)
            ?.filter { it.isNotBlank() }
            .orEmpty(),
    )

    fun save(searches: RecentSearches) {
        preferences.edit()
            .putString(RECENT_SEARCHES, searches.terms.joinToString(SEPARATOR))
            .apply()
    }

    /**
     * The layout for one scope.
     *
     * `library-browsing`: the choice "persists per scope, so a dense list for one library
     * does not force it everywhere" — a reader who wants covers for their comics and a list
     * for their server's catalogue gets both.
     *
     * One key per scope rather than one blob. A scope arrives and leaves with its source, and
     * a blob would have to be pruned when a source is removed by something that currently has
     * no reason to know this file exists.
     *
     * A scope never set falls back to what was stored before the layout was per scope, so a
     * reader who chose the list is not handed the grid again by an upgrade.
     */
    fun layout(scope: LibraryScope = LibraryScope.AllSources): LibraryLayout =
        enumOrNull<LibraryLayout>(preferences.getString(key(scope), null))
            ?: enumOrNull<LibraryLayout>(preferences.getString(LAYOUT, null))
            ?: LibraryLayout.GRID

    fun save(layout: LibraryLayout, scope: LibraryScope = LibraryScope.AllSources) {
        preferences.edit().putString(key(scope), layout.name).apply()
    }

    /** One stored facet, or an empty set when nothing was ever written for it. */
    private fun strings(key: String): Set<String> =
        preferences.getStringSet(key, emptySet()).orEmpty()

    private fun year(key: String): Int? =
        if (preferences.contains(key)) preferences.getInt(key, 0) else null

    private fun putYear(editor: SharedPreferences.Editor, key: String, value: Int?) {
        if (value == null) editor.remove(key) else editor.putInt(key, value)
    }

    /** One key per scope, so a source's layout leaves with the source. */
    private fun key(scope: LibraryScope): String = "$LAYOUT.${scope.storageKey}"

    private fun readStates(): Set<ReadState> =
        preferences.getStringSet(READ_STATES, emptySet()).orEmpty()
            .mapNotNull { enumOrNull<ReadState>(it) }
            .toSet()

    private fun formats(): Set<PublicationFormat> =
        preferences.getStringSet(FORMATS, emptySet()).orEmpty()
            .mapNotNull { enumOrNull<PublicationFormat>(it) }
            .toSet()

    /**
     * A stored name turned back into a value, or `null`.
     *
     * A name that no longer exists is dropped rather than crashing the launch: a
     * format removed from the app is not a reason to refuse to open it.
     */
    private inline fun <reified T : Enum<T>> enumOrNull(name: String?): T? =
        name?.let { runCatching { enumValueOf<T>(it) }.getOrNull() }
}
