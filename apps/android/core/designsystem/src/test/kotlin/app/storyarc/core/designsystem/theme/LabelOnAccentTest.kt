package app.storyarc.core.designsystem.theme

import androidx.compose.material3.ColorScheme
import androidx.compose.ui.graphics.Color
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * `close-the-audited-gaps` 25.7, owner answer O26: the label drawn on the accent reaches 4.5:1.
 *
 * `Button`, `FilledTonalButton` and a selected chip read `primary`/`onPrimary` and
 * `secondaryContainer`/`onSecondaryContainer`, so this asks each scheme the app can draw for
 * the ratio of those pairs. `pnpm tokens:check` gates the token values; this gates the wiring.
 */
class LabelOnAccentTest {

    private val schemes: Map<String, ColorScheme> = mapOf(
        "brand dark" to brandDarkScheme(),
        "brand light" to brandLightScheme(),
        "brand OLED dark" to brandOledDarkScheme(),
        "Natural light" to naturalLightScheme(),
        "Natural dark" to naturalDarkScheme(),
    )

    @Test
    fun `the label on a filled button reaches 4_5 to 1 on every scheme`() {
        schemes.forEach { (name, scheme) ->
            val ratio = contrast(scheme.onPrimary, scheme.primary)
            assertTrue("$name: label on the accent is $ratio:1", ratio >= FLOOR)
        }
    }

    @Test
    fun `the label on a selected chip reaches 4_5 to 1 on every brand scheme`() {
        listOf(brandDarkScheme(), brandLightScheme(), brandOledDarkScheme()).forEach { scheme ->
            val ratio = contrast(scheme.onSecondaryContainer, scheme.secondaryContainer)
            assertTrue("label on a selected chip is $ratio:1", ratio >= FLOOR)
        }
    }

    private companion object {
        const val FLOOR = 4.5

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
