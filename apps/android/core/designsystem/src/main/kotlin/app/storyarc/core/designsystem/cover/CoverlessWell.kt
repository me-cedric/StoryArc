/*
 * What a cover-shaped cell draws when the publication has no artwork.
 *
 * Task 16.8, `audio-playback`'s *A publication with no cover*: the player's well drew the
 * **title**, repeating the name the screen around it already stated — the library shelf, the
 * Downloads shelf, Home's cards and the series shelf repeated it too, since they all drew this
 * same well. iOS settled the same complaint in `CoverlessWell.swift` by drawing the format's
 * own symbol and its name instead of the title: "the title in the well was never the thing
 * that distinguished one card from another … what the well can say that nothing beside it
 * says is what kind of thing this is." This file now draws the same two things — a glyph and
 * a name — so both platforms draw one treatment rather than two.
 *
 * The well still has two shapes, exactly as iOS's does:
 *
 * - A publication's own well names the **format** — [CoverlessWell] with a
 *   [app.storyarc.core.model.PublicationFormat]. Every per-publication caller uses this one:
 *   the library shelf, Downloads, the series shelf, Home's cards and the player.
 * - A **shelf's** own well, with no single format to draw, names the shelf instead — the
 *   overload that takes a `name`. It still draws a glyph: the first member's known format
 *   when one resolved, or a generic glyph when none did. `ShelfCover.kt` is the one caller.
 *
 * The well lives in `:core:designsystem` rather than in `:feature:library` for the reason
 * `grid/CoverColumns.kt` moved here earlier: `CoverGrid`'s `CoverCell` is private to that
 * module, so `:app` could not call it however much it should, and a rule `:app` cannot call is
 * a rule `:app` reimplements — or, here, simply omits. This module is the one every caller
 * already depends on.
 *
 * Four further wells in this app are **not** this one and are left alone deliberately:
 *
 * - `DetailHero`'s `DetailCover` draws a fixed book glyph above the format and no title,
 *   because a publication page reads its title out of the app bar and printing it again
 *   inside the artwork is a stutter. It differs in two ways rather than one, and it is a
 *   single hero rather than a cell in a grid.
 * - `CatalogueEntryCell`, `KavitaSeriesGrid` and `CatalogueDetailScreen`'s `Artwork` centre a
 *   title and stop. They stand for an `OpdsEntry` or a Kavita series rather than a
 *   `Publication`, neither of which has a format to name, and their boxes are the
 *   `StoryArcRadius.lg`/`md` of a remote-browsing card rather than the printed-stock `cover`.
 *   Converting them changes what three remote-browsing screens look like, which belongs with
 *   its own capture and not with this fix.
 *
 * **Android's well has no font-scale rule and iOS's does, and that stays true.** iOS drops the
 * title above `DynamicTypeSize.isAccessibilitySize`; Android never drew a title large enough
 * to need dropping even before this change, because the label was always the format's own
 * short name. The glyph is measured off the well's shorter side instead, which is the rule
 * `CoverlessWellTest` now asserts.
 */
package app.storyarc.core.designsystem.cover

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.LibraryBooks
import androidx.compose.material.icons.automirrored.outlined.MenuBook
import androidx.compose.material.icons.outlined.AutoStories
import androidx.compose.material.icons.outlined.Description
import androidx.compose.material.icons.outlined.Headphones
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.text.style.TextAlign
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.PublicationFormat

/**
 * A publication's own well: the format's glyph, and the format's own name underneath.
 *
 * `title` is deliberately absent. Every caller already states the publication's title
 * somewhere else on the same screen — a caption below the cell, the app bar, the player's
 * `title2` and the lock screen's own title field — so the well repeating it was never new
 * information, only the same word twice over. What the well adds is what kind of thing this
 * is, which is [coverlessWellIcon] and the format's own name.
 *
 * Fills whatever it is given and paints no background of its own: every caller already has a
 * cover-shaped box at `surfaceSunken` with the printed-stock radius, and a second surface
 * inside it would round the corners twice. So this is the *contents* of a well and not the
 * well's frame.
 *
 * **Decorative, and silent to a screen reader**, for the same reason the title-based well
 * was: every caller already states the title in a caption or a `contentDescription`, and a
 * well that spoke the format too would be a second thing said about a cell that already says
 * one.
 *
 * @param format the publication's format.
 */
