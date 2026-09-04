package app.storyarc.core.designsystem.theme

import android.content.Context
import androidx.compose.material3.ColorScheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.MutableState
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.platform.LocalContext
import app.storyarc.core.designsystem.tokens.StoryArcColor
import app.storyarc.core.model.AppearanceMode

/**
 * Natural: the app's third appearance axis, and deliberately not a fifth
 * [AppearanceMode] entry.
 *
 * `settings-and-about` calls Natural "a theme rather than an appearance… carries its own
 * light and dark variants". Both halves of that sentence are load-bearing:
 *
 *  - **Not an entry in [AppearanceMode].** That enum is the *polarity* axis — which end
 *    of light and dark the app sits at, or that it follows the device. A fifth entry
 *    would make Natural and dark mode alternatives, which is exactly the choice the spec
 *    exists to avoid. `AppearanceTest` and iOS's `AppearanceModeTests` both assert its
 *    absence so a later hand does not helpfully add it.
 *  - **Not a reading theme either.** A `ThemePreset` reaches the page and stops there.
 *    Natural's warm accents reach the library, settings and the source list, because
 *    `design.md` decided they do: "the theme is coherent rather than bolted onto the
 *    reader".
 *
 * So it is a second axis crossed with the first: three of the four appearances × on or
 * off. System, Light and Dark each gain a Natural variant; OLED Dark does not, for the
 * reason on [isAvailable].
 *
 * ## Where the choice is stored
 *
 * Its own preference file, read by the design system rather than a field on
 * `AppSettings`. `AppSettings.appearance` answers "which polarity"; Natural answers
 * "which texture", and storing an independent axis inside the field it is independent of
 * is how a boolean ends up encoded in an enum a year later. Reading it here also leaves
 * [StoryArcTheme]'s existing call sites untouched — the parameter has a default that
 * fetches it.
 *
 * iOS stores the same choice under the same key name, in `UserDefaults`.
 */
object NaturalTheme {

    /** The key the switch is stored under. iOS uses the same string. */
    const val STORAGE_KEY: String = "storyarc.appearance.natural"

    private const val PREFERENCES = "storyarc.appearance"

    /**
     * The process-wide state, so the Appearance screen's switch and the theme above it
     * are one value rather than two copies that agree until one is written.
     *
     * Created on the first composition that asks and never replaced. Only ever touched
     * from composition, which is the main thread, so it needs no lock.
     */
    private var shared: MutableState<Boolean>? = null

    /**
     * Whether Natural can be combined with this appearance.
     *
     * False for OLED Dark alone. Warm cream stock and true black are contradictory asks,
     * and OLED Dark's whole reason is a promise about the black point on a panel — a
     * Natural canvas at `#16100C` would quietly break it. The Appearance screen therefore
     * shows the switch *disabled with the reason*, which is what it already does for
     * dynamic colour under the same appearance.
     */
    fun isAvailable(appearance: AppearanceMode): Boolean = !appearance.isTrueBlack

    /**
     * Whether Natural actually applies, given what the reader chose and where. The one
     * place the two axes are combined, so no screen has to remember that OLED Dark wins.
     */
    fun applies(isOn: Boolean, appearance: AppearanceMode): Boolean =
        isOn && isAvailable(appearance)

    /** Writes the choice through to disk and to every composition reading it. */
    fun set(context: Context, isOn: Boolean) {
        preferences(context).edit().putBoolean(STORAGE_KEY, isOn).apply()
        state(context).value = isOn
    }

    /** Reads the stored choice once per process and hands back the state that carries it. */
    internal fun state(context: Context): MutableState<Boolean> =
        shared ?: mutableStateOf(preferences(context).getBoolean(STORAGE_KEY, false))
            .also { shared = it }

    private fun preferences(context: Context) = context.applicationContext
        .getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
}

