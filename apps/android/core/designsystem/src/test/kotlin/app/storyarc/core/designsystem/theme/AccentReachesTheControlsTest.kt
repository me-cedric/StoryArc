package app.storyarc.core.designsystem.theme

import androidx.compose.material3.ColorScheme
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.MaterialExpressiveTheme
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.ProgressIndicatorDefaults
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.test.junit4.v2.createComposeRule
import app.storyarc.core.designsystem.tokens.StoryArcColor
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * The four control kinds the 2026-09-01 design review named — **tab bars, chips, sliders and
 * progress ticks** — draw the brand's accent family and not Material's own, on the path a
 * reader takes with dynamic colour off.
 *
 * `brand-identity-and-app-icons` §1.7 asks for exactly those four, on the argument that "the
 * compiler finds the token rename; it does not find a surface that was never accented". This
 * is that surface, and there turned out to be **one** of it rather than four.
 *
 * ## What was actually wrong, which is not quite what the design document says
 *
 * design.md answers the review's "Android runs blue/purple" with "the purple was the
 * wallpaper" — `Theme.kt` calls `dynamicDarkColorScheme` by default, so on a Material You
 * device the scheme comes from the reader's wallpaper, which `native-experience` asks for by
 * name. That is right about the screenshot the reviewer was looking at, and it is not the
 * whole account.
 *
 * `darkColorScheme()` and `lightColorScheme()` fill **every role the caller omits** from
 * Material's baseline palette, which is lavender. The brand schemes set eleven roles and
 * omitted the rest, so with dynamic colour *off* the app still drew Material's `#4A4458` and
 * `#E8DEF8`. The purple was the wallpaper **and** the baseline, from two independent causes,
 * and only the second one is this project's to fix.
 *
 * ## Why one role was the whole of it
 *
 * Measured against `MaterialExpressiveTheme(colorScheme = brandDarkScheme())` — every
 * assertion below reads a Material default rather than restating one — all four control kinds
 * converge on `secondaryContainer`:
 *
 * - a selected `FilterChip`'s container, and its label from `onSecondaryContainer`;
 * - `NavigationBar`'s selected indicator, and its icon from `onSecondaryContainer`;
 * - `Slider`'s inactive track;
 * - the linear and circular progress indicators' tracks.
 *
 * The accent already reached the *active* half of a slider and a progress bar through
 * `primary`. What stayed Material's was everything at rest and everything selected — and a
 * navigation bar in which the selected label was the brand's pink, the indicator behind it
 * Material's lavender, and the icon on that a third family again.
 *
 * ## Why this test reads the defaults instead of asserting the scheme
 *
 * `BrandSchemeTest` asserts the wiring: that `secondaryContainer` is `brand.accentMuted`.
 * That is necessary and it is not sufficient, because it would keep passing on the day a
 * material3 upgrade moves a chip's selected container to `primaryContainer` or a slider's
 * rail to `surfaceContainerHighest`. The app would quietly go back to lavender in one of the
 * four places and every colour test in the module would still be green.
 *
 * So this file composes the real theme and asks the real `FilterChipDefaults`,
 * `NavigationBarItemDefaults`, `SliderDefaults` and `ProgressIndicatorDefaults` what they
 * resolved to. It is pinned to material3 **1.5.0-alpha**, which `apps/android/README.md`
 * already records as a known risk; when that pin moves and one of these fails, the failure is
 * the news rather than the nuisance.
 *
 * Natural is deliberately **not** covered. Its schemes have the identical hole — a clay accent
 * beside Material's lavender containers — and closing it means choosing a clay-family value
 * with a gated pairing, which belongs to whoever owns that theme.
 */
@RunWith(RobolectricTestRunner::class)
// Robolectric ships an image per API level and has none for 37. 34 is inside its range and
// above this app's minimum, and which colour a Material default resolves to has no API level
// in it — the dynamic-colour branch this file never touches is the only part that would.
@Config(sdk = [34])
class AccentReachesTheControlsTest {

    @get:Rule
    val compose = createComposeRule()

    @Test
    fun `a selected chip is the accent family, not Material's`() = underBrandDark {
        val chip = FilterChipDefaults.filterChipColors()
        assertIsAccentContainer("a selected chip's container", chip.selectedContainerColor)
        assertIsOnAccentContainer("a selected chip's label", chip.selectedLabelColor)
    }

