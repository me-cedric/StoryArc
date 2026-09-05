package app.storyarc.core.model

/**
 * The series line to draw under a title, or `null` when it would only repeat it.
 *
 * **A title inferred from a filename is often the series and the number joined back together.**
 * `Broken Transfer.cbz` becomes a publication whose title *and* series are both
 * `Broken Transfer`, so a surface that draws the title and then the series under it says the
 * same thing twice. Case-insensitive, because a difference of case between the two is not a
 * second fact about the publication.
 *
 * **This rule already existed on both platforms and the publication page did not use it.**
 * `PublicationSeries.kt` has held it for the grid and list captions since those were written,
 * iOS has held it in `SeriesLine.swift`, and the page's own subtitle joined the series, number
 * and year with nothing comparing any of them to the title — photographed on 2026-09-05,
 * reading `Broken Transfer` in the app bar and `Broken Transfer` immediately beneath.
 *
 * It lives here rather than in `feature/library` because a **third** caller needs it:
 * `SearchResult.held` puts the series in a row's detail line, under the title, and cannot see
 * the feature module. That file's own warning — "Two copies of this rule disagreeing would make
 * the layout toggle change what a publication says it is" — is the argument for one primitive
 * with thin overloads over it, which is the shape iOS settled on.
 *
 * @param series the series as the source declares it, or `null` where none is declared.
 * @param number the issue or volume number within it, already written the way it is shown.
 * @param title the title the surface is drawing above this line.
 */
fun seriesLine(series: String?, number: String? = null, title: String): String? {
    val name = series?.takeIf { it.isNotBlank() } ?: return null
    val line = number?.takeIf { it.isNotBlank() }?.let { "$name #$it" } ?: name
    return line.takeIf { !it.equals(title, ignoreCase = true) }
}
