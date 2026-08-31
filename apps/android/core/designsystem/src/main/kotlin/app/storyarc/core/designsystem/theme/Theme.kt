package app.storyarc.core.designsystem.theme

import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ColorScheme
import androidx.compose.material3.MaterialExpressiveTheme
import androidx.compose.material3.MotionScheme
import androidx.compose.material3.Shapes
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
import app.storyarc.core.designsystem.tokens.StoryArcRadius
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

/**
 * StoryArc's own surface, text and border roles — **the content half of the colour rule.**
 *
 * There are two colour sources in this app and they are not interchangeable. Which one a
 * screen reads is decided by what the screen *is*, not by which import was nearer:
 *
 * | Surface class | Read from |
 * | --- | --- |
 * | **Chrome** — app bars, search, navigation, sheets, dialogs, settings, the download queue | `MaterialTheme.colorScheme`. Dynamic colour in full; this is where Material You earns its keep and where the app reads as an Android app rather than a themed one. |
 * | **Content** — the cover grid's ground, a publication's hero, the reader | This palette. |
 * | **State that has to survive a wallpaper** — downloaded, offline, unread | `StoryArcColor.Status`, which is fixed and already correct. |
 *
 * The middle row is the one with a reason behind it rather than a preference: a
 * wallpaper-derived tonal wash laid across a wall of covers destroys the one thing a
 * reader is using to tell one book from another. So the artwork keeps a neutral ground
 * whatever the wallpaper is doing, and [StoryArcTheme] holds the two apart by pinning the
 * content-ground roles of whichever scheme it hands to Material — see `groundedInContent`.
 */
val LocalStoryArcPalette = staticCompositionLocalOf { StoryArcPalette.Dark }

/**
 * Material's shape scale, wired from `StoryArcRadius`.
 *
 * Until this existed the tokens described one shape scale and every Material component
 * drew another: `MaterialTheme.shapes` was never set, so a chip, a card, a sheet and a
 * dialog took M3's defaults while call sites hand-passed
 * `RoundedCornerShape(StoryArcRadius.md)` to whatever they remembered to. Setting it once
 * here is the difference between a token that documents an intention and a token that has
 * one.
 *
 * StoryArc's five chrome radii map onto Material's five slots in order. `cover` is
 * deliberately absent: 4 dp is a fact about printed stock and belongs to artwork, not to a
 * dialog. `capsule` is absent for the same kind of reason — a pill is a shape a component
 * asks for by name.
 */
internal val StoryArcShapes = Shapes(
    extraSmall = RoundedCornerShape(StoryArcRadius.sm),
    small = RoundedCornerShape(StoryArcRadius.md),
    medium = RoundedCornerShape(StoryArcRadius.lg),
    large = RoundedCornerShape(StoryArcRadius.xl),
    extraLarge = RoundedCornerShape(StoryArcRadius.sheet),
)

/**
 * The scheme with its content-ground roles held to StoryArc's neutrals.
 *
 * The chrome/content split described on [LocalStoryArcPalette] cannot be left to each
 * screen to remember, because the one screen that forgets is the one with the covers on
 * it. `background` is what a `Scaffold` paints behind everything by default, so it is the
 * ground artwork sits on, and it is pinned here — along with the text drawn on it and the
 * scrim drawn over it. Every other role stays exactly as it arrived, which for a dynamic
 * scheme means the whole of Material You reaches the chrome untouched.
 *
 * Applied to the brand schemes as well as the dynamic one. It changes nothing there —
 * they already carry these values — and one code path that is occasionally a no-op is
 * worth more than a branch that has to be kept true.
 */
internal fun ColorScheme.groundedInContent(palette: StoryArcPalette): ColorScheme = copy(
    background = palette.surfaceCanvas,
    onBackground = palette.textPrimary,
    scrim = palette.scrim,
)


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
    /**
     * Whether Natural is on. A second axis rather than a fifth appearance — see
     * [NaturalTheme] — read here by default so no call site has to pass it, and a
     * parameter so a preview or a test can set it without touching stored preferences.
     */
    natural: Boolean = rememberNaturalTheme().value,
    content: @Composable () -> Unit,
) {
    val darkTheme = when (appearance) {
        AppearanceMode.SYSTEM -> isSystemInDarkTheme()
        AppearanceMode.LIGHT -> false
        AppearanceMode.DARK, AppearanceMode.OLED_DARK -> true
    }

    // Natural crosses light and dark rather than replacing either, which is what
    // "carries its own light and dark variants" means. OLED Dark declines it.
    val isNatural = NaturalTheme.applies(natural, appearance)

    val base = when {
        appearance.isTrueBlack -> StoryArcPalette.OledDark
        isNatural -> if (darkTheme) StoryArcPalette.NaturalDark else StoryArcPalette.NaturalLight
        darkTheme -> StoryArcPalette.Dark
        else -> StoryArcPalette.Light
    }

    // `native-experience`: Increase Contrast strengthens borders. Read once, here, so
    // every screen below inherits the answer rather than each one asking the system and
    // deciding for itself what to do about it.
    val isHighContrast = rememberHighContrast()
    val palette = if (isHighContrast) base.strengthened() else base

    val context = LocalContext.current
    val chrome = when {
        // Dynamic colour and true black are incompatible asks: Material You derives its
        // surfaces from the wallpaper, and a wallpaper-tinted "true black" is neither.
        // The explicit choice wins over the automatic one.
        appearance.isTrueBlack -> brandOledDarkScheme()
        // And Natural is incompatible with it for the same shape of reason: a
        // wallpaper-derived wash beside a clay accent is not a coherent theme, and
        // `design.md` asks Natural's accents to reach the whole app precisely so it is.
        isNatural -> if (darkTheme) naturalDarkScheme() else naturalLightScheme()
        useDynamicColor && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S ->
            if (darkTheme) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
        darkTheme -> brandDarkScheme()
        else -> brandLightScheme()
    }

    // Dynamic colour dresses the chrome; the ground under the artwork stays StoryArc's.
    // The rule and its reason are on `LocalStoryArcPalette`.
    val colorScheme = chrome.groundedInContent(palette).let {
        // Material's own subtle outline goes the same way as StoryArc's, so a divider
        // drawn by a Material component is strengthened too.
        if (isHighContrast) it.copy(outlineVariant = it.outline) else it
    }

    CompositionLocalProvider(
        LocalStoryArcPalette provides palette,
        // `settings-and-about`: Natural's grain reaches reading surfaces and nothing
        // else, so what travels down the tree is the *permission*, not the texture. The
        // reader asks for it; the shelf and the settings list never do.
        LocalIsNaturalTheme provides isNatural,
    ) {
        MaterialExpressiveTheme(
            colorScheme = colorScheme,
            // The Expressive scheme is the recommended default and is what makes
            // the app feel like Android 16 rather than a themed Material 2 app.
            motionScheme = MotionScheme.expressive(),
            shapes = StoryArcShapes,
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
