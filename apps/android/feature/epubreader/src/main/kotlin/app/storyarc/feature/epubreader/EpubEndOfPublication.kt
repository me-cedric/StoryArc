package app.storyarc.feature.epubreader

import android.app.Activity
import android.content.Intent
import android.graphics.Color as AndroidColor
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.CoverAccent
import app.storyarc.core.model.CoverColours
import app.storyarc.core.model.Publication
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.readium.r2.shared.publication.Publication as ReadiumPublication
import org.readium.r2.shared.publication.services.cover

/** Carried on `EpubReaderActivity`'s intent: task 7.2's end-of-book offer, or null for none. */
internal const val EXTRA_NEXT_ID = "next_id"
internal const val EXTRA_NEXT_TITLE = "next_title"

/**
 * Tells `EpubReaderActivity` what to offer at the end of the book. Null offers nothing.
 *
 * Here rather than as two more parameters of `EpubReaderActivity.intent`, because that file
 * is over the line cap and `scripts/line-cap.mjs` lets it shrink but not grow.
 */
fun Intent.offeringNext(next: Publication?): Intent =
    putExtra(EXTRA_NEXT_ID, next?.id).putExtra(EXTRA_NEXT_TITLE, next?.displayTitle)

/** Carried on the activity result when the offer is taken, read back by the app layer. */
const val EXTRA_RESULT_NEXT_ID = "result_next_id"

/** How close to the end counts as the end, mirroring the floor `record()` uses. */
private const val EPUB_FINISHED_PROGRESSION = 0.999

/**
 * Whether the book is at its end: Readium's last page is on screen, or the locator is at
 * [EPUB_FINISHED_PROGRESSION]. The locator alone missed a short last page, so no end card
 * drew at the end of a book (task 23.4).
 */
internal fun endOfBookReached(atLastPage: Boolean, progression: Double): Boolean =
    atLastPage || progression >= EPUB_FINISHED_PROGRESSION

/**
 * Reads the offer out of [activity]'s intent and draws it once the book is at
 * [EPUB_FINISHED_PROGRESSION], the way the paged reader's own end screen draws over its last
 * page. See [EpubEndOfPublication] below for why it is a function of its own and not a reuse
 * of `ReaderScreen`'s.
 */
@Composable
internal fun EpubEndOfBookOffer(activity: EpubReaderActivity, failure: Int?, progression: Double) {
    val nextId = activity.intent.getStringExtra(EXTRA_NEXT_ID) ?: return
    val colours by activity.model.coverColours.collectAsStateWithLifecycle()
    val atLastPage by activity.model.atLastPage.collectAsStateWithLifecycle()
    if (failure != null || !endOfBookReached(atLastPage, progression)) return
    EpubEndOfPublication(
        nextTitle = activity.intent.getStringExtra(EXTRA_NEXT_TITLE),
        colours = colours,
        onOpenNext = {
            // Handed back as the activity's result: the app layer opens it, since this
            // activity has no library of its own to ask.
            activity.setResult(Activity.RESULT_OK, Intent().putExtra(EXTRA_RESULT_NEXT_ID, nextId))
            activity.finish()
        },
    )
}

/**
 * Offered over the last page of a reflowable book, the way the comic reader's own end
 * screen is offered over its last page.
 *
 * `collections-and-reading-lists` task 7.2: "at the end of a reflowable EPUB... offer
 * `library.next(after:)` the way the paged reader's end screen does". A separate composable
 * rather than a reuse of `ReaderScreen`'s private `EndOfPublication`: that one lives in
 * `:feature:reader`, which this module does not depend on, and the EPUB reader's chrome is
 * its own module for exactly that reason (ADR-0001).
 *
 * D21: this surface takes the cover's accent, as the comic reader's end screen does. The
 * chrome over the page stays untinted, which is the scrim rule.
 *
 * @param colours the cover's colours, or null for a cover with none, which keeps the brand
 *   accent with white text.
 */
@Composable
internal fun EpubEndOfPublication(
    nextTitle: String?,
    onOpenNext: () -> Unit,
    modifier: Modifier = Modifier,
    colours: CoverColours? = null,
) {
    val palette = LocalStoryArcPalette.current
    val button = endButtonColours(colours, brand = palette.accent)
    Box(modifier = modifier.fillMaxSize().safeDrawingPadding(), contentAlignment = Alignment.BottomCenter) {
        Column(
            modifier = Modifier
                .padding(StoryArcSpace.gutter)
                .background(Color.Black.copy(alpha = 0.78f), RoundedCornerShape(StoryArcSpace.md))
                .padding(StoryArcSpace.gutter),
            verticalArrangement = Arrangement.spacedBy(StoryArcSpace.md),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(
                text = stringResource(R.string.epub_end_finished),
                style = MaterialTheme.typography.titleMedium,
                color = Color.White,
            )
            if (nextTitle != null) {
                Button(
                    onClick = onOpenNext,
                    colors = ButtonDefaults.buttonColors(containerColor = button.fill, contentColor = button.label),
                ) {
                    Text(stringResource(R.string.epub_end_next, nextTitle))
                }
            }
        }
    }
}

/** The next-book button's fill and the label on it. */
internal data class EndButtonColours(val fill: Color, val label: Color)

/**
 * The cover's adjusted accent and the colour chosen for it, or the brand accent with white.
 * Never the raw extracted colour: [CoverAccent] has already moved it clear of the floor.
 */
internal fun endButtonColours(colours: CoverColours?, brand: Color): EndButtonColours {
    val fill = colours?.accent?.let(::hexColour) ?: return EndButtonColours(brand, Color.White)
    return EndButtonColours(fill, colours.onAccent.let(::hexColour) ?: Color.White)
}

private fun hexColour(hex: String): Color? =
    runCatching { Color(AndroidColor.parseColor(hex)) }.getOrNull()

/**
 * The colours one EPUB's cover gives its end of book, or null for a book with no cover or a
 * cover with no colour. [CoverAccent], which the comic reader uses too, so both readers derive
 * one cover the same way. Off the main thread: the cover is decoded here.
 */
internal suspend fun epubCoverColours(publication: ReadiumPublication): CoverColours? =
    withContext(Dispatchers.Default) {
        publication.cover()?.let { CoverAccent.derived(CoverAccent.pixels(it)) }
    }
