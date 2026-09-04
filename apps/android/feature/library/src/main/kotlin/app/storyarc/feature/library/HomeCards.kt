package app.storyarc.feature.library

import android.graphics.Bitmap
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ExperimentalMaterial3ExpressiveApi
import androidx.compose.material3.LinearWavyProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.storyarc.core.designsystem.cover.CoverlessWell
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcRadius
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.Publication
import app.storyarc.core.model.ReadState

/** The proportions of a comic cover, near enough for every publisher. */
internal const val HOME_COVER_ASPECT = 3f / 2f

/**
 * How tall the text under a cover is.
 *
 * Measured in `sp` and converted, so it grows with the reader's text size instead of
 * clipping at it — the carousel and the shelf rows both need a height before they can lay
 * out, and a height fixed in `dp` is the reason a card's title disappears at 200%.
 */
@Composable
internal fun homeCaptionHeight(lines: Int): Dp =
    with(LocalDensity.current) { (lines * 22).sp.toDp() } + StoryArcSpace.md

/**
 * One cover, letterboxed rather than cropped, decoded when the card appears.
 *
 * `design.md` is explicit that artwork is never cropped to fill a cell: a manga volume and
 * a square ebook cover are not 2:3, and cropping the art to make them so cuts the title off
 * the top of the artwork. The letterbox goes onto `surfaceSunken` so the cell still reads
 * as a cell, at the 4 dp cover radius the tokens reserve for printed stock.
 *
 * Decoded lazily through the model, which caches it — `publication-formats` asks for covers
 * to be pulled "as rows approach the viewport" rather than during the scan, and the cache
 * is what makes the same cover on Home and on the library shelf one bitmap and not two.
 */
@Composable
internal fun HomeCoverArt(
    publication: Publication,
    cover: suspend (Publication, Int) -> Bitmap?,
    width: Dp,
    modifier: Modifier = Modifier,
) {
    val palette = LocalStoryArcPalette.current
    val pixels = with(LocalDensity.current) { width.roundToPx() }
    var bitmap by remember(publication.id) { mutableStateOf<Bitmap?>(null) }
    LaunchedEffect(publication.id, pixels) { bitmap = cover(publication, pixels) }

    Box(
        modifier = modifier
            .clip(RoundedCornerShape(StoryArcRadius.cover))
            .background(palette.surfaceSunken),
        contentAlignment = Alignment.Center,
    ) {
        val art = bitmap
        if (art != null) {
            Image(
                bitmap = art.asImageBitmap(),
                contentDescription = null,
                contentScale = ContentScale.Fit,
                modifier = Modifier.fillMaxSize(),
            )
        } else {
            // This branch used to be absent, so a publication with no artwork was a bare
            // `surfaceSunken` rectangle on the one surface whose whole job is to hand the
            // reader back a book they already know. The title is what identifies it; no
            // format, because nothing on Home names one — its captions are the title and
            // either what is left to read or why the book is away.
            CoverlessWell(title = publication.displayTitle, format = null)
        }
    }
}

/**
 * The Keep reading card — the one hero moment on the surface.
 *
 * M3 Expressive's own guidance is to combine tactics for a hero but to "stick to one or
 * two"; this uses tactic #1, breaking from the surrounding shape style, and tactic #2,
 * containment. Every other shelf on Home is a bare cover at the 4 dp cover radius with no
 * container at all. This one is a raised container at 22 dp with the cover inside it, so
 * the emphasis is carried entirely by shape and elevation — **no tint reaches the
 * artwork**, which is the whole reason to emphasise this way on a screen whose content is
 * other people's art. It is also the divergence the register records at #10: iOS emphasises
 * with a prominent glass button and scale contrast, Android with shape and containment.
 *
 * The progress line is `LinearWavyProgressIndicator`, Expressive's own determinate
 * indicator, and it carries no text of its own — how much is left is said in pages beside
 * it, because `home-screen` refuses a percentage as the only answer.
 *
 * **The byline was added 2026-09-05**, against *The card shows how far through, not only
 * how much is left*: "the publication's author is named where the card has room for it,
 * because a title alone is not enough to recognise a book by". A folder library is full of
 * `Vol 3` and `Chapter 12`, and a shelf of those is a shelf of strangers. The first author
 * only, which is what `CoverGrid` and `CoverList` already show, so a book reads the same
 * way wherever the reader meets it.
 */
