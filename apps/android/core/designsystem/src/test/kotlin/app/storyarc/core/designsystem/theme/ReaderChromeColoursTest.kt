package app.storyarc.core.designsystem.theme

import androidx.compose.material3.ExperimentalMaterial3ExpressiveApi
import androidx.compose.material3.FloatingToolbarColors
import androidx.compose.material3.FloatingToolbarDefaults
import androidx.compose.material3.MaterialExpressiveTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.test.junit4.v2.createComposeRule
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * The capsule that floats over a page is a layer above the page, not the colour of it.
 *
 * `AGENTS.md`'s fifth non-negotiable: "the artwork is the interface. Chrome recedes,
 * auto-hides, never tints." A control that recedes into the page it sits on has gone past
 * receding, and the sweep of 2026-09-02 caught exactly that: `android-epub-chrome.png` is
 * Material's `surfaceContainer` laid over running body text — a pale lozenge with sentences
 * visible around its edges — while `android-comic-chrome.png`, the same component with the
 * same two buttons, carries a scrim and reads correctly.
 *
 * ## Why the pair is measured rather than restated
 *
 * `readerChromeColours()` could be asserted field by field and would keep passing on the day
 * `standardFloatingToolbarColors()` renames or reorders its parameters, or on the day a call
 * site stops passing them. So this composes the theme, asks the real
 * `FloatingToolbarDefaults` what an *unnamed* capsule would have been, and requires the
 * reader's to differ from it — the same shape of assertion as
 * `AccentReachesTheControlsTest`, and for the same reason.
 *
 * ## What is not proved here
 *
 * That both readers pass these colours. That is a call site, and each reader's own
 * `ReaderChromeTest` is the source tripwire for it, for the reason those files already give:
 * nothing in CI runs either module's instrumented tests.
 */
@RunWith(RobolectricTestRunner::class)
// Robolectric ships an image per API level and has none for 37. A colour has no API level.
@Config(sdk = [34])
@OptIn(ExperimentalMaterial3ExpressiveApi::class)
class ReaderChromeColoursTest {

    @get:Rule
    val compose = createComposeRule()

    @Test
    fun `the capsule is the palette's scrim and not a surface`() {
        lateinit var reader: FloatingToolbarColors
        lateinit var material: FloatingToolbarColors
        underLightChrome {
            reader = readerChromeColours()
            material = FloatingToolbarDefaults.standardFloatingToolbarColors()
        }

        assertNotEquals(
            "the reader's capsule is Material's own container, which is what the sweep" +
                " photographed over body text",
            material.toolbarContainerColor,
            reader.toolbarContainerColor,
        )
        assertEquals(
            "the capsule is not drawn on the appearance's scrim",
            StoryArcPalette.Light.scrim,
            reader.toolbarContainerColor.copy(alpha = 1f),
        )
        assertEquals("the glyphs are not white", Color.White, reader.toolbarContentColor)
    }

    @Test
    fun `a white glyph carries on the whitest page either reader can draw`() {
        lateinit var reader: FloatingToolbarColors
        underLightChrome { reader = readerChromeColours() }

        // Pure white: a comic page that is mostly paper, and the lightest reading theme.
        // Anything darker only helps, which is why the worst case is the one asserted.
        val drawn = over(reader.toolbarContainerColor, Color.White)
        val ratio = contrast(Color.White, drawn)
        assertTrue(
            "a white glyph reaches only ${"%.2f".format(ratio)}:1 on the capsule over white" +
                " paper; WCAG asks 3:1 of a graphical object",
            ratio >= GRAPHICAL_OBJECT_FLOOR,
        )
    }

    @Test
    fun `the capsule is a layer rather than a hole in the page`() {
        lateinit var reader: FloatingToolbarColors
        underLightChrome { reader = readerChromeColours() }

        // The complaint in the sweep's own words is that the pill has "no scrim, gap or
        // elevation" — a lozenge the colour of what is behind it. This is the part a
        // contrast floor does not catch: a *white* glyph would still carry on a white
        // capsule if the capsule were dark enough only where the glyph is not.
        val page = Color.White
        val ratio = contrast(over(reader.toolbarContainerColor, page), page)
        assertTrue(
            "the capsule reaches only ${"%.2f".format(ratio)}:1 against the page it floats" +
                " over, so its edge is not visible",
            ratio >= EDGE_FLOOR,
        )
    }

    /** The chrome as a reader sees it with the app in its light appearance. */
    private fun underLightChrome(body: @Composable () -> Unit) {
        compose.setContent {
            StoryArcThemeUnderTest {
                body()
                // A composition with no node is a composition Robolectric may not run.
                Text("")
            }
        }
        compose.waitForIdle()
    }

    @Composable
    private fun StoryArcThemeUnderTest(content: @Composable () -> Unit) {
        androidx.compose.runtime.CompositionLocalProvider(
            LocalStoryArcPalette provides StoryArcPalette.Light,
        ) {
            MaterialExpressiveTheme(colorScheme = brandLightScheme(), content = content)
        }
    }

    private companion object {
        /** WCAG's floor for a graphical object, which an icon is. */
        const val GRAPHICAL_OBJECT_FLOOR = 3.0

        /**
         * How far the capsule has to stand off the page for its own shape to be legible.
         *
         * WCAG has no requirement for "this control has an edge", so this is a design floor
         * rather than a standard's: 1.5:1 is roughly the point at which a flat fill stops
         * reading as a tint of what is behind it. Material's own `surfaceContainer` over the
         * cream page in `android-epub-chrome.png` measures about 1.03:1.
         */
        const val EDGE_FLOOR = 1.5

        /** Composites a translucent colour over an opaque one. */
        fun over(front: Color, back: Color): Color = Color(
            red = front.red * front.alpha + back.red * (1 - front.alpha),
            green = front.green * front.alpha + back.green * (1 - front.alpha),
            blue = front.blue * front.alpha + back.blue * (1 - front.alpha),
        )

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