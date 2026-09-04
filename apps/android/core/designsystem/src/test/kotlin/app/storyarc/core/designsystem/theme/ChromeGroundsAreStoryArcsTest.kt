package app.storyarc.core.designsystem.theme

import androidx.compose.material3.AlertDialogDefaults
import androidx.compose.material3.BottomSheetDefaults
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ColorScheme
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExperimentalMaterial3ExpressiveApi
import androidx.compose.material3.MaterialExpressiveTheme
import androidx.compose.material3.MenuDefaults
import androidx.compose.material3.ShortNavigationBarDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.test.junit4.v2.createComposeRule
import app.storyarc.core.designsystem.tokens.StoryArcColor
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Every ground a Material component draws itself on is a StoryArc surface, on the path a
 * reader takes with Material You **off**.
 *
 * ## What the sweep photographed
 *
 * `AccentReachesTheControlsTest` closed one unset role and its own account named the ones it
 * left, "so the next reader has it". The `surfaceContainer` family was on that list, and the
 * Android sweep of 2026-09-02 shows what it costs. Sampled out of the frames rather than
 * argued from the code:
 *
 * | Frame | Where | Drawn | Should be |
 * | --- | --- | --- | --- |
 * | `android-library-selection-two-nodynamic.png` | the navigation band | `#F3EDF7` | a StoryArc neutral over `#F8F6F4` |
 * | `android-library-grid-nodynamic-dark.png` | the navigation band | `#211F26` | a StoryArc neutral over `#0F0D0B` |
 * | `android-comic-menu-nodynamic-dark.png` | the sheet | `#1D1B20` | a StoryArc neutral over `#1A1815` |
 *
 * `#F3EDF7` and `#211F26` are `surfaceContainer` out of Material's baseline palette;
 * `#1D1B20` is `surfaceContainerLow`. So the sweep's §4 — "turning Material You off changes
 * less than it should" — is true of far more than the controls it names: it is every sheet,
 * every dialog, every menu and the navigation bar on every screen, and on **OLED Dark and
 * Natural it is the only thing a reader ever sees**, because those two decline dynamic
 * colour outright.
 *
 * ## What §4 got wrong, which this test cannot fix
 *
 * The sweep reads the `+`, the `⋮`, the selection ticks and the bulk-action icons as
 * "Material's baseline". They are not. Sampled from both frames at the same pixels, all four
 * are `#8A4DF0` — `brand.accent` exactly — **with dynamic colour on as well as off**, which
 * no role-derived value could be. They are hand-tinted `LocalStoryArcPalette.current.accent`
 * at their call sites, which is the opposite defect: not Material leaking into the brand, but
 * the brand overriding Material You on chrome, which the chrome/content rule on
 * [LocalStoryArcPalette] forbids and which `native-experience` requires not to happen. Those
 * call sites are in `:feature:library`, and closing them is that module's to do.
 *
 * ## Why this reads the defaults instead of asserting the scheme
 *
 * `the grounds are the appearance's own surfaces` below asserts the wiring — that `surfaceContainer` is the palette's raised
 * surface. That is necessary and not sufficient, for `AccentReachesTheControlsTest`'s reason:
 * it would keep passing on the day a material3 upgrade moves a sheet to `surfaceContainer` or
 * the navigation bar to `surfaceContainerHigh`, and the app would go quietly back to lavender
 * with every colour test in the module still green. So this file composes the real theme and
 * asks the real `BottomSheetDefaults`, `MenuDefaults`, `AlertDialogDefaults`,
 * `ShortNavigationBarDefaults`, `TopAppBarDefaults` and `CardDefaults` what they resolved to.
 *
 * Pinned to material3 1.5.0-alpha, which `apps/android/README.md` records as a known risk.
 */
@RunWith(RobolectricTestRunner::class)
// Robolectric ships an image per API level and has none for 37. Which colour a Material
// default resolves to has no API level in it — the dynamic-colour branch this file never
// touches is the only part that would.
@Config(sdk = [34])
@OptIn(ExperimentalMaterial3Api::class, ExperimentalMaterial3ExpressiveApi::class)
class ChromeGroundsAreStoryArcsTest {

    @get:Rule
    val compose = createComposeRule()

    @Test
    fun `a bottom sheet is a StoryArc surface`() = underBrandDark {
        assertGround("a bottom sheet", BottomSheetDefaults.ContainerColor)
    }

    @Test
    fun `a menu and the navigation bar are a StoryArc surface`() = underBrandDark {
        assertGround("a menu", MenuDefaults.containerColor)
        assertGround("the navigation bar", ShortNavigationBarDefaults.containerColor)
        // The same role, reached a third way: a top app bar swaps to it once content has
        // scrolled under it, which is most of the time a reader is looking at one.
        assertGround(
            "a scrolled top app bar",
            TopAppBarDefaults.topAppBarColors().scrolledContainerColor,
        )
    }

    @Test
    fun `a dialog and a card are a StoryArc surface`() = underBrandDark {
        assertGround("a dialog", AlertDialogDefaults.containerColor)
        assertGround("a card", CardDefaults.cardColors().containerColor)
    }

    @Test
    fun `no scheme that declines Material You keeps a baseline ground`() {
        // The three brand schemes and both Natural variants. Natural matters most of the
        // five: it and OLED Dark override dynamic colour, so there is no path on which a
        // wallpaper covers for an unset role.
        for ((name, scheme, baseline) in schemes()) {
            for ((role, drawn) in grounds(scheme)) {
                assertNotEquals(
                    "$name draws Material's baseline in $role",
                    grounds(baseline)[role],
                    drawn,
                )
            }
        }
    }

