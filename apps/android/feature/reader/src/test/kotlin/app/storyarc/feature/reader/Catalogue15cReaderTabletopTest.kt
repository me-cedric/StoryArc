package app.storyarc.feature.reader

import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.performScrollTo
import app.storyarc.core.designsystem.navigation.LocalPostureOverride
import app.storyarc.core.snapshots.Look
import app.storyarc.core.snapshots.catalogue
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * Catalogue entry 15c: the comic reader on a Pixel Fold half open on a table (D3, 2.2). The page
 * is on the upright half and the controls on the flat half, with the posture faked through
 * `LocalPostureOverride`.
 *
 * At xhdpi one dp is two pixels, so the fold, half way down the 841 dp display, is at 841 px.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34], qualifiers = FoldFixtures.TABLETOP_QUALIFIERS)
class Catalogue15cReaderTabletopTest {

    @get:Rule
    val compose = createComposeRule()

    @get:Rule
    val folder = TemporaryFolder()

    private val fold = Rect(0f, 841f, 1402f, 841f)

    private fun draw(look: Look) {
        val model = FoldFixtures.model(folder.root)
        compose.catalogue(
            "15c-reader-tabletop",
            look,
            act = {
                loaded(model)
                // The controls do not hide while the posture lasts.
                mainClock.advanceTimeBy(10_000)
                val page = bounds("Page 1 of 3")
                val close = bounds("Close")
                assertTrue("The page ends at ${page.bottom}, below the fold.", page.bottom <= fold.top)
                assertTrue("Close starts at ${close.top}, above the fold.", close.top >= fold.bottom)
                assertTrue("The menu control hid after the auto-hide.", shows("Menu"))
                val pane = panes().single()
                assertEquals("Controls below", pane.config[SemanticsProperties.PaneTitle])
                assertTrue("The controls are not below the page.", pane.boundsInRoot.top >= page.bottom)
            },
        ) { Reader(model) }
    }

    @androidx.compose.runtime.Composable
    private fun Reader(model: ReaderViewModel) {
        CompositionLocalProvider(LocalPostureOverride provides FoldFixtures.halfOpen(fold, isVertical = false)) {
            ReaderScreen(viewModel = model, onClose = {})
        }
    }

    @Test
    fun light() = draw(Look.Light)

    @Test
    fun dark() = draw(Look.Dark)

    /** At the largest text size the control half scrolls, so the capsule is still reachable. No image. */
    @Test
    @Config(fontScale = 2f)
    fun `at the largest text size the controls scroll`() {
        val model = FoldFixtures.model(folder.root)
        compose.setContent { Reader(model) }
        compose.loaded(model)

        val pane = compose.panes().single()
        assertTrue("The control half does not scroll.", SemanticsProperties.VerticalScrollAxisRange in pane.config)
        compose.onNodeWithContentDescription("Menu").performScrollTo().assertIsDisplayed()
    }
}
