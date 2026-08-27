package app.storyarc.feature.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcSpace

/**
 * About: who made this, that it costs nothing, and what it is built on.
 *
 * `settings-and-about` is unusually specific here, and two of its clauses are about
 * restraint rather than content. The support link "is never presented as a prompt, an
 * interstitial, or a nag — it appears only on this screen". And the problem report
 * carries "the app version, platform version, and device class pre-filled, and no
 * personal data" — which is why it composes a URL from three known values rather than
 * collecting anything.
 */
@Composable
internal fun AboutGroup(modifier: Modifier = Modifier) {
    val palette = LocalStoryArcPalette.current
    val context = LocalContext.current
    var showing by remember { mutableStateOf<Notice?>(null) }
    val notices = remember { Notices.forAndroid(context.assets) }

    showing?.let { notice ->
        LicenceText(
            notice = notice,
            text = remember(notice) { Notices.text(context.assets, notice) },
            onBack = { showing = null },
            modifier = modifier,
        )
        return
    }

    // No scroll of its own. `SettingsScreen` already scrolls every group, and a second
    // vertical scroll inside the first is measured with an infinite height — which threw
    // and took the whole app down every time anyone opened About.
    Column(
        modifier = modifier,
        verticalArrangement = Arrangement.spacedBy(StoryArcSpace.md),
    ) {
        Text(
            text = stringResource(R.string.about_version, BuildInfo.version, BuildInfo.build),
            style = MaterialTheme.typography.bodyMedium,
            color = palette.textPrimary,
        )
        Text(
            text = stringResource(R.string.about_author),
            style = MaterialTheme.typography.bodyMedium,
            color = palette.textPrimary,
        )
        // Stated plainly, because the spec asks for it plainly: free, open source, no
        // paid tier, no advertising.
        Text(
            text = stringResource(R.string.about_free),
            style = MaterialTheme.typography.bodyMedium,
            color = palette.textSecondary,
        )

        Column {
            LinkRow(R.string.about_repository, "https://github.com/me-cedric/StoryArc")
            LinkRow(R.string.about_author_link, "https://github.com/me-cedric")
            LinkRow(R.string.about_licence, "https://github.com/me-cedric/StoryArc/blob/main/LICENSE")
            // The one support link, on the one screen. Never a prompt.
            LinkRow(R.string.about_support, "https://ko-fi.com/mecedric")
            LinkRow(R.string.about_report, BuildInfo.issueUrl())
        }

        Text(
            text = stringResource(R.string.about_acknowledgements),
            style = MaterialTheme.typography.titleMedium,
            color = palette.textPrimary,
            modifier = Modifier.padding(top = StoryArcSpace.md),
        )
        Text(
            text = stringResource(R.string.about_acknowledgements_note),
            style = MaterialTheme.typography.labelLarge,
            color = palette.textTertiary,
        )

        notices.forEach { notice ->
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickableRow { showing = notice }
                    .padding(vertical = StoryArcSpace.xs),
            ) {
                Text(
                    text = notice.version?.let { "${notice.name} $it" } ?: notice.name,
                    style = MaterialTheme.typography.bodyMedium,
                    color = palette.textPrimary,
                )
                Text(
                    text = "${notice.licence} · ${notice.why}",
                    style = MaterialTheme.typography.labelLarge,
                    color = palette.textTertiary,
                )
            }
        }
    }
}

/** One licence, in full, because a summary of a licence is not a licence. */
@Composable
private fun LicenceText(
    notice: Notice,
    text: String?,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val palette = LocalStoryArcPalette.current

    // Also no scroll of its own, for the same reason. A licence body is long and the
    // host's scroll is what carries it.
    Column(
        modifier = modifier,
        verticalArrangement = Arrangement.spacedBy(StoryArcSpace.sm),
    ) {
        OutlinedButton(onClick = onBack) { Text(stringResource(R.string.settings_back)) }
        Text(
            text = notice.name,
            style = MaterialTheme.typography.titleMedium,
            color = palette.textPrimary,
        )
        Text(
            text = text ?: stringResource(R.string.about_licence_missing, notice.licence),
            // Monospaced, because a licence is a document and its own line breaks are
            // part of it.
            style = MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace),
            color = palette.textSecondary,
        )
    }
}

@Composable
private fun LinkRow(labelRes: Int, url: String) {
    val context = LocalContext.current
    TextButton(onClick = { BuildInfo.open(context, url) }) {
        Text(stringResource(labelRes))
    }
}
