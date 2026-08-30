package app.storyarc.core.persistence

import android.content.Context
import android.content.SharedPreferences
import app.storyarc.core.model.LibraryLayout
import app.storyarc.core.model.LibraryQuery
import app.storyarc.core.model.LibraryScope
import app.storyarc.core.model.LibrarySort
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.ReadState

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
        private const val LAYOUT = "layout"
        private const val SCOPE = "scope"
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
        languages = preferences.getStringSet(LANGUAGES, emptySet()).orEmpty(),
        sort = enumOrNull<LibrarySort>(preferences.getString(SORT, null)) ?: LibrarySort.TITLE,
        ascending = preferences.getBoolean(ASCENDING, true),
        // `library-browsing`: the scope "persists until changed", so it is stored with the
        // filters rather than forgotten with the session.
        scope = LibraryScope.of(preferences.getString(SCOPE, null)),
    )

    fun save(query: LibraryQuery) {
        preferences.edit()
            .putString(SORT, query.sort.name)
            .putBoolean(ASCENDING, query.ascending)
            .putStringSet(READ_STATES, query.readStates.map { it.name }.toSet())
            .putStringSet(FORMATS, query.formats.map { it.name }.toSet())
            .putStringSet(LANGUAGES, query.languages)
            .putString(SCOPE, query.scope.storageKey)
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
