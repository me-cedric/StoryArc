package app.storyarc.feature.epubreader

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
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
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.SearchMatch

/**
 * Searching inside the book, in the sheet the contents and the bookmarks already share.
 *
 * `ebook-reader`: "matches are listed with surrounding context and tapping one jumps to it".
 * The third thing a reader opens this sheet to do is find a word, and it is the same
 * question — where in this book do I go — so it is the same sheet.
 *
 * The match is emboldened inside its own line rather than shown as a separate field. A row
 * that read "context / match / context" in three styles would be three things to read; one
 * sentence with the word standing out is one.
 *
 * iOS's `SearchInBook` draws the same rows.
 */
@Composable
internal fun SearchInBook(
    matches: List<SearchMatch>,
    isSearching: Boolean,
    onSearch: (String) -> Unit,
    onGo: (SearchMatch) -> Unit,
    modifier: Modifier = Modifier,
) {
    val palette = LocalStoryArcPalette.current
    var query by remember { mutableStateOf("") }

    Column(modifier = modifier.fillMaxWidth()) {
        OutlinedTextField(
            value = query,
            onValueChange = {
                query = it
                onSearch(it)
            },
            singleLine = true,
            label = { Text(stringResource(R.string.epub_search)) },
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
            keyboardActions = KeyboardActions(onSearch = { onSearch(query) }),
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = StoryArcSpace.gutter, vertical = StoryArcSpace.sm),
        )

        when {
            // Said while it runs, because a long book takes a moment and a list that is
            // merely empty looks like an answer.
            isSearching && matches.isEmpty() -> Column(
                modifier = Modifier.fillMaxWidth().padding(StoryArcSpace.gutter),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(StoryArcSpace.sm),
            ) {
                CircularProgressIndicator()
                Text(
                    text = stringResource(R.string.epub_search_running),
                    style = MaterialTheme.typography.bodySmall,
                    color = palette.textSecondary,
                )
            }

            query.isNotBlank() && matches.isEmpty() -> Text(
                text = stringResource(R.string.epub_search_none, query),
                style = MaterialTheme.typography.bodySmall,
                color = palette.textSecondary,
                modifier = Modifier.fillMaxWidth().padding(StoryArcSpace.gutter),
            )

            else -> LazyColumn(
                modifier = Modifier.fillMaxWidth().heightIn(max = 380.dp),
                contentPadding = PaddingValues(bottom = StoryArcSpace.lg),
            ) {
                // No key: two hits on one page share a locator's resource and progression,
                // and a duplicate key crashes a `LazyColumn`. Position is the identity here,
                // and the list is replaced wholesale rather than edited.
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
                                style = MaterialTheme.typography.labelMedium,
                                color = palette.textSecondary,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                            )
                        }
                        Text(
                            text = buildAnnotatedString {
                                if (match.snippet.before.isNotEmpty()) {
                                    append(match.snippet.before)
                                    append(" ")
                                }
                                withStyle(SpanStyle(fontWeight = FontWeight.Bold)) {
                                    append(match.snippet.match)
                                }
                                if (match.snippet.after.isNotEmpty()) {
                                    append(" ")
                                    append(match.snippet.after)
                                }
                            },
                            style = MaterialTheme.typography.bodyMedium,
                            color = palette.textPrimary,
                            maxLines = 3,
                            overflow = TextOverflow.Ellipsis,
                        )
                    }
                }
            }
        }
    }
}
