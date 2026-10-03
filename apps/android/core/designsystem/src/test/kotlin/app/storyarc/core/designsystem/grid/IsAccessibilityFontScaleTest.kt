package app.storyarc.core.designsystem.grid

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * [isAccessibilityFontScale] exposes the one threshold [steppedForFontScale] already stepped
 * covers at, so `:feature:library`'s list fallback (`libraryFallsBackToList`, task 19.6) can
 * ask the same line rather than restating `1.3f` — the drift this file's own header comment
 * exists to prevent.
 */
class IsAccessibilityFontScaleTest {

    @Test
    fun `android's own Font size slider tops out below the line`() {
        assertFalse(isAccessibilityFontScale(1.0f))
        assertFalse(isAccessibilityFontScale(1.29f))
    }

    @Test
    fun `the line itself is already past it`() {
        assertTrue(isAccessibilityFontScale(1.3f))
    }

    @Test
    fun `the accessibility settings' own larger steps are past it too`() {
        assertTrue(isAccessibilityFontScale(1.5f))
        assertTrue(isAccessibilityFontScale(2.0f))
    }
}
