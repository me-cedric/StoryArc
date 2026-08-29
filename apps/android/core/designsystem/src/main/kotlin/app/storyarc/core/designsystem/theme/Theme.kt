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
import app.storyarc.core.model.AppearanceMode

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
    /**
     * The same palette with the roles Increase Contrast asks to strengthen.
     *
     * `native-experience`: with the setting on, "borders are strengthened". This is
     * where that happens — once, in the tokens, rather than in each view deciding for
     * itself what "stronger" means and half of them forgetting.
     *
     * Two roles move, and no colour is invented: the subtle border becomes the strong
     * one, and the tertiary text tier steps up to secondary. Secondary deliberately does
     * *not* step up to primary — with three tiers, promoting both would leave one tier,
     * and a hierarchy flattened to nothing is not more legible.
     */
    fun strengthened(): StoryArcPalette = copy(
        borderSubtle = borderStrong,
        textTertiary = textSecondary,
    )

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

        /**
         * True black chrome, with the reader surface deliberately above it.
         *
         * Every value comes from the generated `oledDark` tokens, including the reader
         * surface that refuses to be `#000` — the reason is in `color.json` and not
         * repeated here, because a reason in two places drifts.
         */
        val OledDark = StoryArcPalette(
            surfaceCanvas = StoryArcColor.OledDark.surfaceCanvas,
            surfaceRaised = StoryArcColor.OledDark.surfaceRaised,
            surfaceOverlay = StoryArcColor.OledDark.surfaceOverlay,
            surfaceReader = StoryArcColor.OledDark.surfaceReader,
            surfaceSunken = StoryArcColor.OledDark.surfaceSunken,
            borderSubtle = StoryArcColor.OledDark.borderSubtle,
            borderStrong = StoryArcColor.OledDark.borderStrong,
            textPrimary = StoryArcColor.OledDark.textPrimary,
            textSecondary = StoryArcColor.OledDark.textSecondary,
            textTertiary = StoryArcColor.OledDark.textTertiary,
            scrim = StoryArcColor.OledDark.scrim,
            accent = StoryArcColor.Brand.ember,
            accentMuted = StoryArcColor.Brand.emberMuted,
        )
    }
}

val LocalStoryArcPalette = staticCompositionLocalOf { StoryArcPalette.Dark }


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

private fun brandOledDarkScheme() = darkColorScheme(
    primary = StoryArcColor.Brand.ember,
    onPrimary = StoryArcColor.OledDark.surfaceCanvas,
    secondary = StoryArcColor.Brand.ink,
    background = StoryArcColor.OledDark.surfaceCanvas,
    onBackground = StoryArcColor.OledDark.textPrimary,
    surface = StoryArcColor.OledDark.surfaceRaised,
    onSurface = StoryArcColor.OledDark.textPrimary,
    onSurfaceVariant = StoryArcColor.OledDark.textSecondary,
    outline = StoryArcColor.OledDark.borderStrong,
    outlineVariant = StoryArcColor.OledDark.borderSubtle,
    error = StoryArcColor.Status.danger,
    scrim = StoryArcColor.OledDark.scrim,
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
        AppearanceMode.DARK, AppearanceMode.OLED_DARK -> true
    }

    val context = LocalContext.current
    val colorScheme = when {
        // Dynamic colour and true black are incompatible asks: Material You derives its
        // surfaces from the wallpaper, and a wallpaper-tinted "true black" is neither.
        // The explicit choice wins over the automatic one.
        appearance.isTrueBlack -> brandOledDarkScheme()
        useDynamicColor && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S ->
            if (darkTheme) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
        darkTheme -> brandDarkScheme()
        else -> brandLightScheme()
    }

    val base = when {
        appearance.isTrueBlack -> StoryArcPalette.OledDark
        darkTheme -> StoryArcPalette.Dark
        else -> StoryArcPalette.Light
    }

    // `native-experience`: Increase Contrast strengthens borders. Read once, here, so
    // every screen below inherits the answer rather than each one asking the system and
    // deciding for itself what to do about it.
    val isHighContrast = rememberHighContrast()
    val palette = if (isHighContrast) base.strengthened() else base

    CompositionLocalProvider(LocalStoryArcPalette provides palette) {
        MaterialExpressiveTheme(
            // Material's own subtle outline goes the same way as StoryArc's, so a
            // divider drawn by a Material component is strengthened too.
            colorScheme = if (isHighContrast) {
                colorScheme.copy(outlineVariant = colorScheme.outline)
            } else {
                colorScheme
            },
            // The Expressive scheme is the recommended default and is what makes
            // the app feel like Android 16 rather than a themed Material 2 app.
            motionScheme = MotionScheme.expressive(),
            typography = StoryArcTypography,
            content = content,
        )
    }
}

/**
 * The appearance the device is actually showing.
 *
 * `SYSTEM` is a question rather than a value, and anything that has to *map* an appearance
 * to something else — a reading preset, a palette — needs the answer instead. Resolved from
 * a `Configuration` rather than from a composable, so a view model can ask too.
 */
fun AppearanceMode.resolved(configuration: android.content.res.Configuration): AppearanceMode =
    if (this != AppearanceMode.SYSTEM) {
        this
    } else if (
        configuration.uiMode and android.content.res.Configuration.UI_MODE_NIGHT_MASK ==
        android.content.res.Configuration.UI_MODE_NIGHT_YES
    ) {
        AppearanceMode.DARK
    } else {
        AppearanceMode.LIGHT
    }
