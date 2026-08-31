/*
 * What a cover-shaped cell draws when the publication has no artwork.
 *
 * Four shelves of the reader's own publications draw one of these, and until now exactly one
 * of them drew anything. `CoverGrid`'s cell — the library shelf — put the title in the middle
 * of the well and the format along the bottom. The Downloads shelf, Home's cards and a
 * publication page's series shelf all drew the sunken surface and then `cover?.let { Image }`,
 * with no else branch at all: an empty rectangle where the book's name should be.
 *
 * `android-downloads-tablet-default-light.png` in
 * `docs/designs/screenshots/after-2026-08-31b/` is what that looks like. Five of the
 * twenty-five cells fully on screen — `no-pages` and four of the six `rar4`/`rar5`
 * fixtures — are the bare
 * `surfaceSunken` cream, near-indistinguishable from the page behind them, while every cell
 * around them carries artwork. Home's and the series shelf's halves are the same omission in
 * the source; no committed capture happens to show either of them holding a coverless
 * publication, which is a good part of why they went unremarked for as long as the Downloads
 * one did.
 *
 * iOS's audit could not see any of this: its well is `accessibilityHidden` and the caption
 * below the cell carries the title, so VoiceOver reads the screen correctly either way. That
 * is why the iOS half, `fcc43505`, argues at length that this is the case §6 of `AGENTS.md`
 * asks for a screenshot to catch.
 *
 * The well lives in `:core:designsystem` rather than in `:feature:library` for the reason
 * `grid/CoverColumns.kt` moved here this afternoon: `CoverGrid`'s `CoverCell` is private to
 * that module, so `:app` could not call it however much it should, and a rule `:app` cannot
 * call is a rule `:app` reimplements — or, here, simply omits. This module is the one both
 * already depend on.
 *
 * **The one thing that genuinely differs between the four is whether the format is named** —
 * one nullable string, rather than four opinions about a text role and a padding. iOS reached
 * the same conclusion, in `CoverlessWell.swift`, and its parameter list is the same pair.
 *
 * Four further wells in this app are **not** this one and are left alone deliberately:
 *
 * - `DetailHero`'s `DetailCover` draws a book glyph above the format and no title, because a
 *   publication page reads its title out of the app bar and printing it again inside the
 *   artwork is a stutter. It differs in two ways rather than one, and it is a single hero
 *   rather than a cell in a grid.
 * - `CatalogueEntryCell`, `KavitaSeriesGrid` and `CatalogueDetailScreen`'s `Artwork` centre a
 *   title and stop. They are wells, and they hold three different text roles between them —
 *   but they stand for an `OpdsEntry` or a Kavita series rather than a `Publication`, neither
 *   of which has a format to name, and converting them changes what three remote-browsing
 *   screens look like. That belongs with its own capture, not with this fix.
 *
 * **Android's well has no font-scale rule and iOS's does.** iOS drops the title above
 * `DynamicTypeSize.isAccessibilitySize` — `coverlessWellDrawsTitle(at:)` carries that whole
 * argument — where Android has always relied on `maxLines = 4` and an ellipsis instead. That
 * divergence is older than this file and is preserved rather than settled here: adding the
 * rule would change how the library shelf looks at `font_scale 1.5` and up, which is a
 * behaviour change on the one surface that was not broken.
 */
package app.storyarc.core.designsystem.cover

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcSpace

/**
 * The title as stand-in artwork, and the format underneath when the surface names one.
 *
 * Fills whatever it is given and paints no background of its own: every caller already has a
 * cover-shaped box at `surfaceSunken` with the 4 dp printed-stock radius, and a second
 * surface inside it would round the corners twice. So this is the *contents* of a well and
 * not the well's frame.
 *
 * @param title what the publication is called. This is what the reader is actually looking
 *   for — a wall of coverless cells all say the same format, and the title is the only thing
 *   that tells them apart.
 * @param format the format's name, or `null` on a surface that does not name one. Home's
 *   cards and a series shelf pass `null`: no Home surface names a format anywhere, and a run
 *   of five volumes of one series repeating `CBZ` five times distinguishes nothing, while the
 *   page above it already names the format once.
 */
@Composable
fun CoverlessWell(title: String, format: String?, modifier: Modifier = Modifier) {
    val palette = LocalStoryArcPalette.current
    Box(modifier = modifier.fillMaxSize()) {
        Text(
            text = title,
            style = MaterialTheme.typography.titleSmall,
            color = palette.textSecondary,
            textAlign = TextAlign.Center,
            // Four lines and then an ellipsis. A well is as tall as a cover and a long title
            // set to wrap freely would push its own last line out of the box.
            maxLines = 4,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier
                .align(Alignment.Center)
                .padding(horizontal = StoryArcSpace.sm),
        )
        if (format != null) {
            Text(
                text = format,
                style = MaterialTheme.typography.labelSmall,
                color = palette.textTertiary,
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .padding(bottom = StoryArcSpace.xs),
            )
        }
    }
}
