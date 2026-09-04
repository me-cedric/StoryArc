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
            accent = StoryArcColor.Brand.accent,
            accentMuted = StoryArcColor.Brand.accentMuted,
        )

        /**
         * Light carries **the same accent as dark**, which is why the brand's accent is
         * the violet from the middle of the mark's arc rather than the pink at its first
         * stop: `brand.accent` clears 3:1 on both canvases — 4.06 dark, 4.43 light —
         * where the pink reaches 2.48 on paper. The light-only variant this used to need
         * is absent rather than forgotten. iOS's `Palette` asserts the same wiring.
         */
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
            accent = StoryArcColor.Brand.accent,
            accentMuted = StoryArcColor.Brand.accentMuted,
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
            accent = StoryArcColor.Brand.accent,
            accentMuted = StoryArcColor.Brand.accentMuted,
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

/**
 * Every ground a Material component can draw itself on, held to a StoryArc surface.
 *
 * **The second half of the same hole [brandDarkScheme] describes, and by area the larger
 * one.** A scheme built by [darkColorScheme] or [lightColorScheme] fills every omitted role
 * from Material's baseline palette, and the roles nobody had set included the whole
 * `surfaceContainer` family. Measured off the sweep of 2026-09-02 rather than reasoned
 * about — `android-library-selection-two-nodynamic.png` reads `#F3EDF7` in the navigation
 * band against a page of `#F8F6F4`, and `android-comic-menu-nodynamic-dark.png` reads
 * `#1D1B20` in the sheet against an app surface of `#1A1815`. Both are Material's own
 * lavender greys, drawn on the path a reader takes with Material You **off**.
 *
 * That is every sheet, every dialog, every menu and the navigation bar. Asked of the real
 * defaults rather than assumed, in `ChromeGroundsAreStoryArcsTest`:
 *
 * | Drawn by | Role |
 * | --- | --- |
 * | `ModalBottomSheet` | `surfaceContainerLow` |
 * | `DropdownMenu`, `ShortNavigationBar`, a scrolled `TopAppBar` | `surfaceContainer` |
 * | `AlertDialog` | `surfaceContainerHigh` |
 * | `Card` | `surfaceContainerHighest` |
 *
 * **No colour is invented, because the token file already names this mapping.** `raised` is
 * documented as "cards, list rows, sheets", `overlay` as "menus, popovers", `sunken` as
 * "inset wells", `canvas` as the app background. Menus take `raised` rather than `overlay`
 * for the one reason a mapping has to break its own vocabulary: a menu and the navigation
 * bar read the *same* role, and a bar sitting a whole step above the page is what the
 * baseline was doing right.
 *
 * **Applied to the brand and Natural schemes, never to the dynamic one.** `native-experience`
 * asks for Material You where the platform offers it, so a wallpaper scheme keeps its own
 * containers in full; these functions are the branch a reader reaches by turning it off, and
 * the only branch OLED Dark and Natural ever have.
 *
 * @param isDark which way "brighter" runs. It is the one thing that cannot be read off the
 *   palette: `surfaceBright` is the lightest surface on paper and the lightest surface on
 *   black, and those are not the same token.
 */
internal fun ColorScheme.groundedInChrome(
    palette: StoryArcPalette,
    isDark: Boolean,
): ColorScheme = copy(
    surfaceVariant = palette.surfaceSunken,
    surfaceDim = palette.surfaceSunken,
    surfaceBright = if (isDark) palette.surfaceOverlay else palette.surfaceRaised,
    // Level with the page. Nothing in the app draws it today; it is set so that the
    // component which one day does cannot fall back to lavender on its own.
    surfaceContainerLowest = palette.surfaceCanvas,
    surfaceContainerLow = palette.surfaceRaised,
    surfaceContainer = palette.surfaceRaised,
    surfaceContainerHigh = palette.surfaceOverlay,
    surfaceContainerHighest = palette.surfaceOverlay,
)


