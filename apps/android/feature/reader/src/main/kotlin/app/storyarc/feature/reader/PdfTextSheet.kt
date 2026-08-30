package app.storyarc.feature.reader

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.theme.swatch
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.Annotation
import app.storyarc.core.model.AnnotationExport
import app.storyarc.core.model.SearchMatch

/**
 * Where a reader goes looking inside a PDF: the search, and the marks they made.
 *
 * One sheet with two tabs rather than two controls in the chrome, because both answer the same
 * question -- where in this publication do I go -- and a reader who opened the wrong one would
 * have to close it to ask again. The EPUB reader's sheet is built the same way for the same
 * reason, with three tabs rather than two.
 *
 * Two, not three: iOS's sheet also holds the document's own navigation, and this platform's PDF
 * API exposes no outline to show. ADR-0011 records that, and the tab is absent rather than empty.
 */
internal enum class PdfTextTab(val labelRes: Int) {
    SEARCH(R.string.reader_pdf_tab_search),
    MARKS(R.string.reader_pdf_tab_marks),
}

@Composable
internal fun PdfTextSheet(
    state: PdfTextState,
    matches: List<SearchMatch>,
    isSearching: Boolean,
    isCapped: Boolean,
    annotations: List<Annotation>,
    onSearch: (String) -> Unit,
    onGo: (Int) -> Unit,
    onNote: (Annotation) -> Unit,
    onRemove: (Annotation) -> Unit,
    onExport: (AnnotationExport.Format) -> Unit,
    modifier: Modifier = Modifier,
) {
    var tab by remember { mutableStateOf(PdfTextTab.SEARCH) }

    Column(modifier = modifier.fillMaxWidth()) {
        SingleChoiceSegmentedButtonRow(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = StoryArcSpace.gutter, vertical = StoryArcSpace.sm),
        ) {
            PdfTextTab.entries.forEachIndexed { index, candidate ->
                SegmentedButton(
                    selected = tab == candidate,
                    onClick = { tab = candidate },
                    shape = SegmentedButtonDefaults.itemShape(index, PdfTextTab.entries.size),
                ) {
                    Text(stringResource(candidate.labelRes))
                }
            }
        }

        when (tab) {
            PdfTextTab.SEARCH -> PdfSearchList(
                matches = matches,
                isSearching = isSearching,
                isCapped = isCapped,
                onSearch = onSearch,
                onGo = { match -> state.page(match)?.let(onGo) },
            )
            PdfTextTab.MARKS -> PdfMarkList(
                annotations = annotations,
                onGo = { annotation -> state.page(annotation)?.let(onGo) },
                onNote = onNote,
                onRemove = onRemove,
                onExport = onExport,
            )
        }
    }
}

/**
 * Searching inside the publication.
 *
 * `ebook-reader`: "matches are listed with surrounding context and tapping one jumps to it". The
 * match is emboldened inside its own line rather than shown as a separate field -- a row that
 * read "context / match / context" in three styles would be three things to read, and one
 * sentence with the word standing out is one.
 *
 * iOS's `PdfSearchList` draws the same rows.
 */
