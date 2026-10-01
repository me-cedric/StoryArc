package app.storyarc.feature.epubreader

import android.view.ViewGroup
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch
import org.readium.r2.navigator.epub.EpubNavigatorFragment
import org.readium.r2.shared.ExperimentalReadiumApi

/**
 * The reflowable reader's page turns, from a tap, a key, a volume press or a swipe.
 *
 * Out of [EpubReaderActivity], which holds the navigator and the dip's host but is past
 * its line cap: what a press means and which turn answers it are one concern, and they
 * change together.
 *
 * @param navigator the navigator on screen, or null before it exists.
 * @param dipHost what the Fast fade dip is added to, above the book and below the chrome.
 * @param dipIndex where in [dipHost] the dip goes.
 * @param pageColour the page's own colour, which the dip fades through.
 * @param reduceMotion whether Readium's own turn must not animate.
 * @param fadeOwnsTheTurn whether Fast fade draws the turn, rather than Readium.
 */
internal class EpubPageTurns(
    private val scope: CoroutineScope,
    private val navigator: () -> EpubNavigatorFragment?,
    private val dipHost: () -> ViewGroup,
    private val dipIndex: Int,
    private val pageColour: () -> Int,
    private val reduceMotion: () -> Boolean,
    private val fadeOwnsTheTurn: () -> Boolean,
) {
    /** A turn already running. A second swipe during one would fade over a fade. */
    private var isTurning = false

    /**
     * What a tap means: an edge-third tap turns the page in every mode, where the setting
     * allows it, and any other tap toggles the chrome.
     */
    fun tap(x: Float, width: Float, tapTurnsPages: Boolean, toggleChrome: () -> Unit) {
        when (val forward = EdgeTap.outcome(x, width, tapTurnsPages)) {
            null -> toggleChrome()
            else -> turn(forward)
        }
    }

    /**
     * What a key press means, and whether it was the reader's to take.
     *
     * A volume key is taken only where [volumeTurns] is on. Otherwise it goes back to the
     * system and changes the volume, as a reader who never asked for turning expects.
     */
    fun key(keyCode: Int, volumeTurns: Boolean, toggleChrome: () -> Unit): Boolean {
        val volume = volumeTurnsForward(keyCode)
        if (volume != null) {
            if (volumeTurns) turn(volume)
            return volumeTurns
        }
        when (EpubTurnKey.of(keyCode)) {
            EpubTurnKey.TurnBackward -> turn(forward = false)
            EpubTurnKey.TurnForward -> turn(forward = true)
            EpubTurnKey.ToggleChrome -> toggleChrome()
            null -> return false
        }
        return true
    }

    /** Fast fade's own turn where it owns the turn, Readium's own elsewhere. */
    @OptIn(ExperimentalReadiumApi::class)
    fun turn(forward: Boolean) {
        if (fadeOwnsTheTurn()) {
            withFade(forward)
            return
        }
        val navigator = navigator() ?: return
        val animated = !reduceMotion()
        if (forward) navigator.goForward(animated = animated) else navigator.goBackward(animated = animated)
    }

    /**
     * Turns a page with a transition StoryArc draws rather than one Readium draws.
     *
     * The dip is opaque before the navigator moves, so the swap is never on screen: what
     * a reader sees is the page they were on fading to the page colour, and the next one
     * arriving out of it. `page-transitions` calls this Fast fade.
     *
     * A turn that cannot happen — the last page, the first page — takes the dip straight
     * back off instead of completing, because a full fade there would read as a turn that
     * did happen.
     */
    @OptIn(ExperimentalReadiumApi::class)
    fun withFade(forward: Boolean) {
        val navigator = navigator() ?: return
        if (isTurning) return
        isTurning = true

        scope.launch {
            try {
                FadeTurn(dipHost(), dipIndex).run(pageColour = pageColour()) {
                    if (forward) {
                        navigator.goForward(animated = false)
                    } else {
                        navigator.goBackward(animated = false)
                    }
                }
            } finally {
                isTurning = false
            }
        }
    }
}