/**
 * The StoryArc palette dressed as a Material scheme, for a reader who turned Material You
 * off — and for the two appearances that decline it outright.
 *
 * **`onPrimary` is a light value on all three, and that is a consequence of the accent
 * moving rather than a preference.** The accent it replaced sat at 70 % lightness, so a
 * near-black label on a filled button measured 6.91:1. `brand.accent` sits at 58 %, and
 * the same near-black label measures **4.06:1** — under WCAG's 4.5 floor for normal text.
 * Nothing in the token set clears 4.5 on this violet except pure white, at 4.77:1, so
 * that is what a label drawn on the accent is. `ACCENT_PAIRS` in the token build gates
 * the pair, so this cannot quietly go back.
 *
 * **`secondaryContainer` is set because leaving it unset was the whole of the design
 * review's fourth item, and the design document's account of that item was incomplete.**
 * `brand-identity-and-app-icons`' design.md answers the review's "Android runs blue/purple"
 * with "the purple was the wallpaper" — true of the screenshot the reviewer was looking at,
 * and not the whole story. A scheme built by [darkColorScheme] fills every role the caller
 * omits from **Material's baseline palette**, which is lavender. So with dynamic colour
 * *off* — the path that document correctly identifies as the one to fix — this app still
 * drew `#4A4458` and `#E8DEF8`, Material's own tones, in the roles below.
 *
 * That mattered far more than one role usually would, because of what reads it. Measured
 * against `MaterialExpressiveTheme(colorScheme = brandDarkScheme())` rather than assumed —
 * `AccentReachesTheControlsTest` is that measurement, kept:
 *
 * | Drawn by | Read from |
 * | --- | --- |
 * | A selected `FilterChip`'s container, and its label | `secondaryContainer` / `onSecondaryContainer` |
 * | `NavigationBar`'s selected indicator, and its icon | `secondaryContainer` / `onSecondaryContainer` |
 * | `Slider`'s inactive track | `secondaryContainer` |
 * | `LinearProgressIndicator`'s and `CircularProgressIndicator`'s track | `secondaryContainer` |
 *
 * **Tab bars, chips, sliders and progress ticks** — the four control kinds the review named,
 * one for one, and they are four faces of a single role nobody had set. The accent already
 * reached the *active* half of the last two through `primary`; what stayed Material's was
 * everything at rest and everything selected.
 *
 * The value is `brand.accentMuted`, whose role in design.md's own token table is **"rails at
 * rest"** — a slider track and a progress track are exactly that, and a selected chip or a
 * navigation indicator is the same muted violet doing a container's job.
 *
 * **One value across all three appearances, for the reason the accent itself is one value.**
 * A light theme conventionally wants a pale tint here with dark text on it, and no such
 * tint exists in the token set; inventing one means a new token with a gated pairing in
 * `packages/design-tokens`, which is a decision for whoever owns the palette rather than one
 * to make while wiring it. So a selected chip and the navigation indicator are *filled*
 * rather than tinted on paper, `onSecondaryContainer` is the same near-white every label on
 * the accent uses, and the pair measures **7.76:1** — one calculation that holds on every
 * canvas instead of two that have to be kept true.
 *
 * **Dynamic colour is untouched.** These functions are the `useDynamicColor == false` branch
 * of [StoryArcTheme]; `dynamicDarkColorScheme` and `dynamicLightColorScheme` still return
 * the reader's wallpaper scheme in full, which `native-experience` requires. Fixing the
 * brand by taking Material You away would be trading a requirement for a tidier screenshot.
 */
internal fun brandDarkScheme() = darkColorScheme(
    primary = StoryArcColor.Brand.accent,
    onPrimary = StoryArcColor.Light.surfaceRaised,
    secondary = StoryArcColor.Brand.secondary,
    secondaryContainer = StoryArcColor.Brand.accentMuted,
    onSecondaryContainer = StoryArcColor.Light.surfaceRaised,
    background = StoryArcColor.Dark.surfaceCanvas,
    onBackground = StoryArcColor.Dark.textPrimary,
    surface = StoryArcColor.Dark.surfaceRaised,
    onSurface = StoryArcColor.Dark.textPrimary,
    onSurfaceVariant = StoryArcColor.Dark.textSecondary,
    outline = StoryArcColor.Dark.borderStrong,
    outlineVariant = StoryArcColor.Dark.borderSubtle,
    error = StoryArcColor.Status.danger,
    scrim = StoryArcColor.Dark.scrim,
).groundedInChrome(StoryArcPalette.Dark, isDark = true)

/**
 * See [brandDarkScheme] for why `onPrimary` is light rather than the canvas, and for what
 * `secondaryContainer` reaches — this appearance declines dynamic colour outright, so these
 * are the only values a reader on true black ever sees.
 */
internal fun brandOledDarkScheme() = darkColorScheme(
    primary = StoryArcColor.Brand.accent,
    onPrimary = StoryArcColor.Light.surfaceRaised,
    secondary = StoryArcColor.Brand.secondary,
    secondaryContainer = StoryArcColor.Brand.accentMuted,
    onSecondaryContainer = StoryArcColor.Light.surfaceRaised,
    background = StoryArcColor.OledDark.surfaceCanvas,
    onBackground = StoryArcColor.OledDark.textPrimary,
    surface = StoryArcColor.OledDark.surfaceRaised,
    onSurface = StoryArcColor.OledDark.textPrimary,
    onSurfaceVariant = StoryArcColor.OledDark.textSecondary,
    outline = StoryArcColor.OledDark.borderStrong,
    outlineVariant = StoryArcColor.OledDark.borderSubtle,
    error = StoryArcColor.Status.danger,
    scrim = StoryArcColor.OledDark.scrim,
).groundedInChrome(StoryArcPalette.OledDark, isDark = true)

/**
 * Light takes **the same `primary` as dark** — one accent, both appearances, which is the
 * whole reason the brand's accent is the violet from the middle of the mark's arc.
 *
 * `secondary` is the one role that still needs a pair: the pink at 72 % lightness reaches
 * 2.48:1 on paper, so light takes `secondaryStrong` at 3.72:1 while the dark schemes take
 * `secondary` at 7.24:1. Both are gated.
 */
internal fun brandLightScheme() = lightColorScheme(
    primary = StoryArcColor.Brand.accent,
    onPrimary = StoryArcColor.Light.surfaceRaised,
    secondary = StoryArcColor.Brand.secondaryStrong,
    // The same pair as the two dark schemes, on purpose. See [brandDarkScheme]: the light
    // tint this role conventionally wants does not exist in the token set, and adding one is
    // a palette decision rather than a wiring one.
    secondaryContainer = StoryArcColor.Brand.accentMuted,
    onSecondaryContainer = StoryArcColor.Light.surfaceRaised,
    background = StoryArcColor.Light.surfaceCanvas,
    onBackground = StoryArcColor.Light.textPrimary,
    surface = StoryArcColor.Light.surfaceRaised,
    onSurface = StoryArcColor.Light.textPrimary,
    onSurfaceVariant = StoryArcColor.Light.textSecondary,
    outline = StoryArcColor.Light.borderStrong,
    outlineVariant = StoryArcColor.Light.borderSubtle,
    error = StoryArcColor.Status.danger,
    scrim = StoryArcColor.Light.scrim,
).groundedInChrome(StoryArcPalette.Light, isDark = false)

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
