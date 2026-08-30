package app.storyarc.feature.library

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcSpace

/**
 * What a source shows when the credential it has stored is no longer accepted.
 *
 * **`kavita-server`'s revoked-key scenario asks for "an explanation and an action to enter a
 * new key".** Android had the marking and the action -- `SourceDiagnosis` offers `RECONNECT`
 * on a source in this state, and it re-opens the sheet the source was added through with
 * everything but the secret filled in -- and no explanation at all: tapping the source opened
 * a browser whose every request failed, one after another, in silence. iOS's
 * `UnreachableSource` is this screen.
 *
 * Two sentences, not one, because there are two facts. A key the device has lost and a key the
 * server has refused lead to the same action and are not the same thing to say: "this device
 * no longer holds the key" is untrue of a reader whose key is still in the keystore.
 *
 * No "try again". Asking the same server the same refused key again is not a remedy, and a
 * button that cannot work is worse than none -- which is why this is not `OfflineSourceScreen`
 * with a different string.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun UnauthorizedSourceScreen(
    name: String,
    /** Whether the server refused the key rather than the device having lost it. */
    isRefused: Boolean,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val palette = LocalStoryArcPalette.current
    Scaffold(
        modifier = modifier.fillMaxSize(),
        containerColor = palette.surfaceCanvas,
        topBar = {
            TopAppBar(
                title = { Text(name) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = stringResource(R.string.catalogue_back),
                            tint = palette.accent,
                        )
                    }
                },
            )
        },
    ) { insets ->
        Column(
            verticalArrangement = Arrangement.spacedBy(StoryArcSpace.sm),
            horizontalAlignment = Alignment.CenterHorizontally,
            modifier = Modifier
                .fillMaxSize()
                .padding(insets)
                .padding(StoryArcSpace.gutter),
        ) {
            Text(
                text = stringResource(R.string.source_unauthorized_title),
                style = MaterialTheme.typography.titleMedium,
                color = palette.textPrimary,
            )
            Text(
                text = stringResource(
                    if (isRefused) {
                        R.string.source_unauthorized_refused_body
                    } else {
                        R.string.source_unauthorized_body
                    },
                    name,
                ),
                style = MaterialTheme.typography.bodyMedium,
                color = palette.textSecondary,
            )
        }
    }
}
