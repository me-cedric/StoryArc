package app.storyarc.core.designsystem.theme

import android.os.Build
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * When Natural's grain is drawn, and when it is refused.
 *
 * Every refusal in `settings-and-about` and `design.md` is a line here, including the one
 * a stand-in cannot otherwise reach: the API floor. `PaperGrain.isDrawn` takes the level
 * as a parameter for exactly that reason, which is the trade task 0.4b made for the curl.
 *
 * iOS's `PaperGrainTests` asserts the same table bar the floor, which iOS does not have,
 * and one extra refusal, which Android has no setting for.
 */
class PaperGrainTest {

    private val modern = Build.VERSION_CODES.TIRAMISU

    @Test
    fun `grain is drawn on a modern device with Natural on and standard contrast`() {
        assertTrue(PaperGrain.isDrawn(natural = true, isHighContrast = false, sdk = modern))
    }

    @Test
    fun `grain belongs to Natural and to nothing else`() {
        // `design.md`: the accents reach the whole app, "actual paper grain appears only
        // where text is read" — and only when the theme that owns it is on.
        assertFalse(PaperGrain.isDrawn(natural = false, isHighContrast = false, sdk = modern))
    }

    @Test
    fun `Increase Contrast turns it off, because grain lowers effective contrast`() {
        // The requirement names this one, and the reason is not a preference: grain is a
        // per-pixel modulation of the page, so it eats contrast from every letterform on
        // it. A reader who asked for more is not asking for a texture that removes some.
        assertFalse(PaperGrain.isDrawn(natural = true, isHighContrast = true, sdk = modern))
    }

    @Test
    fun `below API 33 the palette stays and the texture goes`() {
        // `RuntimeShader` arrived in Tiramisu and this module's floor is 31, so two
        // supported versions cannot draw it. `design.md`: below the floor "Natural keeps
        // its palette and accents and drops the texture" — which is what a false here
        // means, since nothing about the palette is decided by this function.
        assertFalse(
            PaperGrain.isDrawn(natural = true, isHighContrast = false, sdk = Build.VERSION_CODES.S),
        )
        assertFalse(
            PaperGrain.isDrawn(
                natural = true,
                isHighContrast = false,
                sdk = Build.VERSION_CODES.TIRAMISU - 1,
            ),
        )
        assertTrue(
            PaperGrain.isDrawn(
                natural = true,
                isHighContrast = false,
                sdk = Build.VERSION_CODES.TIRAMISU,
            ),
        )
    }

    @Test
    fun `the tuning numbers are the same three iOS uses`() {
        // Not a tautology: these are the whole of what a screen has to judge, and the two
        // platforms drifting apart on them is the one way this becomes two textures. If a
        // screenshot moves one, it moves in both files or the test says so.
        assertEquals(0.045f, PaperGrain.INTENSITY, 0f)
        assertEquals(1.5f, PaperGrain.CELL_PIXELS, 0f)
        assertEquals(0.35f, PaperGrain.FINE_OCTAVE, 0f)
    }
}
