package app.storyarc.core.designsystem.control

import androidx.compose.material3.ButtonGroupDefaults
import androidx.compose.material3.ToggleButtonDefaults
import androidx.compose.material3.ToggleButtonShapes
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertIsNotSelected
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.getUnclippedBoundsInRoot
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.unit.dp
import app.storyarc.core.designsystem.theme.StoryArcTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * The connected button group, and the three things about it that no compiler will check.
 *
 * Material 3 Expressive says the baseline segmented button *"is no longer recommended"* and
 * names the connected button group as its replacement, distinguishing the selected option by
 * a **round-to-square shape change rather than by a fill**. Compose has not deprecated
 * `SegmentedButton` — `javap` over `material3-1.5.0-alpha26.aar` shows no `Deprecated`
 * annotation on it anywhere — so nothing in the build says any of this, and nothing will.
 *
 * **There is no `ConnectedButtonGroup` composable to call.** Checked against the same
 * artifact: no class or function in `material3` has "Connected" in its name. What exists is
 * a `Row` arrangement constant and three `@Composable` shape helpers keyed by position, so
 * the component is assembled and the position arithmetic is ours. That is what makes it
 * worth a test: an off-by-one here draws a group with two rounded left ends, and it draws
 * perfectly happily.
 *
 * The shape assertions compare against Material's **own** helpers rather than against
 * corner radii written down here. A radius copied into a test is a second source of truth
 * that goes stale on the next alpha; an equality against the helper cannot.
 */
