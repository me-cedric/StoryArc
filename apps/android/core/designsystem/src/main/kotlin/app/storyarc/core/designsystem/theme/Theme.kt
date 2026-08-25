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

/** What the user chose in Settings › Appearance. */
/**
 * What the reader chose in Settings › Appearance.
 *
 * `settings-and-about` requires System, Light, Dark and OLED Dark, defaulting to
 * System, applied without a restart. Reading themes are deliberately independent of
 * this — a dark chrome with a paper-white page is a legitimate preference, and the spec
 * says so.
 *
 * Natural is deliberately *not* a case. The spec calls it "a theme rather than an
 * appearance… carries its own light and dark variants", so it sits alongside this
 * polarity rather than inside it. Putting it here would force a choice between Natural
 * and dark mode that the spec exists to avoid.
 */
enum class AppearanceMode {
    SYSTEM,
    LIGHT,
    DARK,

    /**
     * True black chrome, for OLED panels where black draws no power.
     *
     * The reader surface stays *above* true black even here. Pure black smears on OLED
     * during a page turn, which is the exact motion this app is built around — so the
     * setting is honoured where it helps and the palette declines it where it does not.
     * The generated `oledDark` tokens carry that decision, not this type.
     */
    OLED_DARK,
    ;

    /** Whether this appearance wants the true-black palette rather than the warm one. */
    val isTrueBlack: Boolean get() = this == OLED_DARK
}

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

    val palette = when {
        appearance.isTrueBlack -> StoryArcPalette.OledDark
        darkTheme -> StoryArcPalette.Dark
        else -> StoryArcPalette.Light
    }

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