/**
 * The Natural switch, as a state every screen shares.
 *
 * Written through [NaturalTheme.set] by Settings › Appearance and read by
 * [StoryArcTheme], so a change applies "immediately across the whole app without a
 * restart" — which is what `settings-and-about` asks of an appearance, and the only
 * reason this is one shared state rather than a value each screen fetches for itself.
 */
@Composable
fun rememberNaturalTheme(): MutableState<Boolean> {
    val context = LocalContext.current
    return remember(context) { NaturalTheme.state(context) }
}

/**
 * Whether Natural is in force, for the reading surfaces that carry its grain.
 *
 * Separate from [LocalStoryArcPalette] because it is not a colour: every other screen
 * resolves Natural entirely through the palette, and only a reading surface has anything
 * more to do about it.
 */
val LocalIsNaturalTheme = staticCompositionLocalOf { false }

/**
 * Warm cream stock and an earthier accent. Natural's light variant.
 *
 * The accent is `clayStrong` for the reason `secondaryStrong` exists: clay at 66 % lightness
 * does not clear 3:1 on warm paper, exactly as the lighter pink does not. The app's own accent
 * needs no such pair — it is one violet on every appearance. `pnpm tokens:check` gates it.
 *
 * `accentMuted` is the same value rather than a `clayMuted` that does not exist. Its only
 * reader is the settings-search highlight, which draws it at a low alpha, and inventing a
 * token no contrast gate covers to serve one wash is a worse trade than an accent at rest
 * that happens to equal the accent.
 */
private val naturalLightPalette = StoryArcPalette(
    surfaceCanvas = StoryArcColor.NaturalLight.surfaceCanvas,
    surfaceRaised = StoryArcColor.NaturalLight.surfaceRaised,
    surfaceOverlay = StoryArcColor.NaturalLight.surfaceOverlay,
    surfaceReader = StoryArcColor.NaturalLight.surfaceReader,
    surfaceSunken = StoryArcColor.NaturalLight.surfaceSunken,
    borderSubtle = StoryArcColor.NaturalLight.borderSubtle,
    borderStrong = StoryArcColor.NaturalLight.borderStrong,
    textPrimary = StoryArcColor.NaturalLight.textPrimary,
    textSecondary = StoryArcColor.NaturalLight.textSecondary,
    textTertiary = StoryArcColor.NaturalLight.textTertiary,
    scrim = StoryArcColor.NaturalLight.scrim,
    accent = StoryArcColor.Brand.clayStrong,
    accentMuted = StoryArcColor.Brand.clayStrong,
)

/**
 * Warm ink and the clay accent. Natural's dark variant.
 *
 * The reader surface goes deeper than the canvas here, as it does in every other palette:
 * grain is drawn *over* the page rather than instead of it, so the colour has to stand on
 * its own wherever the texture is absent — which below API 33 is everywhere.
 */
private val naturalDarkPalette = StoryArcPalette(
    surfaceCanvas = StoryArcColor.NaturalDark.surfaceCanvas,
    surfaceRaised = StoryArcColor.NaturalDark.surfaceRaised,
    surfaceOverlay = StoryArcColor.NaturalDark.surfaceOverlay,
    surfaceReader = StoryArcColor.NaturalDark.surfaceReader,
    surfaceSunken = StoryArcColor.NaturalDark.surfaceSunken,
    borderSubtle = StoryArcColor.NaturalDark.borderSubtle,
    borderStrong = StoryArcColor.NaturalDark.borderStrong,
    textPrimary = StoryArcColor.NaturalDark.textPrimary,
    textSecondary = StoryArcColor.NaturalDark.textSecondary,
    textTertiary = StoryArcColor.NaturalDark.textTertiary,
    scrim = StoryArcColor.NaturalDark.scrim,
    accent = StoryArcColor.Brand.clay,
    accentMuted = StoryArcColor.Brand.clayStrong,
)

/** @see naturalLightPalette */
val StoryArcPalette.Companion.NaturalLight: StoryArcPalette get() = naturalLightPalette