    @Test
    fun `the grounds are the appearance's own surfaces and stay in order`() {
        for ((name, scheme, _) in schemes()) {
            val ours = paletteOf(name)
            assertEquals("$name surfaceContainerLow", ours.surfaceRaised, scheme.surfaceContainerLow)
            assertEquals("$name surfaceContainer", ours.surfaceRaised, scheme.surfaceContainer)
            assertEquals("$name surfaceContainerHigh", ours.surfaceOverlay, scheme.surfaceContainerHigh)
            assertEquals("$name surfaceVariant", ours.surfaceSunken, scheme.surfaceVariant)
            // A sheet has to be visible against the page it covers. The one thing a
            // mapping from four tokens onto five slots can get wrong is landing a
            // container back on the canvas, and this is what would say so.
            assertNotEquals(
                "$name draws a sheet the same colour as the page behind it",
                scheme.background,
                scheme.surfaceContainerLow,
            )
        }
    }

    @Test
    fun `text on those grounds still carries`() {
        // The palette's own pairings, restated where Material now draws them. `onSurface`
        // is what a sheet's and a dialog's content is drawn in, and neither was measured
        // against these surfaces before, because these surfaces were Material's.
        for ((name, scheme, _) in schemes()) {
            for ((role, ground) in grounds(scheme)) {
                if (role == "surfaceDim" || role == "surfaceVariant") continue
                val ratio = contrast(scheme.onSurface, ground)
                assertTrue(
                    "$name: body text on $role reaches only ${"%.2f".format(ratio)}:1",
                    ratio >= BODY_TEXT_FLOOR,
                )
            }
        }
    }

    private fun paletteOf(name: String): StoryArcPalette = when (name) {
        "dark" -> StoryArcPalette.Dark
        "true black" -> StoryArcPalette.OledDark
        "light" -> StoryArcPalette.Light
        "natural light" -> StoryArcPalette.NaturalLight
        else -> StoryArcPalette.NaturalDark
    }

    private fun schemes(): List<Triple<String, ColorScheme, ColorScheme>> = listOf(
        Triple("dark", brandDarkScheme(), darkColorScheme()),
        Triple("true black", brandOledDarkScheme(), darkColorScheme()),
        Triple("light", brandLightScheme(), lightColorScheme()),
        Triple("natural light", naturalLightScheme(), lightColorScheme()),
        Triple("natural dark", naturalDarkScheme(), darkColorScheme()),
    )

    private fun grounds(scheme: ColorScheme): Map<String, Color> = mapOf(
        "surfaceVariant" to scheme.surfaceVariant,
        "surfaceBright" to scheme.surfaceBright,
        "surfaceDim" to scheme.surfaceDim,
        "surfaceContainerLowest" to scheme.surfaceContainerLowest,
        "surfaceContainerLow" to scheme.surfaceContainerLow,
        "surfaceContainer" to scheme.surfaceContainer,
        "surfaceContainerHigh" to scheme.surfaceContainerHigh,
        "surfaceContainerHighest" to scheme.surfaceContainerHighest,
    )

    /**
     * The value is a StoryArc surface, and it is not the one Material would have supplied.
     *
     * Both halves are load-bearing, for [AccentReachesTheControlsTest]'s reason: the first
     * says the role is wired to a token this project chose, the second says it is *set*
     * rather than coincidentally agreeing.
     */
    private fun assertGround(what: String, drawn: Color) {
        assertTrue("$what is not a StoryArc surface: $drawn", drawn in DARK_SURFACES)
        assertTrue("$what is one of Material's baseline greys", drawn !in MATERIAL_DARK_GROUNDS)
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
        /** WCAG AA for body text, which is what a sheet and a dialog are full of. */
        const val BODY_TEXT_FLOOR = 4.5

        val DARK_SURFACES = setOf(
            StoryArcColor.Dark.surfaceCanvas,
            StoryArcColor.Dark.surfaceRaised,
            StoryArcColor.Dark.surfaceOverlay,
            StoryArcColor.Dark.surfaceSunken,
        )

        /**
         * What `darkColorScheme()` puts in these roles, written down so the negative half of
         * each assertion names real colours. `#211F26` and `#1D1B20` are the two the sweep
         * photographed.
         */
        val MATERIAL_DARK_GROUNDS = setOf(
            Color(0xFF0F0D13),
            Color(0xFF1D1B20),
            Color(0xFF211F26),
            Color(0xFF2B2930),
            Color(0xFF36343B),
            Color(0xFF3B383E),
            Color(0xFF141218),
            Color(0xFF49454F),
        )

        /** WCAG relative luminance, and the ratio between two opaque colours. */
        fun contrast(a: Color, b: Color): Double {
            val one = luminance(a)
            val two = luminance(b)
            return (maxOf(one, two) + 0.05) / (minOf(one, two) + 0.05)
        }

        fun luminance(colour: Color): Double {
            fun channel(value: Float): Double {
                val v = value.toDouble()
                return if (v <= 0.03928) v / 12.92 else Math.pow((v + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * channel(colour.red) +
                0.7152 * channel(colour.green) +
                0.0722 * channel(colour.blue)
        }
    }
}