@OptIn(ExperimentalMaterial3ExpressiveApi::class)
@Composable
internal fun HomeKeepReadingCard(
    entry: HomeEntry,
    cover: suspend (Publication, Int) -> Bitmap?,
    width: Dp,
    modifier: Modifier = Modifier,
) {
    val palette = LocalStoryArcPalette.current
    // The dim is animated on Material's own effects spec rather than a fixed duration:
    // divergence #11, and the scheme's speed tokens are device-aware in a way a constant
    // is not. A source coming back should not make a cover flick to full brightness.
    val dim by animateFloatAsState(
        targetValue = if (entry.isReadableNow) 1f else AWAY_ALPHA,
        animationSpec = MaterialTheme.motionScheme.defaultEffectsSpec(),
        label = "home-card-dim",
    )

    // The art sits inside the container's padding, so its height follows the width it
    // actually gets. Taking it from the card's outer width instead leaves a letterbox above
    // and below every cover — the cell claiming to be 2:3 while the artwork inside it is not.
    val art = width - StoryArcSpace.md * 2

    Column(
        modifier = modifier
            .width(width)
            .clip(RoundedCornerShape(StoryArcRadius.xl))
            .background(palette.surfaceRaised)
            .padding(StoryArcSpace.md),
        verticalArrangement = Arrangement.spacedBy(StoryArcSpace.md),
    ) {
        HomeCoverArt(
            publication = entry.publication,
            cover = cover,
            width = art,
            modifier = Modifier
                .fillMaxWidth()
                .height(art * HOME_COVER_ASPECT)
                .alpha(dim),
        )

        Text(
            text = entry.publication.displayTitle,
            style = MaterialTheme.typography.titleMedium,
            color = palette.textPrimary,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
        )

        homeBylineText(entry.publication)?.let { author ->
            Text(
                text = author,
                style = MaterialTheme.typography.bodyMedium,
                color = palette.textSecondary,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }

        LinearWavyProgressIndicator(
            progress = { entry.fraction.toFloat() },
            modifier = Modifier.fillMaxWidth(),
        )

        // What is left, or — when the book is not reachable — why it will not open. The dim
        // says *something* is wrong; `home-screen` asks for it to be said "plainly", and a
        // grey cover on its own is not a sentence.
        Text(
            text = if (entry.isReadableNow) {
                homeRemainingText(entry)
            } else {
                stringResource(R.string.home_away)
            },
            style = MaterialTheme.typography.bodyMedium,
            color = palette.textSecondary,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

/**
 * One cover on a plain shelf: the artwork, the title, and nothing else.
 *
 * Deliberately uncontained. The hero has the only container on the surface, and a shelf
 * cell that grew one would be a second thing asking to be looked at — which is the
 * "overwhelming or distracting" the Expressive guidance warns about, and the failure mode
 * that turns a reading room back into a file manager.
 */
@Composable
internal fun HomeShelfCell(
    entry: HomeEntry,
    cover: suspend (Publication, Int) -> Bitmap?,
    width: Dp,
    modifier: Modifier = Modifier,
) {
    val palette = LocalStoryArcPalette.current
    val dim by animateFloatAsState(
        targetValue = if (entry.isReadableNow) 1f else AWAY_ALPHA,
        animationSpec = MaterialTheme.motionScheme.defaultEffectsSpec(),
        label = "home-cell-dim",
    )

    Column(
        modifier = modifier.width(width),
        verticalArrangement = Arrangement.spacedBy(StoryArcSpace.sm),
    ) {
        HomeCoverArt(
            publication = entry.publication,
            cover = cover,
            width = width,
            modifier = Modifier
                .fillMaxWidth()
                .height(width * HOME_COVER_ASPECT)
                .alpha(dim),
        )
        Text(
            text = entry.publication.displayTitle,
            style = MaterialTheme.typography.bodyMedium,
            color = palette.textPrimary,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
        )
        if (!entry.isReadableNow) {
            Text(
                text = stringResource(R.string.home_away),
                style = MaterialTheme.typography.bodySmall,
                color = palette.textTertiary,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}

/**
 * Who wrote it, where the card has room to say so.
 *
 * `home-screen`: the author is named "because a title alone is not enough to recognise a
 * book by" — a folder library is full of `Vol 3` and `Chapter 12`, and a shelf of those is
 * a shelf of strangers.
 *
 * The first author rather than all of them, which is what `CoverGrid` and `CoverList`
 * already show, so a book reads the same way wherever the reader meets it. `null` rather
 * than a blank where there is no name: a row held open for the publications that have no
 * author is a gap the reader reads as a bug.
 *
 * Not `@Composable`, for the reason `homeHeroWidth` is not: it is a rule, and a rule inside
 * a composable is a rule no plain JVM suite can reach. `HomeCardBylineTest` is that reach.
 */
internal fun homeBylineText(publication: Publication): String? =
    publication.authors.firstOrNull()?.takeIf { it.isNotBlank() }

/**
 * What one card announces to a screen reader.
 *
 * The card is one target, so it reads as one thing: the title, then how much is left, then
 * — only when it applies — that it cannot be opened. Assembled here rather than left to the
 * default traversal, which would read a cover with no description, a title, a bare progress
 * percentage and a sentence as four separate stops.
 */
@Composable
internal fun Modifier.homeCardSemantics(entry: HomeEntry, label: String): Modifier {
    val away = stringResource(R.string.home_away)
    // Assembled from the parts that have something to say. A blank `label` is dropped rather
    // than joined, so a card with nothing to report about reading announces its title instead
    // of the title followed by a full stop and a silence. Home never passes one — its shelves
    // always have an answer — but the search page's *never opened* section does, and the
    // alternative there was every unread book announcing itself as part-read.
    val description = listOf(entry.publication.displayTitle, label, if (entry.isReadableNow) "" else away)
        .filter { it.isNotBlank() }
        .joinToString(". ")
    return clearAndSetSemantics { contentDescription = description }
}

/**
 * How much is left, in the reader's own terms.
 *
 * Pages when the publication says how many it has; otherwise the plain sentence that it is
 * part-read. Never a bare percentage — `home-screen` names that as the thing not to do, and
 * the wavy line above already carries the shape of the answer.
 *
 * **The state decides first, and it did not use to.** "Part-read" was the fallback for
 * *this publication does not say how many pages it has*, and a book nobody has ever opened
 * does not say either — so every cover on a plain shelf announced itself as part-read to a
 * screen reader, on a device where nothing had been read at all. A finished one did too,
 * because [HomeShelves.pagesRemaining] is deliberately null once the finished flag is set.
 * Three sentences for three states, and an untouched book says nothing rather than
 * something untrue: [Modifier.homeCardSemantics] drops a blank instead of joining it.
 */
@Composable
internal fun homeRemainingText(entry: HomeEntry): String = when (entry.state) {
    ReadState.UNREAD -> ""
    ReadState.FINISHED -> stringResource(R.string.home_finished_one)
    ReadState.IN_PROGRESS -> entry.pagesRemaining
        ?.let { pages -> pluralStringResource(R.plurals.home_pages_left, pages, pages) }
        ?: stringResource(R.string.home_part_read)
}
