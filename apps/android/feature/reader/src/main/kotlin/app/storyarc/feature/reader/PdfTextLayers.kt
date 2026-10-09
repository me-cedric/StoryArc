package app.storyarc.feature.reader

import android.content.ClipData
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.runtime.Composable
import androidx.compose.runtime.MutableState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.ClipEntry
import androidx.compose.ui.platform.LocalClipboard
import androidx.compose.ui.platform.LocalContext
import app.storyarc.core.format.PdfTextSelection
import app.storyarc.core.model.Annotation
import app.storyarc.core.model.AnnotationExport
import app.storyarc.core.model.HighlightColour
import app.storyarc.core.model.SearchMatch
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

/**
 * The selection menu, the find sheet, the note editor, and the one sentence a PDF with no text gets.
 *
 * Moved out of [Pager] unchanged. The pager keeps the four states, because its menu and its pages
 * set them too, and hands them over here.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun PdfTextLayers(
    pdfText: PdfTextState?,
    pdfSelection: PdfTextSelection?,
    pdfMatches: List<SearchMatch>,
    isPdfSearching: Boolean,
    isPdfCapped: Boolean,
    pdfAnnotations: List<Annotation>,
    pageLabel: (Int) -> String,
    scope: CoroutineScope,
    jump: (Int) -> Unit,
    comicBookmarks: ComicBookmarksHolder,
    notingState: MutableState<Annotation?>,
    pdfTextTabState: MutableState<PdfTextTab>,
    findingText: MutableState<Boolean>,
    noTextState: MutableState<Boolean>,
) {
    var noting by notingState
    var pdfTextTab by pdfTextTabState
    var isFindingText by findingText
    var saysThereIsNoText by noTextState
    val clipboard = LocalClipboard.current
    val context = LocalContext.current

    val text = pdfText
    val selected = pdfSelection
    if (text != null && selected != null && selected.text.isNotBlank()) {
        val chapter = pageLabel(selected.locator.page)
        Box(
            modifier = Modifier.fillMaxSize().safeDrawingPadding(),
            contentAlignment = Alignment.BottomCenter,
        ) {
            PdfSelectionBar(
                text = selected.text,
                onHighlight = { colour -> scope.launch { text.highlight(colour, chapter) } },
                // A note is a highlight with something written on it, so there is nothing to
                // write on until the highlight exists. Marking in the first colour and opening
                // the editor is the shortest honest path from "these words" to "and here is
                // what I think of them"; a reader who wanted another colour changes it in the
                // list afterwards.
                onNote = {
                    scope.launch { noting = text.highlight(HighlightColour.YELLOW, chapter) }
                },
                onCopy = {
                    scope.launch {
                        clipboard.setClipEntry(
                            ClipEntry(ClipData.newPlainText(null, selected.text)),
                        )
                    }
                    text.clearSelection()
                },
                onSearch = {
                    val words = selected.text
                    text.clearSelection()
                    pdfTextTab = PdfTextTab.SEARCH
                    isFindingText = true
                    scope.launch { text.search(words, pageLabel) }
                },
                onDismiss = { text.clearSelection() },
            )
        }
    }

    if (isFindingText && text != null) {
        ModalBottomSheet(onDismissRequest = { isFindingText = false }) {
            PdfTextSheet(
                opensOn = pdfTextTab,
                state = text,
                matches = pdfMatches,
                isSearching = isPdfSearching,
                isCapped = isPdfCapped,
                annotations = pdfAnnotations,
                onSearch = { query -> scope.launch { text.search(query, pageLabel) } },
                onGo = { page ->
                    // A jump, like the slider's: it leaves the same way back, because
                    // `ebook-reader` asks for one control after a search hit, a mark or a
                    // link -- they are one act from the reader's side.
                    jump(page)
                    isFindingText = false
                },
                onNote = { noting = it },
                onRemove = { annotation -> scope.launch { text.remove(annotation.id) } },
                // The platform's own share sheet rather than a file this app writes:
                // `ebook-reader` asks for them to be "exportable", and where they go is the
                // reader's business.
                onExport = { format ->
                    shareAnnotations(
                        context,
                        AnnotationExport.document(pdfAnnotations, text.title, format),
                    )
                },
            )
        }
    } else if (isFindingText) {
        // D8: no text layer to search or an outline to browse, so this is the marks panel
        // alone -- a comic's or a scan's page bookmarks.
        ModalBottomSheet(onDismissRequest = { isFindingText = false }) {
            ComicBookmarkSheet(
                annotations = comicBookmarks.annotations,
                onGo = { page -> jump(page); isFindingText = false },
                onRemove = comicBookmarks::remove,
            )
        }
    }

    noting?.let { annotation ->
        PdfNoteDialog(
            initial = annotation.note,
            onSave = { note ->
                scope.launch { text?.annotate(annotation, note) }
                noting = null
            },
            onDismiss = { noting = null },
        )
    }

    if (saysThereIsNoText) {
        PdfNoTextDialog { saysThereIsNoText = false }
    }
}

/**
 * Hands a document to whatever the reader wants to keep it in.
 *
 * Nothing is written to disk: the export exists to leave this app, and a file cached on the way
 * out would be a copy of what a reader wrote that nobody asked for.
 */
private fun shareAnnotations(context: android.content.Context, document: String) {
    if (document.isBlank()) return
    context.startActivity(
        android.content.Intent.createChooser(
            android.content.Intent(android.content.Intent.ACTION_SEND).apply {
                type = "text/plain"
                putExtra(android.content.Intent.EXTRA_TEXT, document)
            },
            null,
        ),
    )
}
