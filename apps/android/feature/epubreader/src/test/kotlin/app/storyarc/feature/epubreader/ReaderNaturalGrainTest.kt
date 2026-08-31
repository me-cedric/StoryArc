package app.storyarc.feature.epubreader

import app.storyarc.core.designsystem.theme.NaturalTheme
import app.storyarc.core.designsystem.theme.PaperGrain
import app.storyarc.core.model.AppearanceMode
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Whether Natural's paper grain reaches the reading page, per appearance.
 *
 * The composition that draws it is two reads chained — `LocalIsNaturalTheme` is
 * `NaturalTheme.applies(switch, appearance)`, and `PaperGrainOverlay` feeds that into
 * `PaperGrain.isDrawn`. Both halves are pure, so the chain can be asserted here even though
 * the drawing cannot; what a device would add is whether the specks are visible, which
 * `PaperGrainOverlay`'s KDoc measures rather than looks at.
 *
 * The case that matters is OLED Dark. The reader used to build its chrome with a hardcoded
 * `AppearanceMode.SYSTEM`, and `applies(on, SYSTEM)` is just `on` — so a reader on OLED Dark
 * with the Natural switch left on got grain on the page that no other surface in the app
 * would have given them. Handing the chrome the real appearance ended that, and this is the
 * test that says the ending was on purpose.
 */
class ReaderNaturalGrainTest {

    private fun isGrainDrawn(natural: Boolean, appearance: AppearanceMode) = PaperGrain.isDrawn(
        natural = NaturalTheme.applies(natural, appearance),
        isHighContrast = false,
        // Above the RuntimeShader floor, so the appearance is the only thing under test.
        sdk = android.os.Build.VERSION_CODES.TIRAMISU,
    )

    @Test
    fun `OLED Dark takes the grain off the page, switch on or not`() {
        // Not a loss, a rule: Natural does not combine with OLED Dark anywhere in the app,
        // because a cream canvas at #16100C would break the promise the black point makes
        // about the panel. Grain is Natural's texture and nothing else's, so it goes with it.
        assertFalse(isGrainDrawn(natural = true, appearance = AppearanceMode.OLED_DARK))
        assertFalse(NaturalTheme.isAvailable(AppearanceMode.OLED_DARK))
    }

    @Test
    fun `every other appearance keeps the grain when Natural is on`() {
        listOf(AppearanceMode.SYSTEM, AppearanceMode.LIGHT, AppearanceMode.DARK)
            .forEach { appearance ->
                assertTrue("$appearance", isGrainDrawn(natural = true, appearance = appearance))
            }
    }

    @Test
    fun `no grain without Natural, whatever the appearance`() {
        AppearanceMode.entries.forEach { appearance ->
            assertFalse("$appearance", isGrainDrawn(natural = false, appearance = appearance))
        }
    }
}