@Composable
fun CoverlessWell(format: PublicationFormat, modifier: Modifier = Modifier) {
    CoverlessWellContent(icon = coverlessWellIcon(format), label = format.displayName, modifier = modifier)
}

/**
 * A shelf's own well: no single publication to name a format from, so it is named for the
 * shelf instead.
 *
 * `collections-and-reading-lists` asks a shelf with no artwork to show "the same placeholder a
 * publication with no cover shows", carrying the shelf's own name — which is `name` here,
 * never a format's. The glyph still answers "what kind of thing is this": the first member's
 * known format when the caller resolved one, or a generic glyph when it did not, exactly as
 * iOS's own `CoverlessWell(name:format:)` does.
 *
 * @param name the shelf's own name, drawn where a publication's well draws the format.
 * @param format the first member's format the caller resolved, or `null` when none did —
 *   a shelf with nothing in it, or whose members' formats are not yet known.
 */
@Composable
fun CoverlessWell(name: String, format: PublicationFormat?, modifier: Modifier = Modifier) {
    CoverlessWellContent(icon = coverlessShelfIcon(format), label = name, modifier = modifier)
}

/**
 * How much of the well's shorter side the glyph takes.
 *
 * Mirrors iOS's own `CoverlessWell.glyphShare`: large enough to read as the subject of the
 * well, small enough to leave the format's name clear beneath it at the largest text size.
 */
private const val GLYPH_SHARE = 0.3f

@Composable
private fun CoverlessWellContent(icon: ImageVector, label: String, modifier: Modifier = Modifier) {
    val palette = LocalStoryArcPalette.current
    BoxWithConstraints(modifier = modifier.fillMaxSize().clearAndSetSemantics {}) {
        val glyphSide = minOf(maxWidth, maxHeight) * GLYPH_SHARE
        Column(
            modifier = Modifier.fillMaxSize(),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = palette.textTertiary,
                modifier = Modifier.size(glyphSide),
            )
            Text(
                text = label,
                style = MaterialTheme.typography.labelSmall,
                color = palette.textTertiary,
                textAlign = TextAlign.Center,
                maxLines = 1,
                modifier = Modifier.padding(top = StoryArcSpace.xs),
            )
        }
    }
}

/**
 * The glyph that stands in for a publication of this format.
 *
 * Four glyphs for nine formats, and the grouping is the point — mirrors iOS's
 * `coverlessWellSymbol(for:)` exactly, so an audiobook is never drawn as a book on either
 * platform. Naming CBZ and CBT with different pictures would be drawing the container rather
 * than the publication; the format's own *name*, underneath, already carries that.
 *
 * @param format the publication's format.
 */
fun coverlessWellIcon(format: PublicationFormat): ImageVector = when (format) {
    PublicationFormat.CBZ, PublicationFormat.CBR, PublicationFormat.CB7,
    PublicationFormat.CBT, PublicationFormat.IMAGE_FOLDER -> Icons.Outlined.AutoStories
    PublicationFormat.EPUB -> Icons.AutoMirrored.Outlined.MenuBook
    PublicationFormat.PDF -> Icons.Outlined.Description
    PublicationFormat.M4B, PublicationFormat.MP3, PublicationFormat.FLAC,
    PublicationFormat.OGG, PublicationFormat.AUDIO_FOLDER -> Icons.Outlined.Headphones
}

/**
 * The glyph a shelf's own well draws: the known format's, or a generic one when a shelf
 * resolved none.
 *
 * A distinct name from [coverlessWellIcon] rather than an overload on nullability: the two
 * erase to the same JVM signature, since a nullable reference carries no type of its own on
 * the platform — `PublicationFormat` and `PublicationFormat?` are one descriptor once
 * compiled, and Kotlin's own overload rules do not catch that for a top-level function.
 *
 * @param format the first member's format a shelf resolved, or `null`.
 */
fun coverlessShelfIcon(format: PublicationFormat?): ImageVector =
    format?.let(::coverlessWellIcon) ?: Icons.AutoMirrored.Filled.LibraryBooks
