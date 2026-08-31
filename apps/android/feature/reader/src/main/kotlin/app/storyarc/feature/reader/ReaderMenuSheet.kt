package app.storyarc.feature.reader

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.automirrored.filled.ManageSearch
import androidx.compose.material.icons.filled.Bookmark
import androidx.compose.material.icons.filled.SkipNext
import androidx.compose.material.icons.filled.SkipPrevious
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.PageFit
import app.storyarc.core.model.PageTransition
import app.storyarc.core.model.Publication
import app.storyarc.core.model.ReaderMenuEntry
import app.storyarc.core.model.ReadingDirection
import app.storyarc.core.model.TransitionChoices
import kotlin.math.roundToInt

/*
 * The one door out of the two-control chrome, and everything behind it.
 *
 * `comic-reader`, *Everything else is in the menu, and labelled*: "it offers the table of
 * contents, bookmarks, search within the publication, reading themes and reader settings,
 * each named in words rather than by icon alone … every control that was reachable from the
 * reader before this change is reachable from here in one action."
 *
 * **One action is the load-bearing half.** Eleven icons became five doors, and a door that
 * led to another door would have traded recognition for depth. So the settings rows are *in*
 * the menu with their current value beside them rather than behind a Settings row, and the
 * PDF text sheet opens on the panel the row names. What opens a surface of its own is what
 * already was one: the image adjustments and the text sheet.
 *
 * `ReaderMenuTest` asserts both halves: that each of `ReaderMenuEntry`'s rows is here with
 * its own name, and that every control the chrome used to draw is still reachable.
 *
 * Rows a publication cannot honour are absent rather than disabled — the rule this reader
 * already applied to the buttons these rows replace.
 */

/** What the menu says. Grouped so the sheet takes two parameters rather than seventeen. */
internal data class ReaderMenuFacts(
    val pageIndex: Int,
    val pageCount: Int,
    val skippedPageCount: Int,
    val choices: TransitionChoices,
    val showsSeparator: Boolean,
    val fit: PageFit,
    val direction: ReadingDirection,
    val hasPairs: Boolean,
    val isOffset: Boolean,
    val isOrientationLocked: Boolean,
    /** Whether this PDF carries text. A scan offers no search row rather than an empty one. */
    val hasPdfText: Boolean,
    /**
     * Whether the browser of every page is drawn under the contents row.
     *
     * False on a window wide enough for the supporting pane, where `comic-reader`'s browser
     * sits *beside* the artwork instead — drawing both would be the browser twice.
     */
    val showsThumbnailStrip: Boolean,
    val previousInSeries: Publication?,
    val nextInSeries: Publication?,
)

/** What the menu does. */
internal data class ReaderMenuActions(
    val onDismiss: () -> Unit,
    val onOpenThumbnails: () -> Unit,
    val onOpenText: (PdfTextTab) -> Unit,
    val onAdjust: () -> Unit,
    val onChooseTransition: (PageTransition) -> Unit,
    val onToggleSeparator: (Boolean) -> Unit,
    val onChooseFit: (PageFit) -> Unit,
    val onChooseDirection: (ReadingDirection) -> Unit,
    val onToggleOffset: (Boolean) -> Unit,
    val onToggleOrientation: (Boolean) -> Unit,
    /** Where the drag is heading, or nothing once it is released. */
    val onScrub: (Int?) -> Unit,
    val onJump: (Int) -> Unit,
    val onOpenPublication: (Publication) -> Unit,
)

