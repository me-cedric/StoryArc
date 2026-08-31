package app.storyarc.feature.epubreader

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Toc
import androidx.compose.material.icons.automirrored.filled.VolumeUp
import androidx.compose.material.icons.filled.Bookmark
import androidx.compose.material.icons.filled.Highlight
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.TextFormat
import androidx.compose.material.icons.outlined.BookmarkBorder
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.ChapterRemainder
import app.storyarc.core.model.ReaderMenuEntry
import app.storyarc.core.model.ReadingPositionLine

/*
 * The one door out of the two-control chrome, and everything behind it.
 *
 * `comic-reader`, *Everything else is in the menu, and labelled*: "it offers the table of
 * contents, bookmarks, search within the publication, reading themes and reader settings,
 * each named in words rather than by icon alone … every control that was reachable from the
 * reader before this change is reachable from here in one action."
 *
 * `ReaderMenuEntry` in `:core:model` owns the five names and the order, and the comic
 * reader's menu is built from the same type. A reader who learns the menu in one has learned
 * it in the other — which was not true of five circular pills whose glyphs differed between
 * the two readers.
 *
 * **One action is the load-bearing half.** The contents sheet already held four panels behind
 * a tab row; four rows that each open it on their own panel is the difference between one
 * action and two.
 *
 * `ReaderMenuTest` asserts both halves.
 */

/** What the menu says. */
internal data class EpubMenuFacts(
    val chapter: String?,
    /** How far through the book, 0 to 1. */
    val progression: Double,
    /** How far through the current chapter, 0 to 1, or null where Readium has not said. */
    val withinChapter: Double?,
    val isPageBookmarked: Boolean,
    /** Whether the book's own navigation has been read yet. */
    val isContentsReady: Boolean,
    /** Whether this publication has any text a voice could say. */
    val canReadAloud: Boolean,
    val isReadingAloud: Boolean,
)

/** What the menu does. */
internal data class EpubMenuActions(
    val onDismiss: () -> Unit,
    val onOpenContents: (ContentsTab) -> Unit,
    val onToggleBookmark: () -> Unit,
    val onOpenTheme: () -> Unit,
    val onStartReadAloud: () -> Unit,
    val onStopReadAloud: () -> Unit,
)

/** The reader's menu. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun EpubMenuSheet(facts: EpubMenuFacts, actions: EpubMenuActions) {
    ModalBottomSheet(onDismissRequest = actions.onDismiss) {
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState())) {
            ContentsRow(
                position = ReadingPositionLine.of(
                    totalProgression = facts.progression,
                    chapter = facts.chapter,
                    withinChapter = facts.withinChapter,
                ),
                fraction = facts.progression.coerceIn(0.0, 1.0).toFloat(),
                isReady = facts.isContentsReady,
                onOpen = { actions.onOpenContents(ContentsTab.CONTENTS) },
            )

            MenuRow(ReaderMenuEntry.BOOKMARKS, Icons.Filled.Bookmark) {
                actions.onOpenContents(ContentsTab.BOOKMARKS)
            }

            // One row, not an add beside a remove: `ebook-reader` marks a *position*, and a
            // position is either marked or it is not. A circular pill whose filled and hollow
            // bookmark glyphs were the only statement of which, until now.
            LabelledRow(
                label = stringResource(
                    if (facts.isPageBookmarked) {
                        R.string.epub_bookmark_remove
                    } else {
                        R.string.epub_bookmark_add
                    },
                ),
                icon = if (facts.isPageBookmarked) {
                    Icons.Filled.Bookmark
                } else {
                    Icons.Outlined.BookmarkBorder
                },
                onClick = actions.onToggleBookmark,
            )

            MenuRow(ReaderMenuEntry.SEARCH, Icons.Filled.Search) {
                actions.onOpenContents(ContentsTab.SEARCH)
            }

            // Not one of the five doors, and offered anyway: highlights and notes were
            // reachable before this change, from the same sheet's fourth panel, and
            // `comic-reader` requires everything that was reachable to stay reachable in one
            // action.
            LabelledRow(
                label = stringResource(R.string.annotations_title),
                icon = Icons.Filled.Highlight,
                onClick = { actions.onOpenContents(ContentsTab.ANNOTATIONS) },
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

            MenuRow(ReaderMenuEntry.THEMES, Icons.Filled.TextFormat, actions.onOpenTheme)

            // Absent, not disabled, when the publication has no text a voice could say.
            // `ebook-reader` says a control a platform cannot honour is "absent rather than
            // empty", and this app does not ship a button that does nothing.
            if (facts.canReadAloud) {
                LabelledRow(
                    label = stringResource(
                        if (facts.isReadingAloud) R.string.readaloud_stop else R.string.readaloud_start,
                    ),
                    icon = Icons.AutoMirrored.Filled.VolumeUp,
                    onClick = if (facts.isReadingAloud) {
                        actions.onStopReadAloud
                    } else {
                        actions.onStartReadAloud
                    },
                )
            }
        }
    }
}

/**
 * The contents row: where the reader is, and where else they could be.
 *
 * `ebook-reader`: "one line states how far through the publication they are and how much of
 * the current chapter is left, in words". A percentage, never a page number — a reflowable
 * page count is a function of the type size, and the app refuses to present it as an
 * identity. [ReadingPositionLine] decides what the line says; this decides how it reads.
 *
 * `comic-reader`, *Where the reader is, at a glance*: "the coarse position through the
 * publication is drawn as a fill behind the menu's own contents row, and stated in text on
 * that row … the text is what conveys the position, so the fill may be absent without
 * anything being lost".
 *
 * **The flat indicator, not the wavy one.** Material cautions that the wavy variant changes
 * the component's height and "may not be as visible" at small sizes, and says linear
 * indicators "shouldn't be used in any elements smaller than 40dp". A thin fill behind a list
 * row is precisely that case. The wavy indicator stays where the height exists: downloads and
 * imports.
 *
 * **Decorative to assistive technology, and that is the load-bearing part.** The text above
 * already states the position. A percentage announced twice is a percentage announced wrong,
 * so the indicator is cleared of semantics rather than labelled.
 *
 * Refused rather than hidden until the book is open: a row that appeared a moment after the
 * sheet did would move the four under it.
 */
