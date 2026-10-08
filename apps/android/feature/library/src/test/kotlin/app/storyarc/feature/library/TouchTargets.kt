package app.storyarc.feature.library

import androidx.compose.ui.test.SemanticsNodeInteraction
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import org.junit.Assert.assertTrue

/**
 * Asserts the node's touch target is at least [min] in both directions.
 *
 * Material 3 asks for 48 x 48 dp. `touchBoundsInRoot` is the box a finger can hit, which is
 * the layout box widened to `minimumInteractiveComponentSize` where the component applies it,
 * so a custom height that defeats that widening fails here. ui-test has an `...IsEqualTo` form
 * of this check and no `...IsAtLeast` one.
 */
internal fun SemanticsNodeInteraction.assertTouchTargetIsAtLeast(min: Dp = 48.dp): SemanticsNodeInteraction {
    val node = fetchSemanticsNode()
    val (width, height) = with(node.layoutInfo.density) {
        node.touchBoundsInRoot.width.toDp() to node.touchBoundsInRoot.height.toDp()
    }
    assertTrue("touch target is $width x $height, below $min x $min", width >= min && height >= min)
    return this
}
