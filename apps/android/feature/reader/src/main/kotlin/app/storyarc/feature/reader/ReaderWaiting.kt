package app.storyarc.feature.reader

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import app.storyarc.core.designsystem.tokens.StoryArcSpace

/**
 * Shown in place of [Message] while a streamed open waits for its download.
 *
 * dl-core 1.7: a wait is not an error, so a progress indicator stands where [Message] puts its
 * warning icon. iOS draws `ReaderWaitingForDownload` the same way.
 */
@Composable
internal fun WaitingForDownload() {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(StoryArcSpace.sm),
        modifier = Modifier.padding(StoryArcSpace.gutter),
    ) {
        CircularProgressIndicator(color = Color.White)
        Text(
            text = stringResource(R.string.reader_waiting_for_download),
            style = MaterialTheme.typography.bodySmall,
            color = Color.White.copy(alpha = 0.7f),
            textAlign = TextAlign.Center,
        )
    }
}