@Composable
private fun ContentsRow(
    position: ReadingPositionLine,
    /** How far through the book, 0 to 1, for the fill behind the row. */
    fraction: Float,
    isReady: Boolean,
    onOpen: () -> Unit,
) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .let { if (isReady) it.clickable(onClick = onOpen) else it },
    ) {
        LinearProgressIndicator(
            progress = { fraction },
            color = LocalStoryArcPalette.current.accent.copy(alpha = 0.14f),
            trackColor = Color.Transparent,
            drawStopIndicator = {},
            modifier = Modifier
                .matchParentSize()
                .clearAndSetSemantics {},
        )
        ListItem(
            supportingContent = { Text(position.asLine()) },
            leadingContent = {
                Icon(imageVector = Icons.AutoMirrored.Filled.Toc, contentDescription = null)
            },
            colors = ListItemDefaults.colors(containerColor = Color.Transparent),
            modifier = Modifier.fillMaxWidth(),
        ) { Text(stringResource(ReaderMenuEntry.CONTENTS.labelRes)) }
    }
}

/**
 * The line, as one sentence.
 *
 * Three localised fragments joined by punctuation rather than one resource with three
 * arguments, because the chapter's own title is the publication's and must not be translated,
 * and the band's phrase is shared with iOS's own catalogue. Each fragment is translated on its
 * own; the separators are punctuation.
 */
@Composable
private fun ReadingPositionLine.asLine(): String {
    val through = stringResource(R.string.epub_progress, percentThrough)
    val named = chapter ?: return through
    val remainder = chapterRemainder ?: return "$through · $named"
    return "$through · $named, " + stringResource(remainder.labelRes)
}

/**
 * How much of the chapter is left, in this reader's own words.
 *
 * The enum lives in `:core:model` and carries no resources: the domain has no business
 * holding UI copy. iOS names the same five bands from its own catalogue.
 */
private val ChapterRemainder.labelRes: Int
    get() = when (this) {
        ChapterRemainder.NEARLY_DONE -> R.string.reader_chapter_left_nearly_done
        ChapterRemainder.LESS_THAN_HALF_LEFT -> R.string.reader_chapter_left_less_than_half
        ChapterRemainder.ABOUT_HALF_LEFT -> R.string.reader_chapter_left_about_half
        ChapterRemainder.MORE_THAN_HALF_LEFT -> R.string.reader_chapter_left_more_than_half
        ChapterRemainder.JUST_BEGUN -> R.string.reader_chapter_left_just_begun
    }

/** One of the five doors, named by the entry rather than by this file. */
@Composable
private fun MenuRow(entry: ReaderMenuEntry, icon: ImageVector, onClick: () -> Unit) {
    LabelledRow(label = stringResource(entry.labelRes), icon = icon, onClick = onClick)
}

/** One row: an icon beside words, the whole row a target. */
@Composable
private fun LabelledRow(label: String, icon: ImageVector, onClick: () -> Unit) {
    ListItem(
        leadingContent = { Icon(imageVector = icon, contentDescription = null) },
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick),
    ) { Text(label) }
}

/**
 * How the five rows are named on screen.
 *
 * The enum lives in `:core:model` and carries no resources: the domain has no business
 * holding UI copy. The comic reader names the same five from its own catalogue.
 */
private val ReaderMenuEntry.labelRes: Int
    get() = when (this) {
        ReaderMenuEntry.CONTENTS -> R.string.reader_menu_contents
        ReaderMenuEntry.BOOKMARKS -> R.string.reader_menu_bookmarks
        ReaderMenuEntry.SEARCH -> R.string.reader_menu_search
        ReaderMenuEntry.THEMES -> R.string.reader_menu_themes
        ReaderMenuEntry.SETTINGS -> R.string.reader_menu_settings
    }
