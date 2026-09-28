package app.storyarc.feature.epubreader

import android.content.ContentResolver
import android.provider.Settings
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import kotlin.math.roundToInt

/**
 * The system's own screen brightness, 0…1, read once for the value a reader has not
 * yet overridden to state.
 *
 * The window attribute this screen sets uses `BRIGHTNESS_OVERRIDE_NONE` to mean
 * "follow the device" (`EpubReaderActivity.kt`), which carries no number a label
 * could show. `Settings.System.SCREEN_BRIGHTNESS` is the device's own value, 0…255,
 * and is readable without a permission. A device that has never set it (or refuses
 * the read) states the middle of the range rather than nothing.
 */
internal fun systemBrightnessFraction(resolver: ContentResolver): Float {
    return try {
        (Settings.System.getInt(resolver, Settings.System.SCREEN_BRIGHTNESS) / 255f)
            .coerceIn(0f, 1f)
    } catch (e: Settings.SettingNotFoundException) {
        0.5f
    }
}

/**
 * `reading-themes`: reader-local, and it does not permanently move the device's own.
 * On Android the value is a window attribute, so leaving reverts it by itself.
 *
 * Its own file because `ThemeAxesScreen.kt` is at the 800-line cap (`AGENTS.md` §5).
 *
 * The stated percentage and the thumb read the same value — the reader's own choice,
 * or the device's current level while the reader has not moved the slider yet — so
 * they cannot disagree. Before this, the label said 50% while the thumb sat at the
 * device's real level.
 */
@Composable
internal fun BrightnessControl(
    brightness: Float?,
    onChange: (Float) -> Unit,
    modifier: Modifier = Modifier,
) {
    val palette = LocalStoryArcPalette.current
    val resolver = LocalContext.current.contentResolver
    val inForce = brightness ?: systemBrightnessFraction(resolver)

    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(StoryArcSpace.sm)) {
        Text(
            text = stringResource(R.string.theme_brightness),
            style = MaterialTheme.typography.titleMedium,
            color = palette.textPrimary,
        )
        val percent = stringResource(
            R.string.theme_brightness_percent,
            (inForce * 100).roundToInt(),
        )
        val name = stringResource(R.string.theme_brightness)
        Slider(
            value = inForce,
            onValueChange = onChange,
            valueRange = 0.1f..1f,
            modifier = Modifier.semantics {
                contentDescription = name
                stateDescription = percent
            },
        )
    }
}
