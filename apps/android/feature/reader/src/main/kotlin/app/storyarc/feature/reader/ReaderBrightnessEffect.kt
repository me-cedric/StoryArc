package app.storyarc.feature.reader

import android.content.ContentResolver
import android.provider.Settings
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

/**
 * The brightness the slider shows: the reader's own, or the device's level until they move it.
 *
 * `BRIGHTNESS_OVERRIDE_NONE` carries no number a slider could show, so the device's own
 * value, 0…255 and readable without a permission, stands in. A device that refuses the read
 * states the middle of the range. A mirror of `systemBrightnessFraction` in
 * `feature:epubreader`, which is a peer module.
 */
internal fun brightnessInForce(chosen: Float?, resolver: ContentResolver): Float =
    chosen ?: try {
        (Settings.System.getInt(resolver, Settings.System.SCREEN_BRIGHTNESS) / 255f)
            .coerceIn(0f, 1f)
    } catch (e: Settings.SettingNotFoundException) {
        0.5f
    }
