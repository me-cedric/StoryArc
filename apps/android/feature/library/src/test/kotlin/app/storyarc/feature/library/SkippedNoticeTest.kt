package app.storyarc.feature.library

import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertHasClickAction
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.unit.Density
import app.storyarc.core.designsystem.theme.StoryArcTheme
import app.storyarc.feature.library.SkippedPublications.Entry
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * The notice a reader actually sees, including the one claim only a clock can settle.
 *
 * **A test that only checked the notice appears would pass against the count it replaced**,
 * which is why the survival assertion is here rather than left to a screenshot.
 * `library-browsing`: the notice "stays until the reader dismisses it or resolves it", and
 * the toast on the other platform lived six seconds. Compose's test clock can be advanced,
 * so this moves it past seven and looks again — iOS has no equivalent in a host suite and
 * asserts the absence of a timer structurally instead, in `SkippedNoticeTimerTests`.
 *
 * The banner and the list are composed directly rather than through [SkippedNotice], because
 * that composable opens a `ModalBottomSheet` and a modal sheet is a dialog window a unit test
 * cannot compose — the same split `WhatsNewSheet` and `WhatsNewLayoutTest` use.
 *
 * iOS asserts the states in `SkippedPublicationsTests` and the timer's absence separately.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
// Robolectric ships an image per API level and has none for 37, so it cannot be handed the
// module's target. 34 is inside its range and above the minimum this app supports.
@Config(sdk = [34], qualifiers = "w360dp-h1200dp")
class SkippedNoticeTest {

    @get:Rule
    val compose = createComposeRule()

    private val sevenZip = Entry("refused.cb7", "CB7 is not a format StoryArc reads")
    private val protected = Entry("password-protected.cbz", "the archive is password protected")

    private val named = "“refused.cb7” couldn’t be opened"

    private fun banner(reason: String?, onDismiss: () -> Unit = {}) {
        compose.setContent {
            CompositionLocalProvider(LocalDensity provides Density(density = 2f, fontScale = 1f)) {
                StoryArcTheme {
                    SkippedBanner(
                        sentence = named,
                        reason = reason,
                        onOpenList = {},
                        onDismiss = onDismiss,
                    )
                }
            }
        }
    }

    @Test
    fun `the notice outlives the six seconds the toast had`() {
        // The clock is paused, so nothing advances unless this test says so — which is the
        // whole point: a notice that survives seven seconds of *real* waiting proves nothing
        // about a countdown a recomposition happened to cancel.
        compose.mainClock.autoAdvance = false
        banner(reason = sevenZip.reason)

        compose.onNodeWithText(named, substring = true).assertIsDisplayed()

        // Past the six-second dwell, with a second to spare.
        compose.mainClock.advanceTimeBy(7_000)

        compose.onNodeWithText(named, substring = true).assertIsDisplayed()
        compose.onNodeWithText(sevenZip.reason, substring = true).assertIsDisplayed()
    }

    @Test
    fun `one failure names its publication and states the reason`() {
        banner(reason = sevenZip.reason)

        // The reason is `publication-formats`', verbatim. A count says none of this.
        compose.onNodeWithText(sevenZip.reason, substring = true).assertIsDisplayed()
        compose.onNodeWithText(named, substring = true).assertIsDisplayed()
    }

    @Test
    fun `the notice is one stop for a screen reader, and the way to the list is a named control`() {
        banner(reason = sevenZip.reason)

        // One node carrying both halves, so a screen reader stops once and hears the whole
        // fact rather than swiping twice for two thirds of it. `library-browsing`: "it is
        // announced once, naming the publication where there is one".
        compose.onNode(hasText(named, substring = true) and hasText(sevenZip.reason, substring = true))
            .assertIsDisplayed()
        // And exactly one, which is what the merge is for: unmerged there are two.
        compose.onAllNodesWithText(sevenZip.reason, substring = true).assertCountEquals(1)
        // The way to the list is its own control with its own name — not the notice.
        compose.onNodeWithText("What couldn’t be opened").assertIsDisplayed()
    }

    @Test
    fun `several state the count and no reason, because the reasons are in the list`() {
        compose.setContent {
            CompositionLocalProvider(LocalDensity provides Density(density = 2f, fontScale = 1f)) {
                StoryArcTheme {
                    SkippedBanner(
                        sentence = "2 couldn’t be opened",
                        reason = null,
                        onOpenList = {},
                        onDismiss = {},
                    )
                }
            }
        }

        compose.onNodeWithText("2 couldn’t be opened", substring = true).assertIsDisplayed()
        // Not one reason standing in for two, which is what a merged sentence would be.
        compose.onAllNodesWithText(sevenZip.reason, substring = true).assertCountEquals(0)
        compose.onNodeWithText("What couldn’t be opened").assertIsDisplayed()
    }

    @Test
    fun `dismissal is the reader's own act`() {
        var dismissed = false
        banner(reason = sevenZip.reason, onDismiss = { dismissed = true })

        // It is a control, not a sentence a reader has to guess is tappable.
        compose.onNodeWithText("Dismiss").assertHasClickAction()
        // The semantics action rather than `performClick`: a synthesised touch on a Material
        // button does not reach its `clickable` under Robolectric's own view host, and the
        // question here is whether the control is wired to the reader's intent, not whether
        // Robolectric dispatches motion events. `assertHasClickAction` above is what makes
        // this a control and not a bare call of the lambda.
        compose.onNodeWithText("Dismiss").performSemanticsAction(SemanticsActions.OnClick)
        compose.waitForIdle()

        assertTrue("the dismissal has to be the reader's", dismissed)
    }

    @Test
    fun `the list keeps every reason apart`() {
        compose.setContent {
            CompositionLocalProvider(LocalDensity provides Density(density = 2f, fontScale = 1f)) {
                StoryArcTheme { SkippedList(entries = listOf(sevenZip, protected)) }
            }
        }

        // "the reasons are not merged: two files that failed differently say different
        // things". Two rows, each one stop, each carrying its own name and its own sentence.
        compose.onNode(
            hasText(sevenZip.name, substring = true) and hasText(sevenZip.reason, substring = true),
        ).assertIsDisplayed()
        compose.onNode(
            hasText(protected.name, substring = true) and
                hasText(protected.reason, substring = true),
        ).assertIsDisplayed()
    }
}