/**
 * The reader's menu.
 *
 * @param scrubbing the page a slider drag is heading for, while the finger is still down.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun ReaderMenuSheet(
    viewModel: ReaderViewModel,
    facts: ReaderMenuFacts,
    actions: ReaderMenuActions,
    scrubbing: Int?,
) {
    ModalBottomSheet(onDismissRequest = actions.onDismiss) {
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState())) {
            ContentsRow(
                pageIndex = scrubbing ?: facts.pageIndex,
                pageCount = facts.pageCount,
                onOpen = actions.onOpenThumbnails,
            )

            if (facts.showsThumbnailStrip) {
                ThumbnailStrip(
                    viewModel = viewModel,
                    pageCount = facts.pageCount,
                    currentIndex = facts.pageIndex,
                    onSelect = { index ->
                        // A jump, like the slider's: it leaves the same mark, so the way back
                        // from a mis-tap in a three-hundred-page strip is one control.
                        actions.onJump(index)
                        actions.onDismiss()
                    },
                    modifier = Modifier.padding(horizontal = StoryArcSpace.gutter),
                )
            }

            // `comic-reader`: the slider is offered "where pages are the unit a reader moves
            // in". One page is not a unit anybody moves in.
            if (facts.pageCount > 1) {
                PageSlider(
                    viewModel = viewModel,
                    index = scrubbing ?: facts.pageIndex,
                    count = facts.pageCount,
                    scrubbing = scrubbing,
                    onScrub = actions.onScrub,
                    onJump = actions.onJump,
                )
            }

            HorizontalDivider()

            // Marks and search both live in the PDF text sheet, which opens on the panel the
            // row names — that is what makes each of them one action rather than two. Absent
            // for a comic and for a scan: `ebook-reader` hides a text-dependent control
            // rather than disabling it, and there is no text layer to search.
            if (facts.hasPdfText) {
                MenuRow(ReaderMenuEntry.BOOKMARKS, Icons.Filled.Bookmark) {
                    actions.onOpenText(PdfTextTab.MARKS)
                }
                MenuRow(ReaderMenuEntry.SEARCH, Icons.AutoMirrored.Filled.ManageSearch) {
                    actions.onOpenText(PdfTextTab.SEARCH)
                }
            }

            MenuRow(ReaderMenuEntry.THEMES, Icons.Filled.Tune, actions.onAdjust)

            ChapterRows(
                previous = facts.previousInSeries,
                next = facts.nextInSeries,
                onOpen = actions.onOpenPublication,
            )

            HorizontalDivider()

            Text(
                text = stringResource(ReaderMenuEntry.SETTINGS.labelRes),
                style = MaterialTheme.typography.titleSmall,
                modifier = Modifier.padding(
                    horizontal = StoryArcSpace.gutter,
                    vertical = StoryArcSpace.sm,
                ),
            )

            ReaderSettingsRows(
                choices = facts.choices,
                showsSeparator = facts.showsSeparator,
                onToggleSeparator = actions.onToggleSeparator,
                onChooseTransition = actions.onChooseTransition,
                fit = facts.fit,
                onChooseFit = actions.onChooseFit,
                direction = facts.direction,
                onChooseDirection = actions.onChooseDirection,
                hasPairs = facts.hasPairs,
                isOffset = facts.isOffset,
                onToggleOffset = actions.onToggleOffset,
                isOrientationLocked = facts.isOrientationLocked,
                onToggleOrientation = actions.onToggleOrientation,
            )

            SkippedNotice(facts.skippedPageCount)
        }
    }
}

/**
 * The contents row: where the reader is, and where else they could be.
 *
 * One row for *where am I* and *where else could I be*, because a reader asking the first
 * question is usually about to ask the second. `comic-reader` puts the position "in text on
 * that row", and the thumbnail browser is what the row opens.
 *
 * `comic-reader`, *Where the reader is, at a glance*: "the coarse position through the
 * publication is drawn as a fill behind the menu's own contents row … the text is what
 * conveys the position, so the fill may be absent without anything being lost".
 *
 * **The flat indicator, not the wavy one.** Material cautions that the wavy variant changes
 * the component's height and "may not be as visible" at small sizes, and says linear
 * indicators "shouldn't be used in any elements smaller than 40dp". A thin fill behind a list
 * row is precisely that case. The wavy indicator stays where the height exists: downloads and
 * imports.
 *
 * **Decorative to assistive technology.** The text above already states the page and the
 * total. A page number announced twice is a page number announced wrong, so the indicator is
 * cleared of semantics rather than labelled.
 */
@Composable
private fun ContentsRow(pageIndex: Int, pageCount: Int, onOpen: () -> Unit) {
    Box(Modifier.fillMaxWidth().clickableRow(onOpen)) {
        LinearProgressIndicator(
            // A single page is all the way through itself; anything else is where the reader
            // has reached out of the turns available.
            progress = {
                if (pageCount > 1) pageIndex.toFloat() / (pageCount - 1) else 1f
            },
            color = LocalStoryArcPalette.current.accent.copy(alpha = 0.14f),
            trackColor = Color.Transparent,
            drawStopIndicator = {},
            modifier = Modifier.matchParentSize().clearAndSetSemantics {},
        )
        ListItem(
            supportingContent = {
                Text(stringResource(R.string.reader_page, pageIndex + 1, pageCount))
            },
            leadingContent = {
                Icon(imageVector = Icons.AutoMirrored.Filled.List, contentDescription = null)
            },
            colors = ListItemDefaults.colors(containerColor = Color.Transparent),
            modifier = Modifier.fillMaxWidth(),
        ) { Text(stringResource(ReaderMenuEntry.CONTENTS.labelRes)) }
    }
}

/**
 * The page slider, on a menu row rather than over the page.
 *
 * `comic-reader`: "the page slider SHALL live in the reader's menu rather than over the
 * page". Everything else about it is unchanged — the drag scrubs, the thumbnail follows, and
 * only the release moves the reader, which is what stops a scrub across a long comic asking
 * the archive for every page on the way. TalkBack's own adjustment lands here too: Compose
 * calls the finished callback after an accessibility action, so a stepped slider still turns
 * the page.
 */
