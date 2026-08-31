package app.storyarc.feature.library

import app.storyarc.core.model.PublicationFormat

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

/** Languages actually present, as codes. The screen names them for the reader. */
fun LibraryViewModel.availableLanguages(): List<String> =
    publications.value.mapNotNull { it.language }.distinct().sorted()

/** Publishers actually present, as the files spell them. */
fun LibraryViewModel.availablePublishers(): List<String> =
    publications.value.mapNotNull { it.publisher }.distinct().sorted()

/** Genres actually present, gathered from every publication's list. */
fun LibraryViewModel.availableGenres(): List<String> =
    publications.value.flatMap { it.genres }.distinct().sorted()

/** Tags actually present. Kept apart from [availableGenres] because the files do. */
fun LibraryViewModel.availableTags(): List<String> =
    publications.value.flatMap { it.tags }.distinct().sorted()

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
