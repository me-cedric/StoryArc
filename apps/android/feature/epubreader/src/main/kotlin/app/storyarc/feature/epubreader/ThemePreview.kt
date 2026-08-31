package app.storyarc.feature.epubreader

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color as AndroidColor
import android.view.ViewGroup
import android.webkit.WebView
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcRadius
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.ReadingTheme
import app.storyarc.core.model.ThemeValues

/**
 * The live preview: a chapter title and body text, drawn by the engine that draws the book.
 *
 * ## What "the real renderer" means here, and what it does not
 *
 * `reading-themes` asks for a preview "rendered by the same engine that renders the
 * publication, so the preview cannot disagree with the result". Readium renders a
 * reflowable EPUB in a `WebView`; this is a `WebView`, given the same axis values through
 * [ThemePreviewDocument], which is asserted against the same [ThemeValues] the Readium
 * mapping reads. Type, spacing, measure, alignment and colour behave here exactly as they
 * behave on the page, because the same layout engine is deciding.
 *
 * **It is not a second Readium navigator over the publication's own resources**, and the
 * spec's own preview content is why it cannot be: the same requirement asks for "a chapter
 * title and at least three lines of body text", which is a *constructed* specimen. A
 * navigator renders the resource at a locator and nothing else, so it can show a page but
 * never that. What is given up by the difference is worth naming:
 *
 *  - **The publisher's stylesheet is absent.** Under any preset but Original that is what
 *    the reader asked for anyway — `publisherStyles` is off and StoryArc's values win. It
 *    is a real gap only under Original, where the preview shows the browser's defaults
 *    rather than the publisher's design.
 *  - **ReadiumCSS itself is absent.** Its own resets and its `--USER__*` plumbing are not
 *    reproduced; the same *numbers* are emitted as plain CSS instead. Where ReadiumCSS does
 *    something StoryArc's values do not describe, the page has it and the preview does not.
 *
 * Task 3.6 in the change's task list records this in the same words. iOS's `ThemePreview`
 * is the same preview with the same caveats.
 */
@Composable
internal fun ThemePreview(
    theme: ReadingTheme,
    values: ThemeValues,
    /** The chapter the reader is in, or null before the book reports one. */
    title: String?,
    /** Words from the open publication, or empty for the sample paragraph. */
    excerpt: String,
    modifier: Modifier = Modifier,
) {
    val palette = LocalStoryArcPalette.current
    val sample = stringResource(R.string.theme_preview_sample)
    val description = stringResource(R.string.theme_preview_description)
    val html = ThemePreviewDocument.html(
        theme = theme,
        values = values,
        title = title,
        body = excerpt.ifBlank { sample },
    )

    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(StoryArcSpace.sm)) {
        Text(
            text = stringResource(R.string.theme_preview),
            style = MaterialTheme.typography.titleMedium,
            color = palette.textPrimary,
        )

        AndroidView(
            factory = ::previewWeb,
            update = { web ->
                web.loadDataWithBaseURL(
                    ThemePreviewDocument.ASSET_BASE,
                    html,
                    "text/html",
                    "utf-8",
                    null,
                )
            },
            modifier = Modifier
                .fillMaxWidth()
                // Tall enough to judge a spacing change, and fixed so it stays that way.
                //
                // `reading-themes` asks the preview to stay "large enough to judge a
                // spacing change" at large text sizes — which on a sheet that grows with
                // the system text size means the preview must *not* grow with it, because
                // every dp the preview takes is a dp the controls below it lose. Six lines
                // at the default step, fewer at 200 %, which is still enough to see two
                // lines' leading.
                .height(200.dp)
                .clip(RoundedCornerShape(StoryArcRadius.lg))
                .border(
                    width = 1.dp,
                    color = palette.borderSubtle,
                    shape = RoundedCornerShape(StoryArcRadius.lg),
                )
                // A picture of the page, not the page. TalkBack reading two paragraphs of
                // sample text between the preset grid and the size stepper would be a
                // detour through content the reader is not here to read; the label says
                // what the thing is instead.
                .clearAndSetSemantics { contentDescription = description },
        )
    }
}

/**
 * The web view itself.
 *
 * Reloaded on every change rather than mutated, which is what makes the preview "reflow
 * continuously during a drag": the sliders are stepped to a tenth of their range, so a drag
 * submits at most ten documents rather than one per frame, and each is a few hundred bytes
 * of HTML with no network and no publication behind it.
 */
// The view is semantics-cleared above and has nothing to activate: it is a picture of a
// page. `ClickableViewAccessibility` exists to catch a touch listener that hides a real
// action from a screen reader, and there is no action here to hide.
@SuppressLint("ClickableViewAccessibility")
private fun previewWeb(context: Context): WebView = WebView(context).apply {
    layoutParams = ViewGroup.LayoutParams(
        ViewGroup.LayoutParams.MATCH_PARENT,
        ViewGroup.LayoutParams.MATCH_PARENT,
    )
    // A specimen, not a place to read: a drag that started on the preview belongs to the
    // sheet underneath it, and there is nothing here to scroll to.
    isVerticalScrollBarEnabled = false
    isHorizontalScrollBarEnabled = false
    setOnTouchListener { _, _ -> true }
    // The page paints its own background from the theme, and a white flash between
    // documents during a drag is the one artefact a live preview cannot have.
    setBackgroundColor(AndroidColor.TRANSPARENT)
    // Nothing in the document runs, and the document is built by ThemePreviewDocument out
    // of text this app escaped itself. JavaScript stays off, which is the default.
    settings.javaScriptEnabled = false
}
