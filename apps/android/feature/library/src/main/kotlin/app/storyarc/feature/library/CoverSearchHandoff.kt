package app.storyarc.feature.library

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.CoverWebSearch

/**
 * The Custom Tab a reader is handed to, built as an intent and nothing more.
 *
 * **A Custom Tab, never a `WebView`.** `design.md` records the reason at length and it is
 * two reasons:
 *
 * - App Store Review Guideline 5.2.3, which Google's terms echo, bans saving media from a
 *   third-party source without that source's authorization. A web view this app owns,
 *   capturing an image by screenshot or by reading an element's `src`, is StoryArc
 *   performing that save. The browser performing it is the reader using their browser.
 * - StoryArc's only web view today, the EPUB reader, denies all network egress through
 *   `PublicationEgress`. A second web view that exists to load a search engine would be the
 *   opposite rule on the same app, and two rules about one primitive is how a security
 *   property quietly stops being true.
 *
 * **Built by hand rather than with `androidx.browser`.** The session extra below *is* the
 * Custom Tabs protocol -- a supporting browser reads it and renders a tab rather than a
 * window -- and the library adds a dependency for a builder this screen does not need. The
 * intent carries no callback and no result, so there is no channel a page or a picture could
 * come back through. The only route in is the system picker.
 */
internal object CoverSearchHandoff {
    /**
     * The extra that makes a supporting browser render a Custom Tab.
     *
     * The protocol's own name, which `androidx.browser` sends under the same key. A browser
     * that does not support Custom Tabs ignores it and opens an ordinary tab, which is the
     * same hand-off with a different chrome.
     */
    internal const val SESSION_EXTRA = "android.support.customtabs.extra.SESSION"

    /**
     * What to start for this publication, or null when there is no title to search for.
     *
     * `ACTION_VIEW` and nothing else. Deliberately not `startActivityForResult`: a result is
     * a channel back from the browser, and this feature must have none.
     */
    fun intent(title: String, author: String? = null): Intent? {
        val address = CoverWebSearch.url(title, author) ?: return null
        return Intent(Intent.ACTION_VIEW, Uri.parse(address)).apply {
            putExtra(SESSION_EXTRA, null as Bundle?)
        }
    }
}

/**
 * The row that offers the hand-off, and the sentence that says what it does.
 *
 * `open` is supplied by the screen, because a composable does not hold an `Activity`.
 */
@Composable
internal fun CoverSearchHandoffRow(
    title: String,
    open: (Intent) -> Unit,
    modifier: Modifier = Modifier,
    author: String? = null,
    /**
     * The page's own accent, where the row sits inside the hero's wash. See
     * [CoverChoiceControls]: the theme's own colours can be the wash's colour on itself.
     */
    accent: Color? = null,
) {
    val palette = LocalStoryArcPalette.current
    val intent = CoverSearchHandoff.intent(title, author)
    Column(
        modifier = modifier,
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(StoryArcSpace.hair),
    ) {
        TextButton(
            onClick = { intent?.let(open) },
            enabled = intent != null,
            colors = ButtonDefaults.textButtonColors(
                contentColor = accent ?: MaterialTheme.colorScheme.primary,
            ),
        ) {
            Text(stringResource(R.string.covers_web_search))
        }
        Text(
            text = stringResource(R.string.covers_web_note),
            style = MaterialTheme.typography.labelLarge,
            color = accent ?: palette.textSecondary,
            textAlign = TextAlign.Center,
        )
    }
}