@Composable
private fun PdfSearchList(
    matches: List<SearchMatch>,
    isSearching: Boolean,
    isCapped: Boolean,
    onSearch: (String) -> Unit,
    onGo: (SearchMatch) -> Unit,
) {
    val palette = LocalStoryArcPalette.current
    var query by remember { mutableStateOf("") }

    Column(modifier = Modifier.fillMaxWidth()) {
        OutlinedTextField(
            value = query,
            onValueChange = {
                query = it
                onSearch(it)
            },
            singleLine = true,
            label = { Text(stringResource(R.string.reader_pdf_search)) },
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
            keyboardActions = KeyboardActions(onSearch = { onSearch(query) }),
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = StoryArcSpace.gutter, vertical = StoryArcSpace.sm),
        )

        when {
            // Said while it runs, because a long document takes a moment and a list that is
            // merely empty looks like an answer.
            isSearching && matches.isEmpty() -> Column(
                modifier = Modifier.fillMaxWidth().padding(StoryArcSpace.gutter),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(StoryArcSpace.sm),
            ) {
                CircularProgressIndicator()
                Text(
                    text = stringResource(R.string.reader_pdf_search_running),
                    style = MaterialTheme.typography.bodySmall,
                    color = palette.textSecondary,
                )
            }

            query.isNotBlank() && matches.isEmpty() -> Text(
                text = stringResource(R.string.reader_pdf_search_none),
                style = MaterialTheme.typography.bodySmall,
                color = palette.textSecondary,
                modifier = Modifier.fillMaxWidth().padding(StoryArcSpace.gutter),
            )

            else -> LazyColumn(
                modifier = Modifier.fillMaxWidth().heightIn(max = 380.dp),
                contentPadding = PaddingValues(bottom = StoryArcSpace.lg),
            ) {
                // No key: two hits on one page share a locator, and a duplicate key crashes a
                // `LazyColumn`. Position is the identity here, and the list is replaced
                // wholesale rather than edited.
                items(matches) { match ->
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable(role = Role.Button) { onGo(match) }
                            .padding(
                                horizontal = StoryArcSpace.gutter,
                                vertical = StoryArcSpace.sm,
                            ),
                    ) {
                        if (match.chapter.isNotBlank()) {
                            Text(
                                text = match.chapter,
                                style = MaterialTheme.typography.labelSmall,
                                color = palette.textSecondary,
                            )
                        }
                        Text(
                            text = buildAnnotatedString {
                                if (match.snippet.before.isNotEmpty()) {
                                    append(match.snippet.before + " ")
                                }
                                withStyle(SpanStyle(fontWeight = FontWeight.Bold)) {
                                    append(match.snippet.match)
                                }
                                if (match.snippet.after.isNotEmpty()) {
                                    append(" " + match.snippet.after)
                                }
                            },
                            style = MaterialTheme.typography.bodySmall,
                            maxLines = 2,
                            overflow = TextOverflow.Ellipsis,
                        )
                    }
                }

                if (isCapped) {
                    // Stated rather than applied quietly: a truncated list that says it is
                    // truncated is still a list a reader can trust.
                    item {
                        Text(
                            text = stringResource(R.string.reader_pdf_search_capped),
                            style = MaterialTheme.typography.labelSmall,
                            color = palette.textSecondary,
                            modifier = Modifier.padding(
                                horizontal = StoryArcSpace.gutter,
                                vertical = StoryArcSpace.sm,
                            ),
                        )
                    }
                }
            }
        }
    }
}

/**
 * Everything a reader marked in a PDF, in one place.
 *
 * `ebook-reader`: "highlights and notes are listed in one place and exportable as plain text or
 * Markdown". One list, because a note is a highlight with something written on it -- two lists
 * would be the app insisting on a distinction the reader did not make.
 *
 * The record, the store and both export documents are the ones the EPUB reader writes, which is
 * why a highlight made in a PDF comes out of the same export as one made in a novel.
 *
 * iOS's `PdfMarkList` draws the same rows.
 */