@RunWith(RobolectricTestRunner::class)
// Robolectric ships no image for API 37, and nothing here has an API level in it. A phone
// window, because the two call sites are both reader chrome on a phone.
@Config(sdk = [34], qualifiers = "w360dp-h740dp")
// Legacy graphics measure every glyph at about a pixel wide, so the gap assertion below
// would pass against a group whose buttons overlap. `CompactPlayerTest` sets this out.
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class ConnectedButtonGroupTest {

    @get:Rule
    val compose = createComposeRule()

    private val three = listOf("Search", "Marks", "Outline")

    /**
     * What the component computed, beside what Material would have.
     *
     * Both are read out of the same composition, because the helpers are `@Composable` —
     * they resolve against `MaterialTheme.shapes`, so a value captured outside a
     * composition is not the value the group is drawn with.
     */
    private class Reference {
        val perPosition = mutableListOf<ToggleButtonShapes>()
        lateinit var leading: ToggleButtonShapes
        lateinit var middle: ToggleButtonShapes
        lateinit var trailing: ToggleButtonShapes

        /**
         * Material's shape for a toggle button that is in no group.
         *
         * The one value rather than the whole `ToggleButtonShapes`, because
         * `ToggleButtonDefaults.shapes()` does not resolve: the no-argument overload and the
         * three-defaulted-argument one beside it are both applicable to an empty argument
         * list. Verified by compiling it — the error is `Unresolved reference 'shapes'`.
         */
        lateinit var standalone: Shape
    }

    private fun shapesFor(count: Int): Reference {
        val reference = Reference()
        compose.setContent {
            StoryArcTheme(useDynamicColor = false) {
                reference.leading = ButtonGroupDefaults.connectedLeadingButtonShapes()
                reference.middle = ButtonGroupDefaults.connectedMiddleButtonShapes()
                reference.trailing = ButtonGroupDefaults.connectedTrailingButtonShapes()
                reference.standalone = ToggleButtonDefaults.shape
                // Cleared rather than appended to: a recomposition would otherwise leave
                // the list with two runs in it and the indices below would read the first.
                reference.perPosition.clear()
                repeat(count) { index ->
                    reference.perPosition += connectedButtonShapes(index, count)
                }
            }
        }
        compose.waitForIdle()
        return reference
    }

    @Test
    fun `the ends of a group are shaped leading and trailing, and everything between middle`() {
        val reference = shapesFor(3)

        assertEquals(
            "The first option is not shaped with connectedLeadingButtonShapes, so the" +
                " group's left end is not rounded off.",
            reference.leading,
            reference.perPosition[0],
        )
        assertEquals(
            "An interior option is not shaped with connectedMiddleButtonShapes.",
            reference.middle,
            reference.perPosition[1],
        )
        assertEquals(
            "The last option is not shaped with connectedTrailingButtonShapes, so the" +
                " group's right end is not rounded off.",
            reference.trailing,
            reference.perPosition[2],
        )
    }

    /** Two options are two ends and no interior — the case both call sites nearly are. */
    @Test
    fun `a group of two is all ends`() {
        val reference = shapesFor(2)

        assertEquals(reference.leading, reference.perPosition[0])
        assertEquals(reference.trailing, reference.perPosition[1])
        assertNotEquals(
            "A group of two used a middle shape somewhere. There is no interior in two.",
            reference.middle,
            reference.perPosition[1],
        )
    }

    /**
     * One option is not a leading option.
     *
     * A lone button shaped `connectedLeadingButtonShapes` is rounded on its left and squared
     * on its right, joining a group that does not exist. Material's standalone
     * `ToggleButtonDefaults.shapes()` is the honest answer, and this is the branch a
     * `if (index == 0)` written first would get wrong.
     */
    @Test
    fun `a group of one gets a single shape rather than a leading one`() {
        val reference = shapesFor(1)

        assertEquals(
            "A group of one is not shaped as a standalone toggle button.",
            reference.standalone,
            reference.perPosition[0].shape,
        )
        assertNotEquals(
            "A group of one is shaped as the leading button of a group it has no peers in" +
                " — squared off on the side where nothing follows it.",
            reference.leading,
            reference.perPosition[0],
        )
    }

    /**
     * Selection is the shape change, and the shape change is real.
     *
     * The whole point of the Expressive guidance is that the selected option changes
     * *shape*, not fill. If `checkedShape` matched `shape` the group would still compile,
     * still select, and still be indistinguishable — a segmented button without the fill it
     * used to have, which is worse than what it replaced.
     */
    @Test
    fun `every position distinguishes selection by a different shape`() {
        val reference = shapesFor(3)

        reference.perPosition.forEachIndexed { index, shapes ->
            assertNotEquals(
                "Position $index draws the same shape whether it is selected or not, so" +
                    " nothing marks the selection. Material 3 Expressive distinguishes the" +
                    " chosen option of a connected group by a round-to-square change.",
                shapes.shape,
                shapes.checkedShape,
            )
        }
    }

    /**
     * What a screen reader is told.
     *
     * `ToggleButton` announces itself as a **checkbox** — `role = Role.Checkbox`, read out
     * of `ToggleButtonKt`'s bytecode, not from the documentation — and a checkbox is checked
     * or not, never selected. Three checkboxes in a row is also the wrong shape of thing: it
     * says a reader may pick any number of them, when exactly one of these is ever true.
     */
    @Test
    fun `the chosen option announces itself as selected and the others do not`() {
        compose.setContent {
            StoryArcTheme(useDynamicColor = false) {
                ConnectedButtonGroup(options = three, selectedIndex = 1, onSelect = {})
            }
        }

        compose.onNodeWithText("Marks").assertIsSelected()
        compose.onNodeWithText("Search").assertIsNotSelected()
        compose.onNodeWithText("Outline").assertIsNotSelected()
    }

    @Test
    fun `the group is one selectable group of radio buttons, not three loose checkboxes`() {
        compose.setContent {
            StoryArcTheme(useDynamicColor = false) {
                ConnectedButtonGroup(options = three, selectedIndex = 0, onSelect = {})
            }
        }

        compose.onNode(SemanticsMatcher.keyIsDefined(SemanticsProperties.SelectableGroup))
            .assertExists()
        three.forEach { label ->
            compose.onNodeWithText(label).assert(
                SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.RadioButton),
            )
            // And the checkbox state is *gone*, not merely overridden. Semantics merge, so
            // setting `Role.RadioButton` over `ToggleButton`'s own role does not by itself
            // remove the `ToggleableState` it also sets — and a node carrying both is read
            // out as a radio button that is checked or unchecked, which is the announcement
            // this component exists to correct. Asserting the role alone passed while that
            // was still possible.
            compose.onNodeWithText(label).assert(
                SemanticsMatcher.keyNotDefined(SemanticsProperties.ToggleableState),
            )
        }
    }

    /** The index reaches the caller, which is the only thing the caller asked for. */
    @Test
    fun `choosing an option reports its position`() {
        var chosen = -1
        compose.setContent {
            StoryArcTheme(useDynamicColor = false) {
                ConnectedButtonGroup(options = three, selectedIndex = 0, onSelect = { chosen = it })
            }
        }

        compose.onNodeWithText("Outline").performClick()

        assertEquals(2, chosen)
    }

    /**
     * The buttons are separated by Material's connected gap, not touching and not spread.
     *
     * `ButtonGroupDefaults.ConnectedSpaceBetween` is what makes a connected group read as
     * one control rather than as a row of buttons, and it is the one part of the assembly
     * that a plain `Row` would silently drop.
     */
    @Test
    fun `the options are spaced by Materials connected gap`() {
        var expected = 0.dp
        compose.setContent {
            StoryArcTheme(useDynamicColor = false) {
                expected = ButtonGroupDefaults.ConnectedSpaceBetween
                ConnectedButtonGroup(options = three, selectedIndex = 0, onSelect = {})
            }
        }

        val first = compose.onNodeWithText("Search").getUnclippedBoundsInRoot()
        val second = compose.onNodeWithText("Marks").getUnclippedBoundsInRoot()

        assertEquals(
            "The gap between two options is not ButtonGroupDefaults.ConnectedSpaceBetween," +
                " so this is a row of buttons rather than a connected group.",
            expected.value,
            (second.left - first.right).value,
            0.5f,
        )
    }
}
