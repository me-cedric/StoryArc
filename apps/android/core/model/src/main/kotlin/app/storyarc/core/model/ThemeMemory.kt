package app.storyarc.core.model

import kotlinx.serialization.Serializable

/**
 * Which family of publication a stored theme belongs to.
 *
 * `reading-themes`: a theme set on a reflowable publication "does not change the
 * theme used for comics or fixed-layout publications, which have their own default".
 * Two scopes rather than one, because the two are read differently — a line height
 * means nothing to a page of artwork, and a reader who wants cream paper for novels
 * may well want black behind a comic.
 */
@Serializable
enum class ThemeScope { REFLOWABLE, FIXED_LAYOUT }

/**
 * A theme and the typography in force under it.
 *
 * Both halves. A reader who moved the line height chose a preset *and* a deviation
 * from it, and storing only the preset would silently put that deviation back on the
 * next open — losing work the reader can see they did.
 */
@Serializable
data class StoredTheme(
    val theme: ReadingTheme = ReadingTheme(),
    val values: ThemeValues = theme.preset.values,
)

/**
 * What the reader has chosen, remembered at the level they would expect.
 *
 * `reading-themes` asks for three things that are one data structure: a theme applies
 * to every publication in the same series; a global default covers series never
 * opened; and changing that default does not overwrite a per-series choice already
 * made. The third falls out of keeping the two apart rather than out of any logic —
 * `settingDefault` cannot reach a shelf entry because it does not touch that map.
 */
@Serializable
data class ThemeMemory(
    /**
     * Per shelf, keyed by scope and shelf together. A series called "Bone" can hold
     * both a comic and an ebook, and the two must not share an entry.
     */
    private val shelves: Map<String, StoredTheme> = emptyMap(),
    /** The fallback for a shelf never opened, one per scope. */
    private val defaults: Map<String, StoredTheme> = emptyMap(),
) {
    /** The theme for a shelf: its own if it has one, else the scope's default. */
    fun theme(scope: ThemeScope, shelf: String): StoredTheme =
        shelves[key(scope, shelf)] ?: defaults[scope.name] ?: StoredTheme()

    /** The scope's default on its own, for a settings screen to show and change. */
    fun default(scope: ThemeScope): StoredTheme = defaults[scope.name] ?: StoredTheme()

    /** Remembers a choice made while reading, for this shelf alone. */
    fun remembering(stored: StoredTheme, scope: ThemeScope, shelf: String): ThemeMemory =
        copy(shelves = shelves + (key(scope, shelf) to stored))

    /**
     * Changes what a shelf never opened will get.
     *
     * `reading-themes`: this "applies to publications opened from then on and does not
     * overwrite a per-series choice already made" — which is why it writes to a
     * different map rather than sweeping the first one.
     */
    fun settingDefault(stored: StoredTheme, scope: ThemeScope): ThemeMemory =
        copy(defaults = defaults + (scope.name to stored))

    /** Whether this shelf has a choice of its own, as opposed to inheriting one. */
    fun remembers(scope: ThemeScope, shelf: String): Boolean =
        shelves.containsKey(key(scope, shelf))

    private fun key(scope: ThemeScope, shelf: String) = "${scope.name}/$shelf"

    companion object {
        /**
         * The key a publication remembers its theme under.
         *
         * Its series where it has one, and its own identity where it does not — a
         * standalone book is a series of one. Keying a standalone book to the global
         * default instead would mean reading one novel in sepia changed every other
         * book in the library.
         */
        fun shelf(series: String?, identity: String): String =
            series?.trim()?.takeIf { it.isNotEmpty() } ?: identity
    }
}
