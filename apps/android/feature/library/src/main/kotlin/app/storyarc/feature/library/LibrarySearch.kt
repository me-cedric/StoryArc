package app.storyarc.feature.library

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.res.stringResource
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.RecentSearches

/**
 * `library-browsing`: results update as the user types, debounced, with no submit
 * action. Arranging is a sort of what is already in memory, so a keystroke costs
 * one pass rather than a request.
 */
@Composable
internal fun SearchField(
    value: String,
    recents: RecentSearches,
    onChange: (String) -> Unit,
    onClearRecents: () -> Unit,
    modifier: Modifier = Modifier,
) {
    var isFocused by remember { mutableStateOf(false) }

    Column(modifier = modifier) {
        OutlinedTextField(
            value = value,
            onValueChange = onChange,
            singleLine = true,
            leadingIcon = { Icon(Icons.Filled.Search, contentDescription = null) },
            placeholder = { Text(stringResource(R.string.library_search)) },
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = StoryArcSpace.gutter, vertical = StoryArcSpace.sm)
                .onFocusChanged { isFocused = it.isFocused },
        )
        // Offered only while nothing has been typed — once there is a term, the
        // results below are the better answer, and a list of old searches on top of
        // them would hide what was just found.
        if (isFocused && value.isBlank() && !recents.isEmpty) {
            RecentSearchList(recents.terms, onUse = onChange, onClear = onClearRecents)
        }
    }
}

/**
 * What the reader searched for lately, under an open search field.
 *
 * `library-browsing`: "when a user opens search, recent queries are offered, and
 * can be cleared". Choosing one puts the term in the field, which runs the search:
 * a recent query is a shortcut to the search, not to whatever it found last time.
 */
@Composable
private fun RecentSearchList(
    terms: List<String>,
    onUse: (String) -> Unit,
    onClear: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val palette = LocalStoryArcPalette.current

    Column(modifier = modifier.padding(horizontal = StoryArcSpace.gutter)) {
        Text(
            text = stringResource(R.string.library_search_recent),
            style = MaterialTheme.typography.labelLarge,
            color = palette.textTertiary,
            modifier = Modifier.padding(vertical = StoryArcSpace.xs),
        )
        terms.forEach { term ->
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable { onUse(term) }
                    // Material's 48 dp touch-target floor, per `native-experience`.
                    .heightIn(min = StoryArcSpace.xxl + StoryArcSpace.lg)
                    .padding(vertical = StoryArcSpace.xs),
                horizontalArrangement = Arrangement.spacedBy(StoryArcSpace.md),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(
                    imageVector = Icons.Filled.History,
                    contentDescription = null,
                    tint = palette.textTertiary,
                )
                Text(
                    text = term,
                    style = MaterialTheme.typography.bodyMedium,
                    color = palette.textPrimary,
                )
            }
        }
        TextButton(onClick = onClear) {
            Text(stringResource(R.string.library_search_recent_clear))
        }
    }
}
