package app.storyarc.core.snapshots

import android.graphics.Bitmap
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsNode
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * One accepted fault: the [check] that reports it, the [label] of the node it reports it on, and
 * [why] it stands. A fault listed here is not reported; one that no longer occurs is an error, so
 * the list drains. A fault with a [look] stands in that appearance only.
 */
class KnownFault(val check: Check, val label: String, val why: String, val look: Look? = null)

/** The three rules a catalogue entry is held to. */
enum class Check { TOUCH_TARGET, LABEL, CONTRAST }

/** One thing that broke a rule, in words a person can act on. */
class Fault(val check: Check, val label: String, val detail: String) {
    override fun toString() = "$check on \"$label\": $detail"
}

/**
 * The accessibility rules of Material 3 and WCAG, run over a Compose semantics tree and the
 * picture it drew.
 *
 * **Why this and not the Accessibility Test Framework.** `enableAccessibilityChecks()` runs under
 * Robolectric but checks nothing: the framework walks the view hierarchy, and under Robolectric
 * `AccessibilityNodeInfo.getChild` has no connection to answer for Compose's virtual nodes, so
 * every check reports `NOT_RUN` and the hierarchy ends at `AndroidComposeView`. These checks read
 * the semantics tree directly, which is what the framework reads on a device.
 *
 * - [Check.TOUCH_TARGET]: a clickable node's touch bounds are at least 48 dp wide and 48 dp
 *   high. These are the bounds the accessibility service reports and the framework measures:
 *   Compose widens a small clickable to the minimum touch target, and an ancestor that clips
 *   cuts the widened area short again, which is how a 32 dp chip in a tight row fails.
 * - [Check.LABEL]: a clickable node has text or a content description.
 * - [Check.CONTRAST]: the drawn text reaches 4.5:1 against what is behind it, or 3:1 for large
 *   text (18 sp, or 14 sp bold). The background is the commonest colour in the text's box on the
 *   picture. The text colour is the declared one, or the pixel that differs most from the
 *   background when the style leaves it to the theme.
 */
object Accessibility {
    private val MIN_TARGET: Dp = 48.dp

    fun faults(root: SemanticsNode, unmergedRoot: SemanticsNode, picture: Bitmap): List<Fault> =
        targetFaults(root) + contrastFaults(unmergedRoot, picture)

    private fun SemanticsNode.walk(): Sequence<SemanticsNode> =
        sequenceOf(this) + children.asSequence().flatMap { it.walk() }

    private fun SemanticsNode.label(): String =
        config.getOrNull(SemanticsProperties.ContentDescription)?.joinToString(" ")?.takeIf { it.isNotBlank() }
            ?: config.getOrNull(SemanticsProperties.Text)?.joinToString(" ") { it.text }?.takeIf { it.isNotBlank() }
            ?: config.getOrNull(SemanticsProperties.EditableText)?.text?.takeIf { it.isNotBlank() }
            ?: ""

    private fun SemanticsNode.isShown(root: SemanticsNode): Boolean {
        if (config.contains(SemanticsProperties.HideFromAccessibility)) return false
        val b = boundsInRoot
        val r = root.boundsInRoot
        return b.width > 0 && b.height > 0 && b.right > r.left && b.left < r.right &&
            b.bottom > r.top && b.top < r.bottom
    }

    private fun targetFaults(root: SemanticsNode): List<Fault> = root.walk()
        .filter { it.config.contains(SemanticsActions.OnClick) && it.isShown(root) }
        .flatMap { node ->
            val density = node.layoutInfo.density
            val width = with(density) { node.touchBoundsInRoot.width.toDp() }
            val height = with(density) { node.touchBoundsInRoot.height.toDp() }
            val label = node.label()
            buildList {
                if (width < MIN_TARGET || height < MIN_TARGET) {
                    add(Fault(Check.TOUCH_TARGET, label, "laid out ${width.value} x ${height.value} dp, below 48 x 48"))
                }
                if (label.isEmpty()) add(Fault(Check.LABEL, label, "a clickable node at ${node.boundsInRoot} has no text and no description"))
            }
        }
        .toList()

