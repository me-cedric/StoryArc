package app.storyarc.core.designsystem.theme

import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.ColorScheme
import androidx.compose.material3.MaterialExpressiveTheme
import androidx.compose.material3.MotionScheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import app.storyarc.core.designsystem.tokens.StoryArcColor

/**
 * Surfaces, text and border roles for one appearance.
 *
 * Material's [ColorScheme] covers component colours; this carries the StoryArc
 * roles Material has no slot for — the reader surface, the offline indicator,
 * the tertiary text tier. Every value comes from the generated tokens.
 */
data class StoryArcPalette(
    val surfaceCanvas: Color,
    val surfaceRaised: Color,
    val surfaceOverlay: Color,
    val surfaceReader: Color,
    val surfaceSunken: Color,
    val borderSubtle: Color,
    val borderStrong: Color,
    val textPrimary: Color,
    val textSecondary: Color,
    val textTertiary: Color,
    val scrim: Color,
    val accent: Color,
    val accentMuted: Color,
) {
    companion object {
        val Dark = StoryArcPalette(
            surfaceCanvas = StoryArcColor.Dark.surfaceCanvas,
            surfaceRaised = StoryArcColor.Dark.surfaceRaised,
            surfaceOverlay = StoryArcColor.Dark.surfaceOverlay,
            surfaceReader = StoryArcColor.Dark.surfaceReader,
            surfaceSunken = StoryArcColor.Dark.surfaceSunken,
            borderSubtle = StoryArcColor.Dark.borderSubtle,
            borderStrong = StoryArcColor.Dark.borderStrong,
            textPrimary = StoryArcColor.Dark.textPrimary,
            textSecondary = StoryArcColor.Dark.textSecondary,
            textTertiary = StoryArcColor.Dark.textTertiary,
            scrim = StoryArcColor.Dark.scrim,
            accent = StoryArcColor.Brand.ember,
            accentMuted = StoryArcColor.Brand.emberMuted,
        )

        /** Light uses the stronger accent: ember at 70 % lightness fails 3:1 on paper. */
        val Light = StoryArcPalette(
            surfaceCanvas = StoryArcColor.Light.surfaceCanvas,
            surfaceRaised = StoryArcColor.Light.surfaceRaised,
            surfaceOverlay = StoryArcColor.Light.surfaceOverlay,
            surfaceReader = StoryArcColor.Light.surfaceReader,
            surfaceSunken = StoryArcColor.Light.surfaceSunken,
            borderSubtle = StoryArcColor.Light.borderSubtle,
            borderStrong = StoryArcColor.Light.borderStrong,
            textPrimary = StoryArcColor.Light.textPrimary,
            textSecondary = StoryArcColor.Light.textSecondary,
            textTertiary = StoryArcColor.Light.textTertiary,
            scrim = StoryArcColor.Light.scrim,
            accent = StoryArcColor.Brand.emberStrong,
            accentMuted = StoryArcColor.Brand.emberMuted,
        )
    }
}

val LocalStoryArcPalette = staticCompositionLocalOf { StoryArcPalette.Dark }

/** What the user chose in Settings › Appearance. */
enum class AppearanceMode { SYSTEM, LIGHT, DARK }

private fun brandDarkScheme() = darkColorScheme(
    primary = StoryArcColor.Brand.ember,
    onPrimary = StoryArcColor.Dark.surfaceCanvas,
    secondary = StoryArcColor.Brand.ink,
    background = StoryArcColor.Dark.surfaceCanvas,
    onBackground = StoryArcColor.Dark.textPrimary,
    surface = StoryArcColor.Dark.surfaceRaised,
    onSurface = StoryArcColor.Dark.textPrimary,
    onSurfaceVariant = StoryArcColor.Dark.textSecondary,
    outline = StoryArcColor.Dark.borderStrong,
    outlineVariant = StoryArcColor.Dark.borderSubtle,
    error = StoryArcColor.Status.danger,
    scrim = StoryArcColor.Dark.scrim,
)

private fun brandLightScheme() = lightColorScheme(
    primary = StoryArcColor.Brand.emberStrong,
    onPrimary = StoryArcColor.Light.surfaceRaised,
    secondary = StoryArcColor.Brand.ink,
    background = StoryArcColor.Light.surfaceCanvas,
    onBackground = StoryArcColor.Light.textPrimary,
    surface = StoryArcColor.Light.surfaceRaised,
    onSurface = StoryArcColor.Light.textPrimary,
    onSurfaceVariant = StoryArcColor.Light.textSecondary,
    outline = StoryArcColor.Light.borderStrong,
    outlineVariant = StoryArcColor.Light.borderSubtle,
    error = StoryArcColor.Status.danger,
    scrim = StoryArcColor.Light.scrim,
)

/**
 * The app theme.
 *
 * `native-experience` requires Material You by default where the platform
 * offers it, with a setting to fall back to the StoryArc palette. ADR-0003 puts
 * the floor at API 31 precisely so this branch never needs a third path.
 */
@Composable
fun StoryArcTheme(
    appearance: AppearanceMode = AppearanceMode.SYSTEM,
    useDynamicColor: Boolean = true,
    content: @Composable () -> Unit,
) {
    val darkTheme = when (appearance) {
        AppearanceMode.SYSTEM -> isSystemInDarkTheme()
        AppearanceMode.LIGHT -> false
        AppearanceMode.DARK -> true
    }

    val context = LocalContext.current
    val colorScheme = when {
        useDynamicColor && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S ->
            if (darkTheme) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
        darkTheme -> brandDarkScheme()
        else -> brandLightScheme()
    }

    val palette = if (darkTheme) StoryArcPalette.Dark else StoryArcPalette.Light

    CompositionLocalProvider(LocalStoryArcPalette provides palette) {
        MaterialExpressiveTheme(
            colorScheme = colorScheme,
            // The Expressive scheme is the recommended default and is what makes
            // the app feel like Android 16 rather than a themed Material 2 app.
            motionScheme = MotionScheme.expressive(),
            typography = StoryArcTypography,
            content = content,
        )
    }
}
