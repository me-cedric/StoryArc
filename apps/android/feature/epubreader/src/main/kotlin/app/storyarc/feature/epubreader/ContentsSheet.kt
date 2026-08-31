package app.storyarc.feature.epubreader

import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.PrimaryTabRow
import androidx.compose.material3.Tab
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.res.stringResource
import app.storyarc.core.model.Annotation
import app.storyarc.core.model.AnnotationExport
import app.storyarc.core.model.Bookmark
import app.storyarc.core.model.SearchMatch
import org.readium.r2.shared.publication.Link
import org.readium.r2.shared.util.Url

/*
 * Where in this book do I go — four panels of the one answer.
 *
 * Split out of `EpubReaderActivity.kt`, which is over this project's 800-line ceiling and
 * recorded in `scripts/line-cap.mjs` as debt that may shrink and may not grow. The seam is
 * not arbitrary: everything here is one surface, and the activity keeps the screen and its
 * lifecycle.
 */
/** The table of contents, in the same modal bottom sheet the theme sheet uses. */
@OptIn(ExperimentalMaterial3Api::class)
@androidx.compose.runtime.Composable
internal fun ContentsBottomSheet(
    entries: List<Link>,
    currentResource: Url?,
    bookmarks: List<Bookmark>,
    matches: List<SearchMatch>,
    isSearching: Boolean,
    annotations: List<Annotation>,
    onGo: (Link) -> Unit,
    onGoToBookmark: (Bookmark) -> Unit,
    onRemoveBookmark: (Bookmark) -> Unit,
    onSearch: (String) -> Unit,
    onGoToMatch: (SearchMatch) -> Unit,
    onGoToAnnotation: (Annotation) -> Unit,
    onEditAnnotation: (Annotation) -> Unit,
    onRemoveAnnotation: (Annotation) -> Unit,
    onExportAnnotations: (AnnotationExport.Format) -> Unit,
    onDismiss: () -> Unit,
    /**
     * Which panel the sheet opens on.
     *
     * The reader's menu has a row per panel, and `comic-reader` requires each control to be
     * "reachable from here in one action". A sheet that always opened on the contents would
     * make three of the four rows cost two.
     */
    opensOn: ContentsTab = ContentsTab.CONTENTS,
) {
    var tab by remember(opensOn) { mutableStateOf(opensOn) }

    ModalBottomSheet(onDismissRequest = onDismiss) {
        PrimaryTabRow(selectedTabIndex = ContentsTab.entries.indexOf(tab)) {
            ContentsTab.entries.forEach { candidate ->
                Tab(
                    selected = tab == candidate,
                    onClick = { tab = candidate },
                    text = { Text(stringResource(candidate.labelRes)) },
                )
            }
        }

        when (tab) {
            ContentsTab.BOOKMARKS -> Bookmarks(
                bookmarks = bookmarks,
                onGo = onGoToBookmark,
                onRemove = onRemoveBookmark,
            )
            ContentsTab.SEARCH -> SearchInBook(
                matches = matches,
                isSearching = isSearching,
                onSearch = onSearch,
                onGo = onGoToMatch,
            )
            ContentsTab.ANNOTATIONS -> Annotations(
                annotations = annotations,
                onGo = onGoToAnnotation,
                onEdit = onEditAnnotation,
                onRemove = onRemoveAnnotation,
                onExport = onExportAnnotations,
            )
            ContentsTab.CONTENTS -> TableOfContents(
                entries = entries,
                currentResource = currentResource,
                onGo = onGo,
            )
        }
    }
}

/** How the four panels are named on screen. */
private val ContentsTab.labelRes: Int
    get() = when (this) {
        ContentsTab.CONTENTS -> R.string.epub_contents
        ContentsTab.BOOKMARKS -> R.string.epub_bookmarks
        ContentsTab.SEARCH -> R.string.epub_search
        ContentsTab.ANNOTATIONS -> R.string.annotations_title
    }
