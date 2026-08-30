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
 * Everything a shelf is read with.
 *
 * The theme *and* the typography, because a reader who moved the line height chose a
 * preset and a deviation from it, and storing only the preset would silently put that
 * deviation back on the next open — losing work they can see they did.
 *
 * The page transition is here for the reason `comic-reader` gives: mode persistence
 * is word for word the same rule as theme persistence — per series, with a global
 * default, and comics independent of reflowable. One store, or two that have to be
 * kept in step.
 *
 * @property transition what the reader chose, not necessarily what runs.
 *   `page-transitions` is explicit that a stored Curl survives being opened on a
 *   device without one.
 * @property scrollAxis null means "whatever the publication implies", which is the
 *   default and the only value that can follow a webtoon into vertical unprompted.
 * @property readingDirection null means "whatever the publication's metadata declares",
 *   for the same reason the axis defaults to nothing: it is the only value that can
 *   follow a manga into right-to-left unprompted. `comic-reader` remembers an override
 *   "for the series", and per series is exactly what this store is.
 * @property adjustments what to do to a page before it is shown. `comic-reader` requires an
 *   adjustment to apply "to the series and [not be] applied globally", which is what this
 *   store is.
 * @property offsetsSpreads whether facing pages are paired one page later than they would be
 *   by default. `comic-reader`: "the user can offset the pairing by one page, for
 *   publications whose cover throws the pairing off". Per shelf, because whether a series
 *   prints its cover as part of the pagination is a fact about the series, not about the
 *   reader — they should not have to say it again for issue two.
 * @property showsPageSeparator whether a continuous scroll draws a line where one page ends
 *   and the next begins. `comic-reader`: pages are "stitched with no gap by default, with an
 *   option to show a separator". Default off, because a webtoon is drawn to be read as one
 *   strip and a line across it is a seam its author did not put there.
 * @property fit how a page is sized on the screen. `comic-reader` requires the fit to persist
 *   "per series", and per series is exactly what this store is; it used to be one value for
 *   the whole library, so fit-to-width chosen for a manga changed how every other comic
 *   opened. A shelf that has never been told inherits the scope's default, the way every
 *   other value here does — and that default is seeded once from the old global value (see
 *   `ReaderPreferences.themes()`), so a reader who had chosen
 *   fit-to-width keeps opening at fit-to-width rather than being quietly returned to
 *   fit-to-screen on the day they update.
 */
@Serializable
data class ShelfSettings(
    val theme: ReadingTheme = ReadingTheme(),
    val values: ThemeValues = theme.preset.values,
    val transition: PageTransition = PageTransition.SLIDE,
    val scrollAxis: ScrollAxis? = null,
    val readingDirection: ReadingDirection? = null,
    val adjustments: ImageAdjustments = ImageAdjustments(),
    val offsetsSpreads: Boolean = false,
    val showsPageSeparator: Boolean = false,
    val fit: PageFit = PageFit.SCREEN,
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
data class ShelfMemory(
    /**
     * Per shelf, keyed by scope and shelf together. A series called "Bone" can hold
     * both a comic and an ebook, and the two must not share an entry.
     */
    private val shelves: Map<String, ShelfSettings> = emptyMap(),
    /** The fallback for a shelf never opened, one per scope. */
    private val defaults: Map<String, ShelfSettings> = emptyMap(),
) {
    /** The theme for a shelf: its own if it has one, else the scope's default. */
    fun theme(scope: ThemeScope, shelf: String): ShelfSettings =
        shelves[key(scope, shelf)] ?: defaults[scope.name] ?: ShelfSettings()

    /** The scope's default on its own, for a settings screen to show and change. */
    fun default(scope: ThemeScope): ShelfSettings = defaults[scope.name] ?: ShelfSettings()

    /** Remembers a choice made while reading, for this shelf alone. */
    fun remembering(stored: ShelfSettings, scope: ThemeScope, shelf: String): ShelfMemory =
        copy(shelves = shelves + (key(scope, shelf) to stored))

    /**
     * Changes what a shelf never opened will get.
     *
     * `reading-themes`: this "applies to publications opened from then on and does not
     * overwrite a per-series choice already made" — which is why it writes to a
     * different map rather than sweeping the first one.
     */
    fun settingDefault(stored: ShelfSettings, scope: ThemeScope): ShelfMemory =
        copy(defaults = defaults + (scope.name to stored))

    /**
     * Forgets every scope's default, and nothing else.
     *
     * What "reset settings to defaults" has to mean here. `settings-and-about` requires the
     * reset to state that "sources, downloads, and reading progress are not affected", and
     * a reader's *per-series* choices are none of those three but are equally not settings
     * — they are decisions made while reading. So a reset returns what the settings screen
     * can set and leaves what the reader set in place.
     */
    fun clearingDefaults() = copy(defaults = emptyMap())

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