    private fun contrastFaults(root: SemanticsNode, picture: Bitmap): List<Fault> = root.walk()
        .filter { node ->
            val text = node.config.getOrNull(SemanticsProperties.Text)
            !text.isNullOrEmpty() && text.any { it.text.isNotBlank() } &&
                !node.config.contains(SemanticsProperties.Disabled) && node.isShown(root)
        }
        .mapNotNull { node -> contrastFault(node, picture) }
        .toList()

    private fun contrastFault(node: SemanticsNode, picture: Bitmap): Fault? {
        val box = node.boundsInRoot
        val left = box.left.toInt().coerceIn(0, picture.width - 1)
        val top = box.top.toInt().coerceIn(0, picture.height - 1)
        val right = box.right.toInt().coerceIn(left + 1, picture.width)
        val bottom = box.bottom.toInt().coerceIn(top + 1, picture.height)
        val width = right - left
        val pixels = IntArray(width * (bottom - top))
        picture.getPixels(pixels, 0, width, left, top, width, bottom - top)

        val background = pixels.toList().groupingBy { it and 0xF0F0F0 }.eachCount().maxBy { it.value }.key
            .let { key -> pixels.first { (it and 0xF0F0F0) == key } }
        val result = node.config.getOrNull(SemanticsActions.GetTextLayoutResult)?.action
        val layouts = mutableListOf<TextLayoutResult>()
        result?.invoke(layouts)
        val style = layouts.firstOrNull()?.layoutInput?.style
        val declared = style?.color?.takeIf { it != Color.Unspecified && it.alpha >= 0.99f }
        val ink = declared?.toArgb() ?: pixels.maxBy { distance(it, background) }
        val ratio = contrast(ink, background)

        val large = style != null && (
            (style.fontSize.isSp && style.fontSize >= 18.sp) ||
                (style.fontSize.isSp && style.fontSize >= 14.sp && (style.fontWeight?.weight ?: 400) >= 700)
            )
        val needed = if (large) 3.0 else 4.5
        if (ratio >= needed) return null
        return Fault(
            Check.CONTRAST,
            node.label(),
            "%.2f:1 against %s, below %.1f:1".format(ratio, "#%06X".format(background and 0xFFFFFF), needed),
        )
    }

    private fun distance(a: Int, b: Int): Int {
        val dr = ((a shr 16) and 0xFF) - ((b shr 16) and 0xFF)
        val dg = ((a shr 8) and 0xFF) - ((b shr 8) and 0xFF)
        val db = (a and 0xFF) - (b and 0xFF)
        return dr * dr + dg * dg + db * db
    }

    /** The WCAG contrast ratio of two opaque colours. */
    fun contrast(a: Int, b: Int): Double {
        val la = Color(a).copy(alpha = 1f).luminance().toDouble() + 0.05
        val lb = Color(b).copy(alpha = 1f).luminance().toDouble() + 0.05
        return maxOf(la, lb) / minOf(la, lb)
    }

    /** Throws when [faults] holds anything that [known] does not account for, or [known] holds a stale entry. */
    fun assertNone(faults: List<Fault>, known: List<KnownFault>) {
        val unaccepted = faults.filter { f -> known.none { it.check == f.check && f.label.contains(it.label) } }
        val stale = known.filter { k -> faults.none { it.check == k.check && it.label.contains(k.label) } }
        val message = buildString {
            if (unaccepted.isNotEmpty()) {
                appendLine("${unaccepted.size} accessibility fault(s):")
                unaccepted.forEach { appendLine("  $it") }
            }
            if (stale.isNotEmpty()) {
                appendLine("${stale.size} known fault(s) no longer occur, so remove them:")
                stale.forEach { appendLine("  ${it.check} on \"${it.label}\"") }
            }
        }
        if (message.isNotEmpty()) throw AssertionError(message)
    }
}
