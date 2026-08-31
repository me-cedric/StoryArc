/*
 * What a cover-shaped cell draws when the publication has no artwork.
 *
 * Four shelves of the reader's own publications draw one of these, and until now exactly one
 * of them drew anything. `CoverGrid`'s cell — the library shelf — put the title in the middle
 * of the well and the format along the bottom. The Downloads shelf, Home's cards and a
 * publication page's series shelf all drew the sunken surface and then a `?.let { Image(…) }`,
 * with no else branch at all: an empty rectangle where the book's name should be.
 *
 * `android-downloads-tablet-default-light.png` in
 * `docs/designs/screenshots/after-2026-08-31b/` is what that looks like. Five of the
 * twenty-five cells fully on screen are the bare `surfaceSunken` cream,
 * near-indistinguishable from the page behind them, while every cell around them carries
 * artwork. Which five cannot be told from the picture, because a blank well is exactly a cell
 * with nothing in it to read. Home's and the series shelf's halves are the same
 * omission in the source; no committed capture happens to show either of them holding a
 * coverless publication, which is a good part of why they went unremarked for as long as the
 * Downloads one did.
 *
 * iOS's audit could not see any of this: its downloads well is `accessibilityHidden` and the
 * caption below the cell carries the title, so VoiceOver reads that screen correctly whether
 * or not anything is drawn in the box. That is why the iOS half, `fcc43505`, argues at length
 * that this is the case §6 of `AGENTS.md` asks for a screenshot to catch.
 *
 * The well lives in `:core:designsystem` rather than in `:feature:library` for the reason
 * `grid/CoverColumns.kt` moved here earlier today: `CoverGrid`'s `CoverCell` is private to
 * that module, so `:app` could not call it however much it should, and a rule `:app` cannot
 * call is a rule `:app` reimplements — or, here, simply omits. This module is the one both
 * already depend on.
 *
 * **The one thing that genuinely differs between the four is whether the format is named** —
 * one nullable string, rather than four opinions about a text role and a padding. iOS reached
 * the same conclusion, in `CoverlessWell.swift`, whose two parameters are these two.
 *
 * Four further wells in this app are **not** this one and are left alone deliberately:
 *
 * - `DetailHero`'s `DetailCover` draws a book glyph above the format and no title, because a
 *   publication page reads its title out of the app bar and printing it again inside the
 *   artwork is a stutter. It differs in two ways rather than one, and it is a single hero
 *   rather than a cell in a grid.
 * - `CatalogueEntryCell`, `KavitaSeriesGrid` and `CatalogueDetailScreen`'s `Artwork` centre a
 *   title and stop. They are wells, and two of the three — `CatalogueEntryCell` and
 *   `KavitaSeriesGrid` — are the same well twice over: `bodySmall`, `textSecondary`, centred,
 *   `maxLines = 4`, ellipsised, `StoryArcSpace.sm` either side, differing only in whether the
 *   title comes off an entry or a series. `CatalogueDetailScreen`'s is `titleMedium`, so the
 *   three hold two text roles between them, not three. They stand for an `OpdsEntry` or a
 *   Kavita series rather than a `Publication`, neither of which has a format to name, and
 *   their boxes are the `StoryArcRadius.lg`/`md` of a remote-browsing card rather than the
 *   printed-stock `cover`. Converting them changes what three remote-browsing screens look
 *   like, which belongs with its own capture and not with this fix.
 *
 * **Android's well has no font-scale rule and iOS's does.** iOS drops the title above
 * `DynamicTypeSize.isAccessibilitySize` — `coverlessWellDrawsTitle(at:)` carries that whole
 * argument — where Android keeps the title and bounds it instead: the label's space is
 * reserved rather than drawn over, so the title has a box of its own to wrap and truncate
 * inside at any text size. That divergence is deliberate, and it is now measured at
 * `font_scale` 1.0, 1.5 and 2.0 by `CoverlessWellTest` rather than asserted here.
 */
