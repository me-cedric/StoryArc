package app.storyarc.feature.epubreader

import android.os.Build
import android.view.ViewGroup
import app.storyarc.core.model.PageTransition
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
 * @param dipHost what the Fast fade dip and the curl's sheet are added to, above the book and
 *   below the chrome.
 * @param dipIndex where in [dipHost] either of them goes.
 * @param pageColour the page's own colour, which the dip fades through.
 * @param reduceMotion whether Readium's own turn must not animate.
 * @param drawnTurn which transition this reader draws itself, or null where Readium keeps the
 *   turn.
 */
internal class EpubPageTurns(
    private val scope: CoroutineScope,
    private val navigator: () -> EpubNavigatorFragment?,
    private val dipHost: () -> ViewGroup,
    private val dipIndex: Int,
    private val pageColour: () -> Int,
    private val reduceMotion: () -> Boolean,
    private val drawnTurn: () -> PageTransition?,
) {
    /** A turn already running. A second swipe during one would fade over a fade. */
    private var isTurning = false

    /**
     * What a tap means: an edge-third tap turns the page in every mode, where the setting
     * allows it, and any other tap toggles the chrome.
     *
     * Asks for the navigator only where a turn can follow -- whether a tap lands in the
     * middle third, or the setting is off, never depends on [isRightToLeft], so the first,
     * direction-blind call below answers that for free. Only an edge tap resolves it for
     * real, from the one navigator this call fetches and passes on to [turn] rather than
     * letting it fetch a second one of its own.
     */
    fun tap(x: Float, width: Float, tapTurnsPages: Boolean, toggleChrome: () -> Unit) {
        if (EdgeTap.outcome(x, width, tapTurnsPages) == null) {
            toggleChrome()
            return
        }
        val resolvedNavigator = navigator()
        val forward = EdgeTap.outcome(x, width, tapTurnsPages, isRightToLeft(resolvedNavigator))
        turn(checkNotNull(forward) { "the zone a tap landed in cannot change between the two calls" }, resolvedNavigator)
    }

    /**
     * What a key press means, and whether it was the reader's to take.
     *
     * A volume key is taken only where [volumeTurns] is on. Otherwise it goes back to the
     * system and changes the volume, as a reader who never asked for turning expects.
     * Enter and an unmapped key never depend on [isRightToLeft] either, the same reason
     * [tap] asks for the navigator only once it knows an edge was hit.
     */
    fun key(keyCode: Int, volumeTurns: Boolean, toggleChrome: () -> Unit): Boolean {
        val volume = volumeTurnsForward(keyCode)
        if (volume != null) {
            if (volumeTurns) turn(volume)
            return volumeTurns
        }
        when (EpubTurnKey.of(keyCode)) {
            EpubTurnKey.ToggleChrome -> toggleChrome()
            null -> return false
            else -> {
                val resolvedNavigator = navigator()
                when (EpubTurnKey.of(keyCode, isRightToLeft(resolvedNavigator))) {
                    EpubTurnKey.TurnBackward -> turn(forward = false, resolvedNavigator)
                    EpubTurnKey.TurnForward -> turn(forward = true, resolvedNavigator)
                    EpubTurnKey.ToggleChrome, null -> Unit
                }
            }
        }
        return true
    }

    /**
     * The turn this reader draws where it draws one, Readium's own elsewhere.
     *
     * @param resolvedNavigator the navigator a caller already fetched, so this does not
     *   fetch a second one of its own for the one press that caused it.
     */
    @OptIn(ExperimentalReadiumApi::class)
    fun turn(forward: Boolean, resolvedNavigator: EpubNavigatorFragment? = navigator()) {
        when (drawnTurn()) {
            PageTransition.PAGE_CURL -> {
                withCurl(forward, resolvedNavigator)
                return
            }
            PageTransition.FAST_FADE -> {
                withFade(forward, resolvedNavigator)
                return
            }
            else -> Unit
        }
        val navigator = resolvedNavigator ?: return
        val animated = !reduceMotion()
        if (forward) navigator.goForward(animated = animated) else navigator.goBackward(animated = animated)
    }

    /**
     * The turn a swipe takes, which is whichever one this reader is drawing.
     *
     * [TurnInterceptor] holds one callback and arms it only while the reader owns the turn,
     * so this is what it holds. Routed through [turn] rather than bound to a mode when the
     * interceptor was armed: a reader chooses a page turn *after* the book is open.
     */
    fun swipe(forward: Boolean) = turn(forward)

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
    fun withFade(forward: Boolean, resolvedNavigator: EpubNavigatorFragment? = navigator()) {
        val navigator = resolvedNavigator ?: return
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

    /** The finger-driven curl. One per reader, so a drag can catch a tap's settle. */
    private val curl by lazy {
        ProseCurlDriver(
            scope = scope,
            density = { dipHost().resources.displayMetrics.density },
            probe = { ProseCurlProbe.report(dipHost().context, it) },
        )
    }

    /**
     * Turns a page by rolling a picture of it off a picture of the next one, from a tap, a key
     * or a volume press: the same spring a released drag runs. Task 8.12.
     *
     * [ProseCurlDriver] carries the order of the lift and why. What is here is the API floor:
     * AGSL's `RuntimeShader` arrives at API 33, and below it `EpubReaderViewModel.canCurl` has
     * already withheld the mode, so the fade branch is unreachable rather than merely unused.
     */
    @OptIn(ExperimentalReadiumApi::class)
    fun withCurl(forward: Boolean, resolvedNavigator: EpubNavigatorFragment? = navigator()) {
        val navigator = resolvedNavigator ?: return
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            withFade(forward, resolvedNavigator)
            return
        }
        val page = NavigatorProsePage(dipHost(), dipIndex, navigator)
        if (!curl.request(forward, page, isRightToLeft(navigator))) {
            if (forward) navigator.goForward(animated = false) else navigator.goBackward(animated = false)
        }
    }

    /** A finger on the page while Curl draws the turn: the fold follows it. Task 8.12. */
    fun drag(phase: ProseDrag) {
        val navigator = navigator() ?: return
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        curl.drag(phase, NavigatorProsePage(dipHost(), dipIndex, navigator), isRightToLeft(navigator))
    }
}