@Composable
private fun PageSlider(
    viewModel: ReaderViewModel,
    index: Int,
    count: Int,
    scrubbing: Int?,
    onScrub: (Int?) -> Unit,
    onJump: (Int) -> Unit,
) {
    val sliderName = stringResource(R.string.reader_page_slider)
    val pageLabel = stringResource(R.string.reader_page, index + 1, count)

    Column(Modifier.fillMaxWidth().padding(horizontal = StoryArcSpace.gutter)) {
        scrubbing?.let { target ->
            ScrubThumbnail(
                viewModel = viewModel,
                index = target,
                modifier = Modifier.padding(bottom = StoryArcSpace.xs),
            )
        }
        Slider(
            value = index.toFloat(),
            onValueChange = { value -> onScrub(value.roundToInt()) },
            onValueChangeFinished = {
                scrubbing?.let(onJump)
                onScrub(null)
            },
            valueRange = 0f..(count - 1).toFloat(),
            steps = (count - 2).coerceAtLeast(0),
            // Named, and reading the page rather than the range percent Compose announces
            // by default.
            modifier = Modifier.fillMaxWidth().semantics {
                contentDescription = sliderName
                stateDescription = pageLabel
            },
        )
    }
}

/**
 * Previous and next chapter, as two named rows.
 *
 * Two icon-only pills over the page until now. Named here, because the neighbour of a
 * chapter is a *publication* and its title is the only thing that says which one pressing
 * this opens. Disabled at the end of the run rather than absent: the first and the last issue
 * of a series each have one neighbour, and a section that changed shape between them would
 * move the other row under the finger.
 *
 * Skip-previous and skip-next rather than a chevron: this is the track-skip idiom, and it
 * does not mirror for a right-to-left publication — the series still runs from its first
 * issue to its last whichever way its pages do.
 */
@Composable
private fun ChapterRows(previous: Publication?, next: Publication?, onOpen: (Publication) -> Unit) {
    if (previous == null && next == null) return
    ChapterRow(previous, Icons.Filled.SkipPrevious, R.string.reader_chapter_previous, onOpen)
    ChapterRow(next, Icons.Filled.SkipNext, R.string.reader_chapter_next, onOpen)
}

@Composable
private fun ChapterRow(
    destination: Publication?,
    icon: ImageVector,
    labelRes: Int,
    onOpen: (Publication) -> Unit,
) {
    ListItem(
        supportingContent = destination?.let { { Text(it.displayTitle) } },
        leadingContent = { Icon(imageVector = icon, contentDescription = null) },
        modifier = Modifier
            .fillMaxWidth()
            .let { if (destination == null) it else it.clickableRow { onOpen(destination) } },
    ) { Text(stringResource(labelRes)) }
}

/**
 * How many entries the archive could not give us, when any.
 *
 * `publication-formats`: a damaged archive opens "whatever pages it can read and states how
 * many were skipped". It was drawn over the page until now, which made it one more thing
 * between the reader and the artwork; it is a fact about the file, and the menu is where this
 * reader's facts live.
 */
@Composable
private fun SkippedNotice(count: Int) {
    if (count <= 0) return
    Text(
        text = pluralStringResource(R.plurals.reader_skipped, count, count),
        style = MaterialTheme.typography.labelSmall,
        modifier = Modifier.padding(
            horizontal = StoryArcSpace.gutter,
            vertical = StoryArcSpace.sm,
        ),
    )
}

/** One of the five doors, named by the entry rather than by this file. */
@Composable
private fun MenuRow(entry: ReaderMenuEntry, icon: ImageVector, onClick: () -> Unit) {
    ListItem(
        leadingContent = { Icon(imageVector = icon, contentDescription = null) },
        modifier = Modifier.fillMaxWidth().clickableRow(onClick),
    ) { Text(stringResource(entry.labelRes)) }
}

/**
 * How the five rows are named on screen.
 *
 * The enum lives in `:core:model` and carries no resources, for the same reason `PageFit`
 * does not: the domain has no business holding UI copy.
 */
private val ReaderMenuEntry.labelRes: Int
    get() = when (this) {
        ReaderMenuEntry.CONTENTS -> R.string.reader_menu_contents
        ReaderMenuEntry.BOOKMARKS -> R.string.reader_menu_bookmarks
        ReaderMenuEntry.SEARCH -> R.string.reader_menu_search
        ReaderMenuEntry.THEMES -> R.string.reader_menu_themes
        ReaderMenuEntry.SETTINGS -> R.string.reader_menu_settings
    }

/** A whole list row as the target, which is well past the platform's minimum touch size. */
private fun Modifier.clickableRow(onClick: () -> Unit): Modifier = this.clickable(onClick = onClick)
