package app.storyarc.feature.reader

import android.content.ComponentCallbacks2
import android.content.pm.ActivityInfo
import android.content.res.Configuration
import androidx.activity.compose.LocalActivity
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import app.storyarc.core.model.MemoryPressure
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

// Three effects of [Pager], moved here unchanged so `ReaderPager.kt` stays under the 800-line
// cap. Each one reads only what the pager hands it.

@Composable
internal fun OrientationLockEffect(isOrientationLocked: Boolean) {
    // `comic-reader`: a locked orientation "stays locked for the reader only, and the
    // rest of the app follows the device". `SCREEN_ORIENTATION_LOCKED` pins the activity
    // to the way up it is already showing, whichever that is, and the effect hands it
    // back on the way out — which is what makes it the reader's lock and not the app's.
    val activity = LocalActivity.current
    DisposableEffect(activity, isOrientationLocked) {
        activity?.requestedOrientation = if (isOrientationLocked) {
            ActivityInfo.SCREEN_ORIENTATION_LOCKED
        } else {
            ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
        }
        onDispose { activity?.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED }
    }
}

@Composable
internal fun ChromeAutoHideEffect(
    isChromeVisible: Boolean,
    position: Int,
    isMenuOpen: Boolean,
    isBrowsingThumbnails: Boolean,
    isAdjusting: Boolean,
    scrubbing: Int?,
    onHide: () -> Unit,
) {
    // The strip and an open menu both count as interaction: reading either takes
    // longer than four seconds, and the chrome vanishing underneath would take them
    // with it.
    LaunchedEffect(
        isChromeVisible,
        position,
        isMenuOpen,
        isBrowsingThumbnails,
        isAdjusting,
        scrubbing,
    ) {
        // Not while the adjustment controls are open, and not mid-scrub: a reader dragging
        // a slider has not stopped interacting because they have not touched the page, and
        // a drag no longer moves `position` for the countdown to notice.
        if (!isChromeVisible || isMenuOpen || isBrowsingThumbnails || isAdjusting) {
            return@LaunchedEffect
        }
        if (scrubbing != null) return@LaunchedEffect
        delay(CHROME_TIMEOUT_MILLIS)
        onHide()
    }
}

@Composable
internal fun MemoryPressureEffect(viewModel: ReaderViewModel, scope: CoroutineScope, readingPage: () -> Int) {
    // `comic-reader`: the prefetch window narrows "under memory pressure rather than the
    // app being terminated". Android reports pressure through the context's component
    // callbacks and never reports it lifting, so the all-clear is tied to the reader
    // coming back to the foreground instead — see `noteMemoryPressure`.
    val context = LocalContext.current
    DisposableEffect(context, viewModel) {
        val callbacks = object : ComponentCallbacks2 {
            override fun onTrimMemory(level: Int) {
                scope.launch { viewModel.noteMemoryPressure(trimPressure(level), at = readingPage()) }
            }

            override fun onConfigurationChanged(newConfig: Configuration) = Unit

            @Deprecated("Superseded by onTrimMemory, and still called on older systems.")
            override fun onLowMemory() {
                scope.launch {
                    viewModel.noteMemoryPressure(MemoryPressure.CRITICAL, at = readingPage())
                }
            }
        }
        context.registerComponentCallbacks(callbacks)
        onDispose { context.unregisterComponentCallbacks(callbacks) }
    }
    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) {
        scope.launch { viewModel.noteMemoryPressure(MemoryPressure.NORMAL, at = readingPage()) }
    }
}

private const val CHROME_TIMEOUT_MILLIS = 4_000L
