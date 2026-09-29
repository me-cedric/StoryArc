package app.storyarc

import androidx.compose.foundation.layout.Row
import androidx.compose.material3.Button
import androidx.compose.material3.Text
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
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
 * Task 21.1 — rotating the device on the library page froze it.
 *
 * `AppContent` reaches the shelf from two call sites: the single column, and the list pane of
 * `StoryArcListDetailPanes`. Both are now the one call to [rememberMovablePane]'s returned
 * function, so a rotation that crosses 840 dp moves that call between the two shapes instead
 * of tearing the shelf down and composing it again from nothing — which is what a plain
 * `if`/`else` around two separate `Destination(...)` calls did, and which is where the field
 * report's 3305 ms came from.
 *
 * This asserts [rememberMovablePane] itself, called the same way `AppContent` calls it — from
 * an `if`/`else` whose two branches wrap the content differently, which is the one shape a
 * structural-branch rebuild depends on. A production `Destination(LIBRARY)` needs a
 * `LibraryViewModel`, an `AppHost` and the rest of the app graph to compose at all, so this
 * stands in a `Text` and a counter for it; what is asserted is the mechanism `AppContent`
 * relies on, not a re-description of it.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class RotationKeepsThePaneTest {

    @get:Rule
    val compose = createComposeRule()

    @Test
    fun `the pane survives the branch its caller draws it from`() {
        var entries = 0
        val twoPane = mutableStateOf(false)

        compose.setContent {
            val pane = rememberMovablePane {
                DisposableEffect(Unit) {
                    entries++
                    onDispose {}
                }
                var position by remember { mutableIntStateOf(0) }
                Text("shelf at $position")
                Button(onClick = { position++ }) { Text("scroll") }
            }
            if (!twoPane.value) {
                pane()
            } else {
                // The list pane's own wrapper, standing in for `StoryArcListDetailPanes` —
                // a different parent in the tree, which is what a structural branch is.
                Row { pane() }
            }
        }

        compose.onNodeWithText("scroll").performClick()
        compose.onNodeWithText("scroll").performClick()
        compose.onNodeWithText("shelf at 2").assertIsDisplayed()
        assertEquals("the pane composed more than once before any rotation", 1, entries)

        // Rotate past 840 dp: the branch changes shape.
        twoPane.value = true
        compose.waitForIdle()

        compose.onNodeWithText("shelf at 2").assertIsDisplayed()
        assertEquals(
            "rotating rebuilt the shelf instead of moving it — this is the freeze task 21.1 fixes",
            1,
            entries,
        )

        // And rotate back.
        twoPane.value = false
        compose.waitForIdle()
        compose.onNodeWithText("shelf at 2").assertIsDisplayed()
        assertEquals(1, entries)
    }
}
