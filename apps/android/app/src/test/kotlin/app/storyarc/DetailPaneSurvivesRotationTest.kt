package app.storyarc

import androidx.compose.foundation.layout.Row
import androidx.compose.material3.Button
import androidx.compose.material3.Text
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Task 21.1, item 2 — a rotated publication page went back to the top.
 *
 * `AppContent` reached a publication page from the single column and from the detail pane of
 * `StoryArcListDetailPanes` the same way it once reached the shelf: two call sites, each with
 * its own `SaveableStateProvider(navigation.stateKey) { HostedScreen(...) }`. A rotation that
 * crossed 840 dp moved the branch; the *new* call restored whatever the *old* call had last
 * saved, not the scroll position at the moment of rotation, because the old call had not yet
 * saved that position when the new one composed. On the device this measured as `Read` moving
 * from y=1398 to y=1626 after portrait, landscape, portrait.
 *
 * The fix is the one-argument [rememberMovablePane] added beside the zero-argument one: a
 * single continuation, parameterised on the page and on whether it sits beside the shelf,
 * called from both branches instead of rebuilt by either. This asserts two things a mechanism
 * built the way the shelf's was could still get wrong for a *parameterised* continuation:
 * that moving it between branches does not reset it (as `RotationKeepsThePaneTest` already
 * asserts for the shelf), and that a value read through [rememberUpdatedState] inside it is
 * the current one and not whatever was in scope the one time `remember` ran.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class DetailPaneSurvivesRotationTest {

    @get:Rule
    val compose = createComposeRule()

    @Test
    fun `the page survives the branch its caller draws it from, and reads live state`() {
        var entries = 0
        val twoPane = mutableStateOf(false)
        // Stands in for `settings` (or `navigation`): a value `AppContent` reads fresh on
        // every recomposition, which only `rememberUpdatedState` keeps current inside a
        // continuation `remember` creates once.
        val label = mutableStateOf("first")

        compose.setContent {
            val currentLabel = rememberUpdatedState(label.value)
            val pane = rememberMovablePane<Int> { position ->
                DisposableEffect(Unit) {
                    entries++
                    onDispose {}
                }
                var scrubbed by remember { mutableIntStateOf(0) }
                Text("page $position at $scrubbed, label ${currentLabel.value}")
                Button(onClick = { scrubbed++ }) { Text("scroll") }
            }
            if (!twoPane.value) {
                pane(1)
            } else {
                // `StoryArcListDetailPanes`' detail pane, standing in for a different
                // parent in the tree — the branch shape that once forced a rebuild.
                Row { pane(1) }
            }
        }

        compose.onNodeWithText("scroll").performClick()
        compose.onNodeWithText("scroll").performClick()
        compose.onNodeWithText("page 1 at 2, label first").assertIsDisplayed()
        assertEquals("the page composed more than once before any rotation", 1, entries)

        // Rotate past 840 dp: the branch changes shape, and the live value changes too —
        // the way `settings` can between one recomposition and the next.
        twoPane.value = true
        label.value = "second"
        compose.waitForIdle()

        compose.onNodeWithText("page 1 at 2, label second").assertIsDisplayed()
        assertEquals(
            "rotating rebuilt the page instead of moving it — the scroll-position regression " +
                "task 21.1 item 2 fixes",
            1,
            entries,
        )

        // And rotate back.
        twoPane.value = false
        compose.waitForIdle()
        compose.onNodeWithText("page 1 at 2, label second").assertIsDisplayed()
        assertEquals(1, entries)
    }
}
