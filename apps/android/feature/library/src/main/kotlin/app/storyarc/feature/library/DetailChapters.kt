package app.storyarc.feature.library

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import app.storyarc.core.designsystem.format.clock
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcSpace

/**
 * One part of an audiobook, as the page is handed it.
 *
 * The two facts a chapter list needs and no more. `:core:playback` already decides what the
 * parts of a publication are — `AudiobookChapters.parts` gives an unchaptered book one part
 * standing for the whole file, and names an untitled mark — so the caller calls that and
 * passes the answer down. This module holds no player and takes no dependency on one.
 *
 * @param statedMillis the length the page may print, or null when nothing knows it. The
 *   caller passes `PlaybackDuration.statedMillis`, so an estimate never reaches a clock.
 */
data class AudiobookPart(val title: String, val statedMillis: Long?)

/** How far a listener has got through one chapter, as the page marks it. */
internal enum class ChapterProgress {

    /** The listener has passed it. */
    FINISHED,

    /** The listener stopped inside it. */
    IN_PROGRESS,

    /** Not reached yet, or the book was never started. */
    UNPLAYED,
}

/** One chapter as the page draws it: a title, a duration where one is stated, and a mark. */
internal data class DetailChapter(
    val title: String,
    val statedMillis: Long?,
    val progress: ChapterProgress,
)

/**
 * The rows the page lists, or none where a list would say nothing.
 *
 * `audio-playback`, *An audiobook with one part*: a book with no chapter markers "offers no
 * list, because a list of one row tells a listener nothing". `AudiobookChapters.parts` never
 * returns an empty list — an unchaptered book gets one part standing for the whole file — so
 * one part is exactly the case that gets no list, and the page states the duration instead.
 * See [wholeBookMillis].
 *
 * @param stoppedIn the part the listener stopped in, or null for a book they never started.
 *   The caller passes null for the same fact the primary action calls *no progress*, so the
 *   button and the marks cannot disagree about whether the book was started.
 */
internal fun chapterRows(
    parts: List<AudiobookPart>,
    stoppedIn: Int?,
): List<DetailChapter> {
    if (parts.size < 2) return emptyList()
    return parts.mapIndexed { index, part ->
        DetailChapter(
            title = part.title,
            statedMillis = part.statedMillis,
            progress = progressOf(index, stoppedIn),
        )
    }
}

/**
 * One saved position marks every row, because a listener is in one place at a time.
 *
 * Everything before the part they stopped in is behind them and is marked finished; the part
 * they stopped in is the one in progress. Nothing after it is marked at all — a chapter
 * nobody has reached is the ordinary state of a chapter and carries no word.
 */
private fun progressOf(index: Int, stoppedIn: Int?): ChapterProgress = when {
    stoppedIn == null -> ChapterProgress.UNPLAYED
    index < stoppedIn -> ChapterProgress.FINISHED
    index == stoppedIn -> ChapterProgress.IN_PROGRESS
    else -> ChapterProgress.UNPLAYED
}

/**
 * The whole book's duration, for the book that gets no list, or null where there is none.
 *
 * Null for a chaptered book, whose length is the list. Null for a single part whose container
 * never said how long it is, because the page states a duration or says nothing — and
 * `publication-formats` refuses to report that absence as a fault.
 */
internal fun wholeBookMillis(parts: List<AudiobookPart>): Long? =
    parts.singleOrNull()?.statedMillis

/**
 * The chapter a resume would land inside, or null where naming one would tell a listener
 * nothing.
 *
 * `audio-playback`: the primary action "names the chapter it will resume inside", and "an
 * audiobook never started offers to start it, naming no chapter". Null for a single-part
 * book too: its one part is titled with the book's own title, so naming it would print the
 * title the reader is already looking at.
 */
internal fun resumeChapterTitle(parts: List<AudiobookPart>, stoppedIn: Int?): String? {
    if (parts.size < 2 || stoppedIn == null) return null
    return parts.getOrNull(stoppedIn)?.title
}

/**
 * An audiobook's chapters, before the first minute of it has been heard.
 *
 * `audio-playback` puts this on the publication's own page and says why: the player lists
 * chapters and the player is reached by starting the book, so a listener choosing what to
 * hear next could see a chapter list only by first playing something they had not chosen.
 *
 * Drawing the list moves nothing. The saved position arrives as a parameter and leaves
 * unchanged; the only thing a row can do is call [onChoose], which is a different verb from
 * the resume the primary action carries.
 */
@Composable
internal fun DetailChapters(
    parts: List<AudiobookPart>,
    stoppedIn: Int?,
    /** Start at this part rather than where the book was left. */
    onChoose: (Int) -> Unit,
    modifier: Modifier = Modifier,
) {
    val palette = LocalStoryArcPalette.current
    val rows = chapterRows(parts, stoppedIn)

    if (rows.isEmpty()) {
        val whole = wholeBookMillis(parts) ?: return
        Text(
            text = stringResource(R.string.detail_duration, clock(whole)),
            style = MaterialTheme.typography.bodyMedium,
            color = palette.textSecondary,
            modifier = modifier,
        )
        return
    }

    Column(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(StoryArcSpace.xs),
    ) {
        Text(
            text = stringResource(R.string.detail_chapters),
            style = MaterialTheme.typography.titleSmall,
            color = palette.textSecondary,
        )
        rows.forEachIndexed { index, row -> ChapterRow(row, onChoose = { onChoose(index) }) }
    }
}

/**
 * One chapter, announced as one row.
 *
 * `audio-playback` asks for the duration as the row's **value**, so it is the row's state
 * description and the printed copy of it is taken out of the semantics — otherwise a screen
 * reader states the same number twice in one breath. `Modifier.clickable` merges the rest,
 * so the row announces its title and its mark and then its duration.
 */
@Composable
private fun ChapterRow(row: DetailChapter, onChoose: () -> Unit) {
    val stated = row.statedMillis?.let(::clock)
    ListItem(
        modifier = Modifier
            .clickable(onClick = onChoose)
            .semantics { stated?.let { stateDescription = it } },
        supportingContent = stated?.let { spoken -> { DurationLine(spoken) } },
        trailingContent = row.progress.mark()?.let { mark -> { Text(stringResource(mark)) } },
        content = { Text(row.title) },
    )
}

/** The printed duration, silent because the row already carries it as its value. */
@Composable
private fun DurationLine(stated: String) {
    Text(text = stated, modifier = Modifier.clearAndSetSemantics {})
}

/**
 * The word beside a chapter, or none.
 *
 * The library's own read-state words rather than a second pair: a chapter a listener has
 * passed is finished in the same sense a book is, and one situation described twice in a
 * four-language app is how the two come apart.
 */
private fun ChapterProgress.mark(): Int? = when (this) {
    ChapterProgress.FINISHED -> R.string.library_read_state_finished
    ChapterProgress.IN_PROGRESS -> R.string.library_read_state_in_progress
    ChapterProgress.UNPLAYED -> null
}
