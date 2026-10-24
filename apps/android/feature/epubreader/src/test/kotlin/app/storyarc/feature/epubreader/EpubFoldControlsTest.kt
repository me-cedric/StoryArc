package app.storyarc.feature.epubreader

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.material3.adaptive.HingeInfo
import androidx.compose.material3.adaptive.Posture
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsNode
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import app.storyarc.core.designsystem.navigation.LocalPostureOverride
import app.storyarc.core.designsystem.navigation.windowHinge
import app.storyarc.core.playback.SpokenAudio
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * `native-experience`, *The camera and the fold are not content* (1.4): no control of the EPUB
 * reader, and no row of its menu sheet, is under a vertical fold that separates or occludes.
 *
 * The fold has a width and is not centred, so controls centred on the window fail this.
 *
 * **Proved able to fail**, per AGENTS.md section 5: drawing the chrome with no hinge and the menu
 * sheet without `sheetOffFold()` failed both tests by name. Reverted.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], qualifiers = "w1200dp-h800dp-mdpi")
class EpubFoldControlsTest {

    @get:Rule
    val compose = createComposeRule()

    private val fold = Rect(560f, 0f, 600f, 800f)
    private val posture = Posture(hingeList = listOf(HingeInfo(fold, isFlat = true, isVertical = true, isSeparating = false, isOccluding = true)))

    private fun SemanticsNode.walk(): Sequence<SemanticsNode> = sequenceOf(this) + children.asSequence().flatMap { it.walk() }

    private fun assertOffTheFold(nodes: Sequence<SemanticsNode>) {
        val controls = nodes.filter { SemanticsActions.OnClick in it.config }.toList()
        assertTrue("No control was drawn.", controls.isNotEmpty())
        for (control in controls) {
            val area = control.boundsInWindow
            assertFalse("A control is under the fold: $area.", area.right > fold.left && area.left < fold.right)
        }
    }

    @Test
    fun `the chrome and the overlays keep off the fold`() {
        compose.setContent {
            CompositionLocalProvider(LocalDensity provides Density(1f)) {
                Box(Modifier.size(1200.dp, 800.dp)) {
                    EpubChrome(failure = null, isVisible = true, onClose = {}, onOpenMenu = {}, hinge = posture.windowHinge)
                    EpubReaderOverlays(
                        canReturn = true,
                        onReturn = {},
                        isReadingAloud = true,
                        isSpeaking = true,
                        onToggleReadAloud = {},
                        onSkipSentence = {},
                        onStopReadAloud = {},
                        hinge = posture.windowHinge,
                        spokenAudio = SpokenAudio(),
                    )
                }
            }
        }

        assertOffTheFold(compose.onRoot(useUnmergedTree = true).fetchSemanticsNode().walk())
    }

    @Test
    fun `the menu sheet keeps off the fold`() {
        compose.setContent {
            CompositionLocalProvider(LocalPostureOverride provides posture) {
                EpubMenuSheet(
                    facts = EpubMenuFacts(
                        chapter = "Chapter Two",
                        progression = 0.4,
                        withinChapter = 0.5,
                        isPageBookmarked = false,
                        isContentsReady = true,
                        canReadAloud = true,
                        isReadingAloud = false,
                    ),
                    actions = EpubMenuActions({}, {}, {}, {}, {}, {}),
                )
            }
        }
        compose.waitUntil(timeoutMillis = 5_000) { compose.onAllNodesWithText("Chapter Two", substring = true, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty() }

        // The sheet is the pane in a window of its own. The scrim around it is the way out, not a control.
        val sheet = compose.onAllNodesWithText("Chapter Two", substring = true, useUnmergedTree = true).fetchSemanticsNodes().first()
            .let { node -> generateSequence(node) { it.parent }.first { SemanticsProperties.PaneTitle in it.config } }
        assertTrue("The sheet is not on the wider side: ${sheet.boundsInWindow}.", sheet.boundsInWindow.left >= fold.right)
        assertOffTheFold(sheet.walk())
    }
}
