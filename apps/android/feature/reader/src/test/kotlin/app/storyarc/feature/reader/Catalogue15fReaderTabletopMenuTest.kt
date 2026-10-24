package app.storyarc.feature.reader

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.performClick
import app.storyarc.core.designsystem.navigation.LocalPostureOverride
import app.storyarc.core.designsystem.theme.StoryArcTheme
import app.storyarc.core.snapshots.Look
import com.github.takahirom.roborazzi.ExperimentalRoborazziApi
import com.github.takahirom.roborazzi.captureScreenRoboImage
import com.github.takahirom.roborazzi.roborazziSystemPropertyOutputDirectory
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * Catalogue entry 15f: the reader's menu open in tabletop posture (D3, 2.2). The sheet rises no
 * higher than the fold, so the page on the upright half stays in view.
 *
 * The sheet is a window of its own, so this photographs the screen rather than one root, and the
 * catalogue's audit, which reads one root, does not run here. `sheetOffFold()` is the same for
 * every reader sheet; `WindowPostureTest` holds its arithmetic.
 */
@OptIn(ExperimentalRoborazziApi::class)
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34], qualifiers = FoldFixtures.TABLETOP_QUALIFIERS)
class Catalogue15fReaderTabletopMenuTest {

    @get:Rule
    val compose = createComposeRule()

    @get:Rule
    val folder = TemporaryFolder()

    private val fold = Rect(0f, 841f, 1402f, 841f)

    private fun draw(look: Look) {
        val model = FoldFixtures.model(folder.root)
        compose.setContent {
            StoryArcTheme(appearance = look.appearance, useDynamicColor = false, natural = false) {
                Box(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background)) {
                    CompositionLocalProvider(LocalPostureOverride provides FoldFixtures.halfOpen(fold, isVertical = false)) {
                        ReaderScreen(viewModel = model, onClose = {})
                    }
                }
            }
        }
        compose.loaded(model)
        compose.onNodeWithContentDescription("Menu").performClick()
        compose.waitUntil(timeoutMillis = 5_000) { compose.onAllNodesWithText("Contents").fetchSemanticsNodes().isNotEmpty() }
        compose.waitForIdle()

        val sheet = compose.onAllNodesWithText("Contents").fetchSemanticsNodes().first()
            .let { node -> generateSequence(node) { it.parent }.first { SemanticsProperties.PaneTitle in it.config } }
        assertTrue("The sheet starts at ${sheet.boundsInWindow.top}, above the fold.", sheet.boundsInWindow.top >= fold.bottom)
        captureScreenRoboImage("${roborazziSystemPropertyOutputDirectory()}/15f-reader-tabletop-menu-${look.suffix}.png")
    }

    @Test
    fun light() = draw(Look.Light)

    @Test
    fun dark() = draw(Look.Dark)
}
