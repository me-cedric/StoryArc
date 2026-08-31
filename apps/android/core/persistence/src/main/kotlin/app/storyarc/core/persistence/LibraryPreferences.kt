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
        private const val AVAILABILITY = "availability"
        private const val SEARCH_SCOPE = "searchScope"
        private const val DOWNLOAD_FILTER = "downloadFilter"

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

    /**
     * The library's availability axis, by name, or `null` when the reader never chose.
     *
     * `library-browsing` makes availability the primary axis and says the choice "persists
     * until changed" — until changed, not until the process dies. A shelf narrowed to what
     * is on the device and then reopened wide is the app quietly undoing a decision the
     * reader made, and the reader has no way to know it happened.
     *
     * Its own key beside the query's, in the same file, because it is not a field on
     * [LibraryQuery]: the query is the value both platforms encode, and a case added to it is
     * a change to `:core:model` and to iOS's mirror of it. iOS reaches the identical
     * arrangement from the other side — `@AppStorage(LibraryAvailability.storageKey)` writes
     * into the same `UserDefaults` the rest of the library's preferences use. Nothing is
     * migrated on either platform.
     *
     * A name rather than a value, because both enums live in `:feature:library` and this
     * module does not depend on a feature module. The name is the whole contract: the feature
     * turns it back into a choice and falls back to its own default when it cannot, which is
     * the rule [enumOrNull] already applies to every other stored enum here.
     */
    fun availability(): String? = preferences.getString(AVAILABILITY, null)

    fun saveAvailability(choice: String) {
        preferences.edit().putString(AVAILABILITY, choice).apply()
    }

    /**
     * What the **search screen** is narrowed to, by name, or `null` when the reader never
     * chose.
     *
     * A second key rather than [availability]'s, because the two are the same question asked
     * about different screens. `navigation-shell` promises a reader leaving search "return to
     * the destination they were on, with its scroll position and filters intact" — and a
     * shared key would have narrowing a search on a train silently narrow the shelf they go
     * back to, which is a filter they never set and would have to find to undo.
     *
     * `library-browsing` asks the search choice to persist "until changed" in its own right,
     * so it needs somewhere of its own to persist to. `rememberSaveable` is not that: it dies
     * with the process, and a launch is not a change. iOS reaches the identical arrangement
     * from the other side, under `LibraryAvailability.searchScopeKey`.
     */
    fun searchScope(): String? = preferences.getString(SEARCH_SCOPE, null)

    fun saveSearchScope(choice: String) {
        preferences.edit().putString(SEARCH_SCOPE, choice).apply()
    }

    /**
     * The download facet, by name, or `null` when the reader never chose.
     *
     * Beside [availability] and not inside it, for the reason the facet itself gives: the two
     * ask different questions. Stored the same way and for the same clause —
     * `library-browsing` asks that "when a user leaves the library and returns, active
     * filters are still applied".
     */
    fun downloadFilter(): String? = preferences.getString(DOWNLOAD_FILTER, null)

    fun saveDownloadFilter(choice: String) {
        preferences.edit().putString(DOWNLOAD_FILTER, choice).apply()
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
