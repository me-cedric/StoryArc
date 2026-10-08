package app.storyarc.feature.library

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.wrapContentHeight
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import app.storyarc.core.designsystem.control.MIN_TOUCH_TARGET
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcSpace

/**
 * One recent search, which a tap uses again.
 *
 * Task 24.4 of `close-the-audited-gaps`: a line of text with a little padding was 40 dp high.
 * The row is at least 48 dp, with the text centred in it.
 */
@Composable
internal fun RecentSearchRow(term: String, onUse: () -> Unit) {
    Text(
        text = term,
        style = MaterialTheme.typography.bodyLarge,
        color = LocalStoryArcPalette.current.textPrimary,
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onUse)
            .heightIn(min = MIN_TOUCH_TARGET)
            .wrapContentHeight(Alignment.CenterVertically)
            .padding(StoryArcSpace.gutter, StoryArcSpace.sm),
    )
}