/** @see naturalDarkPalette */
val StoryArcPalette.Companion.NaturalDark: StoryArcPalette get() = naturalDarkPalette

/**
 * The chrome scheme Natural dresses the app in.
 *
 * Natural overrides dynamic colour, for the reason OLED Dark does: a wallpaper-derived
 * tonal wash beside a clay accent is not a coherent theme, and `design.md` asks Natural's
 * accents to reach "the library, settings and source list" precisely so it is one. The
 * explicit choice wins over the automatic one, and the dynamic-colour row says so.
 */
/*
 * **`secondary` is Natural's own accent rather than a second pole, and that is a decision
 * the change artifacts did not make.** It used to be `brand.ink`, the indigo the brand and
 * Natural shared, and `ink` retires with the accent rename. Neither replacement in the new
 * token set fits: the brand's pink sits at hue 2, which is 39° from clay at hue 41 — the
 * same "one colour said twice" objection that moved the brand accent off `ink` in the first
 * place — and a hot pink is the opposite of the earthier accent Natural exists to have.
 * The other clay does not work either: read across, `clay` reaches 2.80:1 on Natural's
 * cream and `clayStrong` 2.99:1 on its ink, both under the 3:1 floor their own gated
 * pairings clear at 5.47 and 5.84.
 *
 * So each variant's `secondary` is the accent it already gates, which flattens the two
 * Material roles onto one value. That flattening turns out to be the *right* answer rather
 * than a free one: `ShortNavigationBarItemDefaults.colors()` reads `secondary` for a
 * selected navigation label — measured, not assumed — so the claim that nothing in this app
 * reads the role was already false when it was written, and it is what leaves the brand
 * schemes drawing a crimson label under a violet pill. Natural's label is its own accent,
 * matching the indicator above it. It keeps the brand change out of Natural the way
 * `design.md` asks. Giving Natural a real second pole means adding a token to `color.json` with a
 * gated pairing, and that is a decision for whoever owns the Natural theme — not one to
 * invent while renaming the brand's.
 */
internal fun naturalLightScheme(): ColorScheme = lightColorScheme(
    primary = StoryArcColor.Brand.clayStrong,
    onPrimary = StoryArcColor.NaturalLight.surfaceRaised,
    secondary = StoryArcColor.Brand.clayStrong,
    background = StoryArcColor.NaturalLight.surfaceCanvas,
    onBackground = StoryArcColor.NaturalLight.textPrimary,
    surface = StoryArcColor.NaturalLight.surfaceRaised,
    onSurface = StoryArcColor.NaturalLight.textPrimary,
    onSurfaceVariant = StoryArcColor.NaturalLight.textSecondary,
    outline = StoryArcColor.NaturalLight.borderStrong,
    outlineVariant = StoryArcColor.NaturalLight.borderSubtle,
    error = StoryArcColor.Status.danger,
    scrim = StoryArcColor.NaturalLight.scrim,
).groundedInChrome(StoryArcPalette.NaturalLight, isDark = false)

/** @see naturalLightScheme */
internal fun naturalDarkScheme(): ColorScheme = darkColorScheme(
    primary = StoryArcColor.Brand.clay,
    onPrimary = StoryArcColor.NaturalDark.surfaceCanvas,
    secondary = StoryArcColor.Brand.clay,
    background = StoryArcColor.NaturalDark.surfaceCanvas,
    onBackground = StoryArcColor.NaturalDark.textPrimary,
    surface = StoryArcColor.NaturalDark.surfaceRaised,
    onSurface = StoryArcColor.NaturalDark.textPrimary,
    onSurfaceVariant = StoryArcColor.NaturalDark.textSecondary,
    outline = StoryArcColor.NaturalDark.borderStrong,
    outlineVariant = StoryArcColor.NaturalDark.borderSubtle,
    error = StoryArcColor.Status.danger,
    scrim = StoryArcColor.NaturalDark.scrim,
).groundedInChrome(StoryArcPalette.NaturalDark, isDark = true)
