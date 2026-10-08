package app.storyarc.feature.epubreader

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.width
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.unit.dp
import app.storyarc.core.designsystem.theme.StoryArcTheme
import app.storyarc.core.model.SUGGESTED_BACKGROUNDS
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * Task 24.4 and 24.5 of `close-the-audited-gaps`: a colour swatch is a touch target of 48 dp, and
 * two swatches are 8 dp apart.
 *
 * The page colour swatches were 32 dp targets and the highlight colours of the selection menu
 * were 44 dp. Both draw their coloured dot smaller than the target, and this measures the
 * target. The grid is composed in a column 280 dp wide, which is what a 320 dp phone leaves
 * after the sheet's padding, so it wraps and the gap between rows is measured as well.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34], qualifiers = "w320dp-h2400dp")
class SwatchTouchTargetTest {

    @get:Rule
    val compose = createComposeRule()

    @Test
    fun `every page colour swatch is a 48 dp target, 8 dp from the next`() {
        compose.setContent {
            StoryArcTheme {
                Column(Modifier.width(280.dp)) {
                    SwatchRow(
                        colours = SUGGESTED_BACKGROUNDS,
                        selected = SUGGESTED_BACKGROUNDS.first(),
                        onSelect = {},
                    )
                }
            }
        }
        compose.waitForIdle()

        compose.onAllNodes(hasClickAction()).assertAllTouchTargetsAreAtLeast()
        compose.onAllNodes(hasClickAction()).assertTouchTargetsAreApart()
    }

    @Test
    fun `every highlight colour of the selection menu is a 48 dp target`() {
        compose.setContent {
            StoryArcTheme {
                SelectionMenu(onHighlight = {}, onNote = {}, onCopy = {}, onSearch = {})
            }
        }
        compose.waitForIdle()

        // The colours carry no description of their own, which is what tells them from the
        // three icon buttons under them.
        val colours = compose.onAllNodes(
            hasClickAction() and SemanticsMatcher.keyNotDefined(SemanticsProperties.ContentDescription),
        )

        colours.assertAllTouchTargetsAreAtLeast()
        colours.assertTouchTargetsAreApart()
    }
}
