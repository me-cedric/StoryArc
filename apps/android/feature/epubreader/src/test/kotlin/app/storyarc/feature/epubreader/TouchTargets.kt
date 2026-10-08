package app.storyarc.feature.epubreader

import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.test.SemanticsNodeInteraction
import androidx.compose.ui.test.SemanticsNodeInteractionCollection
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import org.junit.Assert.assertTrue

/**
 * Asserts the node is laid out at least [min] wide and high.
 *
 * Material 3 asks for a touch target of 48 x 48 dp. **The layout box is what is measured, and
 * not `touchBoundsInRoot`.** Compose widens the hit area of every clickable to the view
 * configuration's minimum touch target without changing its layout, so `touchBoundsInRoot` is
 * 48 x 48 for a 32 dp chip too and an assertion on it can never fail. The accessibility
 * service reports the layout box, which is where the owner's audit found the sleep-timer
 * chips at 37.3 dp.
 */
internal fun SemanticsNodeInteraction.assertTouchTargetIsAtLeast(min: Dp = 48.dp): SemanticsNodeInteraction {
    val node = fetchSemanticsNode()
    val (width, height) = with(node.layoutInfo.density) {
        node.boundsInRoot.width.toDp() to node.boundsInRoot.height.toDp()
    }
    assertTrue("laid out $width x $height, below $min x $min", width >= min && height >= min)
    return this
}

/** Asserts every node in the collection is a touch target of at least [min]. */
internal fun SemanticsNodeInteractionCollection.assertAllTouchTargetsAreAtLeast(min: Dp = 48.dp) {
    val count = fetchSemanticsNodes().size
    assertTrue("no targets to measure", count > 0)
    for (index in 0 until count) get(index).assertTouchTargetIsAtLeast(min)
}

/** Asserts every pair of nodes in the collection is laid out at least [gap] apart. */
internal fun SemanticsNodeInteractionCollection.assertTouchTargetsAreApart(gap: Dp = 8.dp) {
    val nodes = fetchSemanticsNodes()
    assertTrue("fewer than two targets to compare", nodes.size >= 2)
    for (a in nodes.indices) {
        for (b in a + 1 until nodes.size) {
            val density = nodes[a].layoutInfo.density
            val apart = with(density) { distance(nodes[a].boundsInRoot, nodes[b].boundsInRoot).toDp() }
            assertTrue(
                "targets $a ${nodes[a].boundsInRoot} and $b ${nodes[b].boundsInRoot} are $apart apart, below $gap",
                apart >= gap,
            )
        }
    }
}

private fun distance(a: Rect, b: Rect): Float {
    val across = maxOf(a.left - b.right, b.left - a.right)
    val down = maxOf(a.top - b.bottom, b.top - a.bottom)
    return maxOf(across, down)
}
