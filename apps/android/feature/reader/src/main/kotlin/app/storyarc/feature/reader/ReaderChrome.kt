package app.storyarc.feature.reader

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material3.FloatingToolbarDefaults
import androidx.compose.material3.HorizontalFloatingToolbar
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcSpace

/*
 * The reader's controls: a way out, a way in, and nothing else.
 *
 * `comic-reader`, *Revealing controls*: "exactly two controls fade in over the page — one
 * that closes the publication and one that opens the reader's menu … no title, page number,
 * percentage or slider is drawn over the page, because each of those is a fact the menu
 * states better and none of them is an action."
 *
 * **What used to be here.** A close button at the top left, a thumbnail toggle at the top
 * centre, a five-control tool cluster at the top right, and a bottom band holding the layout
 * cluster, the chapter row, a page counter, a slider, a return control and a skipped-page
 * notice. About eleven controls across three surfaces, taking roughly a fifth of a phone
 * screen. They are all still reachable, one tap away, in `ReaderMenuSheet.kt` — labelled in
 * words rather than left to be recognised from an icon.
 *
 * **One capsule, not two pills.** Material sanctions exactly one floating bottom capsule —
 * the Expressive floating toolbar — for "contextual actions relevant to the body content",
 * and two controls are what fits that description now. `HorizontalFloatingToolbar` is what
 * the tool cluster already used, so the container, its shape, elevation, insets and motion
 * are Material's rather than hand-built. The rule it must not break — that a toolbar and a
 * navigation bar "should not be shown at the same time" — holds, because the reader covers
 * the shell.
 *
 * The colours are named rather than left to `standardFloatingToolbarColors()`: this bar
 * floats over artwork that can be white and its icons are white, so it carries the scrim the
 * hand-rolled pills used to. Losing it would be a contrast regression, not a restyle.
 *
 * `ReaderChromeTest` counts the buttons in this file. Two. Adding a third here is the
 * regression the count exists to stop, and the menu is where the third one goes.
 */

/** The scrim and white the chrome has always used, on Material's container. */
@Composable
private fun readerToolbarColours() = FloatingToolbarDefaults.standardFloatingToolbarColors(
    toolbarContainerColor = LocalStoryArcPalette.current.scrim.copy(alpha = 0.6f),
    toolbarContentColor = Color.White,
)

/**
 * The controls. One tap away, and gone while reading.
 *
 * Inside the system bars: the reader draws edge to edge so the page fills the screen, and
 * without this the row sat under the status bar's own gesture strip — the system took the
 * touch and the buttons were all but unreachable. Measured on an emulator, where only the
 * lowest sliver of each button worked.
 */
@Composable
internal fun ReaderChrome(
    onClose: () -> Unit,
    onOpenMenu: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Box(modifier.fillMaxSize().safeDrawingPadding()) {
        HorizontalFloatingToolbar(
            expanded = true,
            colors = readerToolbarColours(),
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .padding(StoryArcSpace.md),
        ) {
            IconButton(onClick = onClose) {
                Icon(
                    imageVector = Icons.Filled.Close,
                    contentDescription = stringResource(R.string.reader_close),
                )
            }
            IconButton(onClick = onOpenMenu) {
                Icon(
                    imageVector = Icons.Filled.MoreHoriz,
                    contentDescription = stringResource(R.string.reader_menu),
                )
            }
        }
    }
}
