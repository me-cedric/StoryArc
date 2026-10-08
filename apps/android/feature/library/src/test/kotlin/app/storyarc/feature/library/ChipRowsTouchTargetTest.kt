package app.storyarc.feature.library

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import app.storyarc.core.designsystem.theme.StoryArcTheme
import app.storyarc.core.model.LibrarySort
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * Task 24.4 and 24.5 of `close-the-audited-gaps`: the chip rows of the library are touch targets
 * of 48 dp, 8 dp apart, along a row and between rows.
 *
 * A filter chip draws 32 dp high, and the accessibility tree reports what is laid out. The
 * rows here are the ones that wrap at the largest text size, so the gap between rows matters
 * as much as the one along them. Each row is composed through the same function the screen
 * calls, so a chip that loses its minimum height, or a row that loses its vertical gap, fails
 * here. The narrow window is the narrowest Android's compact class allows.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34], qualifiers = "w320dp-h2400dp")
class ChipRowsTouchTargetTest {

    @get:Rule
    val compose = createComposeRule()

    @Composable
    private fun Narrow(fontScale: Float, content: @Composable () -> Unit) {
        CompositionLocalProvider(LocalDensity provides Density(density = 1f, fontScale = fontScale)) {
            StoryArcTheme { Column(Modifier.width(280.dp)) { content() } }
        }
    }

    private fun orderChips(fontScale: Float) {
        compose.setContent {
            Narrow(fontScale) {
                ListOrderChips(
                    order = ListOrder(sort = LibrarySort.FILE_SIZE),
                    onSortChange = {},
                    onDirectionChange = {},
                    onCurated = {},
                )
            }
        }
        compose.waitForIdle()
    }

    private fun scopeChips(fontScale: Float) {
        compose.setContent {
            Narrow(fontScale) { ScopeChips(LibraryAvailability.EVERYTHING, onScopeChange = {}) }
        }
        compose.waitForIdle()
    }

    @Test
    fun `the list order chips are 48 dp targets`() {
        orderChips(fontScale = 1f)

        compose.onAllNodes(hasClickAction()).assertAllTouchTargetsAreAtLeast()
    }

    @Test
    fun `the list order chips are 8 dp apart at the largest text size`() {
        orderChips(fontScale = 2f)

        compose.onAllNodes(hasClickAction()).assertAllTouchTargetsAreAtLeast()
        compose.onAllNodes(hasClickAction()).assertTouchTargetsAreApart()
    }

    @Test
    fun `the search scope chips are 48 dp targets`() {
        scopeChips(fontScale = 1f)

        compose.onAllNodes(hasClickAction()).assertAllTouchTargetsAreAtLeast()
    }

    @Test
    fun `the search scope chips are 8 dp apart at the largest text size`() {
        scopeChips(fontScale = 2f)

        compose.onAllNodes(hasClickAction()).assertAllTouchTargetsAreAtLeast()
        compose.onAllNodes(hasClickAction()).assertTouchTargetsAreApart()
    }
}
