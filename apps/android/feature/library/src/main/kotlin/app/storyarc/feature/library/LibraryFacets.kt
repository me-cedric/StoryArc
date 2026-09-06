package app.storyarc.feature.library

import app.storyarc.core.model.PublicationFormat
import java.text.Collator
import java.util.Locale

/**
 * What the filter menu is allowed to offer.
 *
 * Every one of these is the same question — *which values does the library actually hold* —
 * and `library-browsing` gives the same answer for all of them: the filter never offers a
 * value that would empty the shelf, because a menu entry that leads to nothing is a control
 * that lies. [LibraryFilterMenu] is the only caller.
 *
 * Extensions rather than members, and they moved here from [LibraryViewModel] without a
 * change: they read the published library and nothing private, so nothing about them needed
 * to be inside the class. That file is over the 800-line cap recorded in
 * `scripts/line-cap.mjs`, which means it may shrink and may not grow — and six derived lists
 * over one public flow are exactly the kind of thing that does not have to live in a view
 * model that six screens already share.
 */
fun LibraryViewModel.availableFormats(): List<PublicationFormat> =
    publications.value.map { it.format }.distinct().sortedBy { it.displayName }

/**
 * Languages actually present, as codes. The screen names them for the reader.
 *
 * Collated like the other three even though a language tag is ASCII: nothing validates what a
 * `ComicInfo.xml` writes into `<LanguageISO>`, so a mis-tagged file spelling the language out
 * reaches this list as it is spelled.
 */
fun LibraryViewModel.availableLanguages(locale: Locale = readerLocale()): List<String> =
    publications.value.mapNotNull { it.language }.distinct().collated(locale)

/** Publishers actually present, as the files spell them. */
fun LibraryViewModel.availablePublishers(locale: Locale = readerLocale()): List<String> =
    publications.value.mapNotNull { it.publisher }.distinct().collated(locale)

/** Genres actually present, gathered from every publication's list. */
fun LibraryViewModel.availableGenres(locale: Locale = readerLocale()): List<String> =
    publications.value.flatMap { it.genres }.distinct().collated(locale)

/** Tags actually present. Kept apart from [availableGenres] because the files do. */
fun LibraryViewModel.availableTags(locale: Locale = readerLocale()): List<String> =
    publications.value.flatMap { it.tags }.distinct().collated(locale)

/**
 * The decades the library spans, newest first.
 *
 * `library-browsing` asks for a year *range*, and `LibraryQuery.years` carries an arbitrary
 * one — which is what the tests assert and what a future control will set. What the menu
 * offers is decades, because a menu cannot ask for two numbers without becoming a form, and a
 * decade is a range a reader picks in one tap. Derived from the years actually present, so the
 * filter never offers a decade the library has nothing in.
 */
fun LibraryViewModel.availableDecades(): List<Int> =
    publications.value.mapNotNull { it.year }.map { it - it % 10 }.distinct().sortedDescending()

/**
 * Filter values in the order a reader of [locale] reads them.
 *
 * A bare `sorted()` is Kotlin's `compareTo` on `String`, which is UTF-16 unit order: *É* is
 * U+00C9 and *Z* is U+005A, so every accented value landed after every unaccented one and a
 * French reader found *Éditions* past *Zenith*. That is not the wrong collation, it is none —
 * the shelf, the search results and a reading list all collate and this menu did not.
 *
 * `Collator.SECONDARY` against the reader's locale, which is the comparison `LibraryIndex`
 * gives the shelf, so a value is filed in one place wherever it is drawn. Without
 * `LibraryIndex.sortKey`, though: that strips a leading article so a title files under its
 * first real word, and `library-browsing` asks for it on **titles**. A publisher named *The
 * Comic Company* is a name, not a title, and filing it under C would be a behaviour no
 * requirement asks for.
 *
 * `compareTo` breaks a tie, and it is not decoration. `SECONDARY` calls *marvel* and *Marvel*
 * equal while `distinct()` keeps them as two values, so the menu could draw them either way
 * round. It decides only between values that collate equal.
 *
 * The collator is built once per sort rather than once per comparison, which is what
 * `LibraryIndex.arrange` does and for the same reason.
 *
 * The locale is a parameter, and the four callers above default it rather than fetching it:
 * `readerLocale()` decodes the settings blob on every call, and [LibraryFilterMenu] asks four
 * of these functions for their values on every recomposition of the open menu. So the menu
 * remembers one locale and hands it to all four, exactly as `LibraryIndex.arrange` is handed
 * one. The default keeps a caller with no locale in hand honest, and a test that chooses a
 * language still proves the choice reaches the sort.
 *
 * iOS does not carry the parameter, and the platform forces that: `Locale.storyArc` reads a
 * tag already in memory, so a facet fetching its own costs a `Locale.Components` build and no
 * file at all.
 */
private fun List<String>.collated(locale: Locale): List<String> {
    val collator = Collator.getInstance(locale).apply { strength = Collator.SECONDARY }
    return sortedWith { left, right ->
        val byReader = collator.compare(left, right)
        if (byReader != 0) byReader else left.compareTo(right)
    }
}
