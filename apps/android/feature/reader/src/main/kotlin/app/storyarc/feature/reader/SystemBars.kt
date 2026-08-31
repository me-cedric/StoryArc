package app.storyarc.feature.reader

import androidx.activity.compose.LocalActivity
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalView
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect

/**
 * The clock, the battery and the signal bars, going away with the reader's own chrome.
 *
 * `comic-reader` asks for two things this answers. A publication opens with "the page
 * filling the screen, chrome hidden, and the system status and home indicators dim per
 * platform convention"; and while chrome is visible it "floats over the page ... and the
 * page is not resized or shifted". The page has always drawn edge to edge here, which is
 * the half that was already built — and edge to edge with nothing hiding the bars is how
 * a clock came to sit over every page of every reading session. iOS answers the same
 * requirement with `.statusBarHidden(!isChromeVisible)`.
 *
 * It follows [isChromeVisible] and nothing else. Two notions of "chrome is showing" — one
 * for the app's bars and one for the system's — is a pair that drifts, and the point is
 * that they are one state: the centre tap that reveals the reading controls is the tap
 * that brings the clock back, because it is the same tap.
 *
 * Both bars, not the status bar alone. The scenario names the home indicator as well as
 * the status, and on Android the home indicator is the gesture pill in the navigation bar
 * — hiding one and leaving the other lights a bar across the foot of the artwork.
 *
 * `BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE` is what makes that safe rather than a trap. A
 * swipe from an edge draws the bars back over the page for a few seconds without changing
 * the window's insets, so nothing reflows and nothing is unreachable; the system takes
 * them away again by itself, and the window is still hidden underneath, so the reader does
 * not have to know it happened.
 */
@Composable
internal fun SystemBarsFollowChrome(isChromeVisible: Boolean) {
    val view = LocalView.current
    val window = LocalActivity.current?.window ?: return
    val controller = remember(window, view) { WindowCompat.getInsetsController(window, view) }

    // First, so the behaviour is set before anything is hidden under it, and last, so the
    // window is handed back the way it was found. However the reading session ends — the
    // close button, a back gesture, the end screen, a publication that failed to open —
    // everything outside this reader is a list of things to read, and a library with no
    // clock is a defect rather than a style.
    DisposableEffect(controller) {
        controller.systemBarsBehavior =
            WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        onDispose {
            controller.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_DEFAULT
            controller.show(WindowInsetsCompat.Type.systemBars())
        }
    }

    // The state lives on the window, not in this composable, which is what carries it
    // across the things that would otherwise lose it: a configuration change recomposes
    // with whatever the chrome says now, and the app leaving the foreground does not
    // recompose at all.
    LaunchedEffect(controller, isChromeVisible) { controller.follow(isChromeVisible) }

    // Said again on the way back to the front. The window usually keeps what it was told,
    // but not everywhere and not after everything — a device unlocked straight back into
    // the reader can arrive with the bars up while the reader still believes them down.
    // One idempotent call per resume closes a state nothing else would correct.
    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) { controller.follow(isChromeVisible) }
}

/** Up with the reading controls, and away with them. */
private fun WindowInsetsControllerCompat.follow(isChromeVisible: Boolean) {
    if (isChromeVisible) {
        show(WindowInsetsCompat.Type.systemBars())
    } else {
        hide(WindowInsetsCompat.Type.systemBars())
    }
}