    @Test
    fun `the navigation bar's selected item is the accent family, not Material's`() =
        underBrandDark {
            val nav = NavigationBarItemDefaults.colors()
            assertIsAccentContainer("the navigation indicator", nav.selectedIndicatorColor)
            assertIsOnAccentContainer("the selected navigation icon", nav.selectedIconColor)
        }

    @Test
    fun `a slider is the accent at both ends of its travel`() = underBrandDark {
        val slider = SliderDefaults.colors()
        // The active half already came from `primary` before this change. Asserted anyway:
        // half a control in the brand and half in Material's is the state this fixes, and a
        // test that only watched the half that was wrong would not notice the other half
        // going wrong later.
        assertEquals(
            "a slider's active track", StoryArcColor.Brand.accent, slider.activeTrackColor,
        )
        assertEquals("a slider's thumb", StoryArcColor.Brand.accent, slider.thumbColor)
        assertIsAccentContainer("a slider's rail at rest", slider.inactiveTrackColor)
    }

    @Test
    fun `a progress tick is the accent and runs on an accent rail`() = underBrandDark {
        assertEquals(
            "a progress indicator's fill",
            StoryArcColor.Brand.accent,
            ProgressIndicatorDefaults.linearColor,
        )
        assertIsAccentContainer(
            "a linear progress track", ProgressIndicatorDefaults.linearTrackColor,
        )
        assertIsAccentContainer(
            "a circular progress track",
            ProgressIndicatorDefaults.circularDeterminateTrackColor,
        )
    }

    @Test
    fun `the same holds on paper and on true black`() {
        // The three brand schemes are three call sites of the same wiring, and the one that
        // matters most is the one nobody can fall back from: OLED Dark declines dynamic
        // colour outright, so these values are the only ones that appearance ever draws.
        for ((name, scheme) in schemes()) {
            assertEquals(
                "$name lost the accent container",
                StoryArcColor.Brand.accentMuted,
                scheme.secondaryContainer,
            )
            assertEquals(
                "$name lost the label on the accent container",
                StoryArcColor.Light.surfaceRaised,
                scheme.onSecondaryContainer,
            )
            assertNotEquals(
                "$name is back on Material's baseline container",
                MATERIAL_BASELINE_CONTAINER,
                scheme.secondaryContainer,
            )
        }
    }

    private fun schemes(): List<Pair<String, ColorScheme>> = listOf(
        "dark" to brandDarkScheme(),
        "true black" to brandOledDarkScheme(),
        "light" to brandLightScheme(),
    )

    /**
     * The assertion every control kind above shares, said once.
     *
     * Two halves, and both are load-bearing. The first says the value is the token this
     * project chose; the second says it is not the value Material would have supplied on its
     * own — which is what proves the role is *set* rather than coincidentally agreeing, the
     * same reason `ThemeScalesTest` asserts the shape scale differs from the default.
     */
    private fun assertIsAccentContainer(what: String, drawn: Color) {
        assertEquals(what, StoryArcColor.Brand.accentMuted, drawn)
        assertNotEquals("$what is Material's baseline", MATERIAL_BASELINE_CONTAINER, drawn)
    }

    private fun assertIsOnAccentContainer(what: String, drawn: Color) {
        assertEquals(what, StoryArcColor.Light.surfaceRaised, drawn)
        assertNotEquals("$what is Material's baseline", MATERIAL_BASELINE_ON_CONTAINER, drawn)
    }

    /** Runs [body] inside the theme a reader gets with Material You turned off. */
    private fun underBrandDark(body: @Composable () -> Unit) {
        compose.setContent {
            MaterialExpressiveTheme(colorScheme = brandDarkScheme()) {
                body()
                // A composition with no node is a composition Robolectric may not run.
                Text("")
            }
        }
        compose.waitForIdle()
    }

    private companion object {
        /**
         * What Material's own dark palette puts in these two roles, measured off
         * `darkColorScheme()` before this change and written down so the negative half of
         * each assertion names a real colour rather than "not the token".
         */
        val MATERIAL_BASELINE_CONTAINER = Color(0xFF4A4458)
        val MATERIAL_BASELINE_ON_CONTAINER = Color(0xFFE8DEF8)
    }
}
