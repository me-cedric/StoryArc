package app.storyarc.core.designsystem.theme

import android.app.UiModeManager
import android.content.Context
import android.database.ContentObserver
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext

/**
 * Whether a system contrast value asks for the strengthened palette.
 *
 * `UiModeManager.getContrast` reports a float, and the settings screen offers three
 * stops: standard, medium and high. Medium is already a reader saying the default is
 * not enough, so the line sits there rather than at the top of the range.
 *
 * Separated from the reading of it so there is something a unit test can hold: what the
 * device reports is the platform's business, and what StoryArc does about it is not.
 */
fun isHighContrast(contrast: Float): Boolean = contrast >= MEDIUM_CONTRAST

/** The middle of the three stops Android's own contrast setting offers. */
private const val MEDIUM_CONTRAST = 0.5f

/**
 * The system's contrast setting, kept current while the composition lives.
 *
 * `native-experience`: with Increase Contrast on, "translucent materials are replaced
 * with the opaque fallback declared in the design tokens, and borders are strengthened".
 * The strengthening belongs to the tokens, not to each view: a screen that draws
 * `borderSubtle` gets a stronger border because the palette changed, not because it
 * remembered to ask.
 *
 * Live rather than read once, because iOS gets that for free from its environment, and
 * a reader turning the setting on to see whether it helps should not have to relaunch
 * the app to find out.
 */
@Composable
fun rememberHighContrast(): Boolean {
    val context = LocalContext.current
    var isOn by remember(context) { mutableStateOf(systemContrast(context)) }
    DisposableEffect(context) {
        val stop = observeContrast(context) { isOn = it }
        onDispose(stop)
    }
    return isOn
}

/**
 * What the system says right now.
 *
 * Android 14 gave contrast a first-class API with three stops. Before it, the only
 * public signal is the accessibility "high contrast text" secure setting, which is a
 * flag rather than a scale — so the floor reads that and treats it as the top stop.
 */
private fun systemContrast(context: Context): Boolean =
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
        val modes = context.getSystemService(Context.UI_MODE_SERVICE) as? UiModeManager
        isHighContrast(modes?.contrast ?: 0f)
    } else {
        Settings.Secure.getInt(context.contentResolver, HIGH_TEXT_CONTRAST, 0) == 1
    }

/** Reports changes to [report] until the returned function is called. */
private fun observeContrast(context: Context, report: (Boolean) -> Unit): () -> Unit {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
        val modes = context.getSystemService(Context.UI_MODE_SERVICE) as? UiModeManager
            ?: return {}
        val listener = UiModeManager.ContrastChangeListener { contrast ->
            report(isHighContrast(contrast))
        }
        modes.addContrastChangeListener(context.mainExecutor, listener)
        return { modes.removeContrastChangeListener(listener) }
    }
    val resolver = context.contentResolver
    val observer = object : ContentObserver(Handler(Looper.getMainLooper())) {
        override fun onChange(selfChange: Boolean) {
            report(systemContrast(context))
        }
    }
    resolver.registerContentObserver(
        Settings.Secure.getUriFor(HIGH_TEXT_CONTRAST),
        false,
        observer,
    )
    return { resolver.unregisterContentObserver(observer) }
}

/**
 * The accessibility flag Android 12 and 13 have instead of a contrast scale.
 *
 * A literal because the platform never made the constant public. Reading an unknown
 * secure setting is defined to return the default, so a device that does not carry this
 * one reports standard contrast rather than throwing.
 */
private const val HIGH_TEXT_CONTRAST = "high_text_contrast_enabled"
