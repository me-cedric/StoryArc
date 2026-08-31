package app.storyarc.feature.settings

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.getUnclippedBoundsInRoot
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import app.storyarc.core.designsystem.theme.StoryArcTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * What's new survives the largest text size, in the smallest window this app supports.
 *
 * `settings-and-about`: "every entry's heading and sentence are readable in full, the screen
 * scrolls if it must, and the dismissing action stays reachable without scrolling past the
 * content". Three claims, and every one of them is a layout claim — none can be answered by
 * asserting that a composable was called.
 *
 * Two of Material's own rules are what the sheet is built to satisfy, and they pull against
 * each other: support 200% text, and **do not resize a component that contains no text**. An
 * icon obeys the second, so the column it sits in is a fixed number of dp; the sentence
 * beside it obeys the first and grows. Get that wrong and the row still lays out — it just
 * gives the sentence a third of the line and turns it into a column of syllables, which is
 * exactly the failure `DownloadLimitWrapTest` was written for one row over.
 *
 * Robolectric, `GraphicsMode.NATIVE` and a `LocalDensity` override, all three for the reasons
 * `DownloadLimitWrapTest` sets out at length: a layout claim is only answerable inside a
 * composition, legacy graphics measure every glyph at about a pixel wide and would pass this
 * against a sheet that clips, and the text size is a setting a reader chooses rather than
 * scaffolding.
 *
 * The **content** is composed rather than [WhatsNewSheet], for the same reason that test
 * composes a group rather than a screen: `ModalBottomSheet` is a dialog window, and what
 * carries every claim above is what it holds.
 */
@RunWith(RobolectricTestRunner::class)
// Robolectric ships no image for API 37, and nothing here has an API level in it.
@Config(sdk = [34], qualifiers = "w320dp-h640dp")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class WhatsNewLayoutTest {

    @get:Rule
    val compose = createComposeRule()

    private val release = WhatsNew.releases.first()

    // Every finder below reads the **unmerged** tree, and that is load-bearing rather than
    // habitual. A `ListItem` merges its children's semantics, so the merged node carrying a
    // heading's text is the whole row: it starts at 0 and spans the window whatever the icon
    // column does, and this suite passed against a deliberately broken sheet until the
    // mutation check said so.

    /** Every string the assertions look for, resolved inside the composition that draws it. */
    private var labels = emptyList<String>()
    private var dismiss = ""

    /**
     * The text size, as state rather than an argument.
     *
     * `setContent` may be called once per rule, and one of the tests below has to measure the
     * same sheet at two sizes — so the size is something the composition reads and reacts to,
     * which is also how a reader changes it: by moving a slider while the app is running.
     */
    private val fontScale = mutableFloatStateOf(1f)
    private var composed = false

    private fun show(fontScale: Float) {
        this.fontScale.floatValue = fontScale
        if (!composed) {
            composed = true
            compose.setContent { sheet() }
        }
        compose.waitForIdle()
        assertTrue("labels were $labels", labels.none { it.isBlank() })
        assertEquals("labels were $labels", labels.size, labels.toSet().size)
    }

    @Composable
    private fun sheet() {
        labels = release.notes.flatMap { listOf(stringResource(it.title), stringResource(it.body)) }
        dismiss = stringResource(R.string.whats_new_continue)
        CompositionLocalProvider(
            LocalDensity provides Density(density = 1f, fontScale = fontScale.floatValue),
        ) {
            StoryArcTheme {
                // The sheet is bounded by the window it is drawn in, and that bound is what
                // makes the action pinnable at all. A `Box` of the window's size is the same
                // bound without the dialog.
                Box(modifier = Modifier.size(WINDOW, WINDOW_HEIGHT)) {
                    WhatsNewContent(release = release, onDismiss = {})
                }
            }
        }
    }

    /**
     * The dismissing action is on screen at 200% text, without scrolling to it.
     *
     * A column that simply grew would push the button off the bottom of the sheet, and a
     * button off the bottom of a modal is one a reader cannot reach at all — the sheet is
     * over everything else, so there is nowhere to scroll to.
     */
    @Test
    fun `continue stays on screen at the largest text size`() {
        show(fontScale = LARGEST_TEXT)
        val button = compose.onNodeWithText(dismiss, useUnmergedTree = true)
        button.assertIsDisplayed()
        val bounds = button.getUnclippedBoundsInRoot()
        assertTrue(
            "Continue's foot is at ${bounds.bottom}, past the window's $WINDOW_HEIGHT",
            bounds.bottom <= WINDOW_HEIGHT,
        )
        assertTrue("Continue has no height", bounds.bottom - bounds.top > Dp.Hairline)
    }

    /**
     * The icon column is the same width whatever the text size.
     *
     * Material: do not resize components that do not contain text. An icon that scaled with
     * the reader's type would take a third of a 320 dp line at 200%, and the sentence beside
     * it would be measured into what was left.
     *
     * Measured as where the sentence *starts*, which is the icon column plus the gutters and
     * needs nothing added to the sheet for a test to hold on to.
     */
    @Test
    fun `the icon column does not grow with the text size`() {
        show(fontScale = 1f)
        val atDefault = compose.onNodeWithText(labels.first(), useUnmergedTree = true).getUnclippedBoundsInRoot().left
        show(fontScale = LARGEST_TEXT)
        val atLargest = compose.onNodeWithText(labels.first(), useUnmergedTree = true).getUnclippedBoundsInRoot().left
        assertEquals(
            "The text column starts at $atDefault by default and $atLargest at 200%",
            atDefault,
            atLargest,
        )
    }

    /** Every heading and every sentence keeps most of the line to itself. */
    @Test
    fun `every entry keeps most of the line at the largest text size`() {
        show(fontScale = LARGEST_TEXT)
        for (label in labels) {
            val bounds = compose.onNodeWithText(label, useUnmergedTree = true).getUnclippedBoundsInRoot()
            val width = bounds.right - bounds.left
            // The icon column and the two gutters are what a sentence gives up. Anything
            // narrower than half the window has been squeezed rather than laid out.
            assertTrue("\"$label\" was measured $width wide", width > WINDOW / 2)
            assertTrue("\"$label\" ends at ${bounds.right}", bounds.right <= WINDOW)
        }
    }

    private companion object {
        /** The narrowest window Android's compact width class allows, and so the floor. */
        val WINDOW = 320.dp

        /** A short window, because a sheet that fits a tall one proves nothing. */
        val WINDOW_HEIGHT = 640.dp

        /** The largest font scale Android's accessibility settings offer. */
        const val LARGEST_TEXT = 2f
    }
}