package app.storyarc.core.designsystem.cover

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.clearAndSetSemantics
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
 * **Decorative, and silent to a screen reader.** A well stands in for artwork, and the
 * artwork it stands in for is drawn with `contentDescription = null` on every one of the four
 * surfaces — so a well that spoke would make the cell say more than the same cell with a
 * cover, which is the wrong way round. Every caller already states the title: Downloads and
 * Home in a caption under the box, the library shelf and the series shelf in an explicit
 * `contentDescription` on the cell. Without the clear, the Downloads cell announced
 * `Foreign Codec, CBZ, Foreign Codec` — the title twice and a format that surface's caption
 * never carried. `clearAndSetSemantics {}` rather than the caller's business, because it was
 * four callers' business before this file existed and three of them got it wrong by not
 * writing it at all.
 *
 * iOS arrives at the same place surface by surface, and with the same two answers: an
 * `.accessibilityHidden(true)` on Home's artwork box and on the downloads cell's box, and on
 * the grid's cell an explicit `.accessibilityLabel` over `.accessibilityElement(children:
 * .combine)` — which is what Android's library shelf and series shelf do with a
 * `contentDescription`. Its downloads comment gives this reason in as many words.
 *
 * The clear is invisible to a test using the unmerged semantics tree, which is where
 * `CoverlessWellTest` asserts what is drawn.
 *
 * @param title what the publication is called. This is what the reader is actually looking
 *   for — a wall of coverless cells all say the same format, and the title is the only thing
 *   that tells them apart.
 * @param format the format's name, or `null` on a surface that does not name one. The library
 *   shelf and the Downloads shelf name it; Home's cards and a publication page's series shelf
 *   do not, because nothing else on either of those surfaces names a format either — their
 *   captions are the title with, respectively, what is left to read and the volume's read
 *   state. A well stands in for artwork that is missing; it does not introduce a field its
 *   neighbours do not carry.
 */
@Composable
fun CoverlessWell(title: String, format: String?, modifier: Modifier = Modifier) {
    val palette = LocalStoryArcPalette.current
    Column(
        modifier = modifier.fillMaxSize().clearAndSetSemantics {},
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        // A column and not an overlay, so the label's space is reserved rather than drawn
        // over. The title used to be centred in the whole well with the format laid on top of
        // it, which is clear at the default text size and is not clear above it: the well is
        // as tall as a cover and the title's lines grow while the box does not, so from
        // `font_scale 1.5` up the fourth line was drawn underneath the label — measured at
        // 142 px against a label starting at 128. Reserving the label's height means the
        // title has a box of its own to be centred in and truncated to, at every text size,
        // and the collision cannot come back by arithmetic.
        //
        // It costs the title about half the label's height at the default size, where it is
        // now centred in the space above the label rather than in the whole well. That is a
        // visible change on the two surfaces that name a format — the library shelf and
        // Downloads — and it is the price of the bound.
        Box(
            modifier = Modifier.weight(1f).fillMaxWidth(),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                text = title,
                style = MaterialTheme.typography.titleSmall,
                color = palette.textSecondary,
                textAlign = TextAlign.Center,
                // Four lines and then an ellipsis. A well is as tall as a cover and a long
                // title set to wrap freely would push its own last line out of the box.
                //
                // The count does **not** need to fall when a label is drawn, which was this
                // fix's first guess: Compose lays a `Text` out inside the height it is given,
                // so the box above caps the line count on its own. Measured at 104 dp and
                // `titleSmall`: four lines end exactly at the label's top edge at
                // `font_scale 1.5`, and at 2.0 only three are laid out. A conditional here
                // would have been a constant dressed as a rule, killing no mutation the box
                // does not already kill.
                maxLines = 4,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.padding(horizontal = StoryArcSpace.sm),
            )
        }
        if (format != null) {
            Text(
                text = format,
                style = MaterialTheme.typography.labelSmall,
                color = palette.textTertiary,
                modifier = Modifier.padding(bottom = StoryArcSpace.xs),
            )
        }
    }
}
