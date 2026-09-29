package app.storyarc.feature.reader

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalDensity
import kotlinx.coroutines.delay

/**
 * What a refused discrete turn shows besides its haptic (task 8.11, D13).
 *
 * `page-transitions` "Turning at a boundary": "the page resists with a bounded rubber-band
 * and returns". A drag in Slide or Scroll already gets the container's own overscroll. A tap
 * or a key had only the haptic. Under Reduce Motion the give becomes a brief dim. iOS's
 * `RefusalResponse` is the same rule.
 */
internal sealed interface RefusalResponse {
    /** The page gives [reachDp] sideways, then springs back. */
    data class Nudge(val reachDp: Float) : RefusalResponse

    /** The page dims for a moment, then comes back. */
    data object Dim : RefusalResponse

    companion object {
        /** How far the page gives before it springs back. */
        const val REACH_DP = 24f

        /**
         * The response for one refused turn, or null in a scroll, which has no page to give.
         *
         * A turn is refused only going back from the first page. So the page gives the way
         * the missing page would have pushed it: right in left-to-right, left in right-to-left.
         */
        fun of(reduceMotion: Boolean, isRightToLeft: Boolean, scrolls: Boolean): RefusalResponse? = when {
            scrolls -> null
            reduceMotion -> Dim
            else -> Nudge(if (isRightToLeft) -REACH_DP else REACH_DP)
        }
    }
}

/**
 * Where the page stands while it resists, and the modifier that draws it there.
 *
 * The dim is a step with a delay, not an animation: a reader who removed animations has an
 * animator scale of zero, and every Compose animation would then finish before it is seen.
 */
internal class RefusalResistance(private val density: Float) {
    private val offset = Animatable(0f)
    private var isDimmed by mutableStateOf(false)

    val modifier: Modifier = Modifier.graphicsLayer {
        translationX = offset.value
        alpha = if (isDimmed) DIM_ALPHA else 1f
    }

    suspend fun play(response: RefusalResponse?) {
        when (response) {
            is RefusalResponse.Nudge -> {
                offset.animateTo(response.reachDp * density, tween(NUDGE_MILLIS))
                offset.animateTo(0f, spring(dampingRatio = Spring.DampingRatioMediumBouncy))
            }
            RefusalResponse.Dim -> {
                isDimmed = true
                delay(DIM_MILLIS)
                isDimmed = false
            }
            null -> Unit
        }
    }

    private companion object {
        const val DIM_ALPHA = 0.6f
        const val DIM_MILLIS = 150L
        const val NUDGE_MILLIS = 100
    }
}

/** A [RefusalResistance] for the life of the reader. */
@Composable
internal fun rememberRefusalResistance(): RefusalResistance {
    val density = LocalDensity.current.density
    return remember(density) { RefusalResistance(density) }
}