@Composable
private fun PdfMarkList(
    annotations: List<Annotation>,
    onGo: (Annotation) -> Unit,
    onNote: (Annotation) -> Unit,
    onRemove: (Annotation) -> Unit,
    onExport: (AnnotationExport.Format) -> Unit,
) {
    val palette = LocalStoryArcPalette.current

    if (annotations.isEmpty()) {
        // Says what the control is rather than that there is nothing: a reader who has never
        // pressed on a word has no reason to know a menu appears when they do.
        Text(
            text = stringResource(R.string.reader_pdf_marks_empty),
            style = MaterialTheme.typography.bodySmall,
            color = palette.textSecondary,
            modifier = Modifier.fillMaxWidth().padding(StoryArcSpace.gutter),
        )
        return
    }

    Column(modifier = Modifier.fillMaxWidth()) {
        LazyColumn(
            modifier = Modifier.fillMaxWidth().heightIn(max = 340.dp),
            contentPadding = PaddingValues(bottom = StoryArcSpace.sm),
        ) {
            items(annotations, key = { it.id }) { annotation ->
                Row(
                    verticalAlignment = Alignment.Top,
                    horizontalArrangement = Arrangement.spacedBy(StoryArcSpace.sm),
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable(role = Role.Button) { onGo(annotation) }
                        .padding(horizontal = StoryArcSpace.gutter, vertical = StoryArcSpace.sm),
                ) {
                    // The colour the reader chose, as a bar rather than a dot: it reads as the
                    // highlight it stands for, and it is what makes a colour-coded list
                    // scannable.
                    ColourBar(annotation.colour.swatch)

                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            text = annotation.chapter,
                            style = MaterialTheme.typography.labelSmall,
                            color = palette.textSecondary,
                        )
                        Text(
                            text = annotation.text,
                            style = MaterialTheme.typography.bodySmall,
                            maxLines = 3,
                            overflow = TextOverflow.Ellipsis,
                        )
                        if (annotation.hasNote) {
                            Text(
                                text = annotation.note,
                                style = MaterialTheme.typography.labelSmall,
                                color = palette.textSecondary,
                                maxLines = 3,
                                overflow = TextOverflow.Ellipsis,
                            )
                        }
                    }

                    TextButton(onClick = { onNote(annotation) }) {
                        Text(stringResource(R.string.reader_pdf_note))
                    }
                    TextButton(onClick = { onRemove(annotation) }) {
                        Text(stringResource(R.string.reader_pdf_marks_remove))
                    }
                }
            }
        }

        // Both formats, side by side, because the spec offers both and a reader choosing one is
        // choosing where they are about to paste it.
        Row(
            modifier = Modifier.fillMaxWidth().padding(StoryArcSpace.sm),
            horizontalArrangement = Arrangement.spacedBy(StoryArcSpace.md),
        ) {
            TextButton(onClick = { onExport(AnnotationExport.Format.PLAIN_TEXT) }) {
                Text(stringResource(R.string.reader_pdf_export_text))
            }
            TextButton(onClick = { onExport(AnnotationExport.Format.MARKDOWN) }) {
                Text(stringResource(R.string.reader_pdf_export_markdown))
            }
        }
    }
}

/** The colour bar beside a mark's row. */
@Composable
private fun ColourBar(colour: Color) {
    Box(
        modifier = Modifier
            .size(width = 4.dp, height = 36.dp)
            .background(colour, RoundedCornerShape(2.dp)),
    )
}

/**
 * Writing on a mark.
 *
 * A dialog rather than a sheet: it is one field and two buttons, and it is asked for while the
 * reader is looking at the words it is about. iOS presents the same thing as a half-height
 * sheet, which is where an iOS reader expects a small editor.
 */
@Composable
internal fun PdfNoteDialog(
    initial: String,
    onSave: (String) -> Unit,
    onDismiss: () -> Unit,
) {
    var text by remember(initial) { mutableStateOf(initial) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.reader_pdf_note)) },
        text = {
            OutlinedTextField(value = text, onValueChange = { text = it })
        },
        confirmButton = {
            TextButton(onClick = { onSave(text) }) {
                Text(stringResource(R.string.reader_pdf_note_save))
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text(stringResource(R.string.reader_pdf_note_cancel))
            }
        },
    )
}

/**
 * The one sentence a PDF without a text layer gets.
 *
 * A statement rather than a control. There is no search box to explain, so this is the only
 * place a reader can learn that the file is a picture of a page.
 */
@Composable
internal fun PdfNoTextDialog(onDismiss: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.reader_pdf_no_text_title)) },
        text = { Text(stringResource(R.string.reader_pdf_no_text_message)) },
        confirmButton = {
            TextButton(onClick = onDismiss) {
                Text(stringResource(R.string.reader_pdf_no_text_done))
            }
        },
    )
}
