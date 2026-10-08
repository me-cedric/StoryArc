package app.storyarc.feature.reader

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.width
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.unit.dp
import app.storyarc.core.designsystem.theme.StoryArcTheme
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * Task 24.4 and 24.5 of `close-the-audited-gaps`: a matte swatch in the reader's adjustments
 * sheet is a touch target of 48 dp, and two swatches are 8 dp apart, along a row and between
 * rows.
 *
 * The swatches were 44 dp targets with 4 dp between rows. The grid is composed in a column 280
 * dp wide, which is what a 320 dp phone leaves after the sheet's padding, so it wraps.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34], qualifiers = "w320dp-h2400dp")
class MatteSwatchTouchTargetTest {

    @get:Rule
    val compose = createComposeRule()

    @Test
    fun `every matte swatch is a 48 dp target, 8 dp from the next`() {
        compose.setContent {
            StoryArcTheme {
                Column(Modifier.width(280.dp)) {
                    MatteSwatches(current = null, onChoose = {})
                }
            }
        }
        compose.waitForIdle()

        compose.onAllNodes(hasClickAction()).assertAllTouchTargetsAreAtLeast()
        compose.onAllNodes(hasClickAction()).assertTouchTargetsAreApart()
    }
}
