package app.storyarc.feature.epubreader

import android.content.Intent
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
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcSpace

/** Carried on `EpubReaderActivity`'s intent: task 7.2's end-of-book offer, or null for none. */
internal const val EXTRA_NEXT_ID = "next_id"
internal const val EXTRA_NEXT_TITLE = "next_title"

/** Carried on the activity result when the offer is taken, read back by the app layer. */
const val EXTRA_RESULT_NEXT_ID = "result_next_id"

/** How close to the end counts as the end, mirroring the floor `record()` uses. */
private const val EPUB_FINISHED_PROGRESSION = 0.999

/**
 * Reads the offer out of [intent] and draws it once the book is at [EPUB_FINISHED_PROGRESSION],
 * the way the paged reader's own end screen draws over its last page.
 *
 * Takes the intent and the raw state rather than the activity itself, so this stays a
 * composable function nothing but the chrome calls — see [EpubEndOfPublication] below for
 * why it is a function of its own and not a reuse of `ReaderScreen`'s.
 */
@Composable
internal fun EpubEndOfBookOffer(
    intent: Intent,
    failure: Int?,
    progression: Double,
    onOpenNext: (String) -> Unit,
) {
    val nextId = intent.getStringExtra(EXTRA_NEXT_ID) ?: return
    if (failure != null || progression < EPUB_FINISHED_PROGRESSION) return
    EpubEndOfPublication(
        nextTitle = intent.getStringExtra(EXTRA_NEXT_TITLE),
        onOpenNext = { onOpenNext(nextId) },
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
 */
@Composable
internal fun EpubEndOfPublication(
    nextTitle: String?,
    onOpenNext: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val palette = LocalStoryArcPalette.current
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
                    colors = ButtonDefaults.buttonColors(containerColor = palette.accent, contentColor = Color.White),
                ) {
                    Text(stringResource(R.string.epub_end_next, nextTitle))
                }
            }
        }
    }
}
