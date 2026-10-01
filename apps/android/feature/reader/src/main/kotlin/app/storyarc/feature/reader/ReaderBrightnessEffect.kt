package app.storyarc.feature.reader

import android.view.WindowManager
import androidx.activity.compose.LocalActivity
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect

/**
 * Reader-local screen brightness, as a window attribute rather than the system setting.
 *
 * `reading-themes`, *Brightness is reader-local*: "the change applies while the reader is
 * open and is reverted on leaving it" and "the system brightness is not permanently
 * modified". `EpubReaderActivity` gets the second half for free -- its window dies with its
 * own activity -- because it writes exactly this same `screenBrightness` attribute. The
 * comic reader is a destination inside the one shared activity, so its window outlives the
 * screen, and [onDispose] is what [ReaderScreen] gets the same guarantee from.
 *
 * `BRIGHTNESS_OVERRIDE_NONE` is "no override, follow the system" rather than a captured
 * value: unlike `UIScreen.main.brightness`, a window attribute never moves the *device's*
 * brightness, so there is nothing of the system's own to capture or put back -- only this
 * window's override to clear.
 */
@Composable
internal fun ReaderBrightnessEffect(brightness: Float?) {
    val window = LocalActivity.current?.window ?: return

    DisposableEffect(window) {
        onDispose {
            window.attributes = window.attributes.apply {
                screenBrightness = WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE
            }
        }
    }

    LaunchedEffect(window, brightness) {
        window.attributes = window.attributes.apply {
            screenBrightness = brightness ?: WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE
        }
    }
}
