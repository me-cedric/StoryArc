package app.storyarc.feature.epubreader

import androidx.compose.foundation.clickable
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
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.ReaderMenuEntry
import kotlin.math.roundToInt

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
                chapter = facts.chapter,
                progression = facts.progression,
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
 * `ebook-reader`: "one line states how far through the publication they are". A percentage,
 * never a page number — a reflowable page count is a function of the type size, and the app
 * refuses to present it as an identity.
 *
 * Refused rather than hidden until the book is open: a row that appeared a moment after the
 * sheet did would move the four under it.
 */
@Composable
private fun ContentsRow(
    chapter: String?,
    progression: Double,
    isReady: Boolean,
    onOpen: () -> Unit,
) {
    val line = if (chapter == null) {
        stringResource(R.string.epub_progress, (progression * 100).roundToInt())
    } else {
        stringResource(
            R.string.epub_progress_chapter,
            (progression * 100).roundToInt(),
            chapter,
        )
    }

    ListItem(
        supportingContent = { Text(line) },
        leadingContent = {
            Icon(imageVector = Icons.AutoMirrored.Filled.Toc, contentDescription = null)
        },
        modifier = Modifier
            .fillMaxWidth()
            .let { if (isReady) it.clickable(onClick = onOpen) else it },
    ) { Text(stringResource(ReaderMenuEntry.CONTENTS.labelRes)) }
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
