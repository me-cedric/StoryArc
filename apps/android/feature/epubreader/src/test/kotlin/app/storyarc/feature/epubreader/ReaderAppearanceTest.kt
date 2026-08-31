package app.storyarc.feature.epubreader

import app.storyarc.core.model.AppSettings
import app.storyarc.core.model.AppearanceMode
import app.storyarc.core.model.ThemePreset
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * What the reader's chrome is drawn with.
 *
 * A plain JVM test rather than an instrumented one: [ReaderAppearance] takes the resolved
 * appearance as a value precisely so the rule can be asserted without a device deciding
 * half of it. What a `Configuration` resolves to is `resolved()`'s own contract, pinned in
 * `:core:designsystem`, and what an appearance maps to is `presetMatching`'s, pinned in
 * `:core:model`.
 *
 * The first two cases are the regression. The reflowable reader used to build its chrome
 * with a hardcoded `AppearanceMode.SYSTEM`, which made it the one screen in the app that
 * ignored Settings › Appearance -- and, because a true-black palette outranks Material You
 * in `StoryArcTheme`, the one screen OLED Dark could not reach at all.
 */
class ReaderAppearanceTest {

    private fun of(
        settings: AppSettings,
        device: AppearanceMode = AppearanceMode.LIGHT,
    ) = ReaderAppearance.of(settings, device)

    @Test
    fun `the chrome is drawn with the appearance the reader chose`() {
        listOf(AppearanceMode.LIGHT, AppearanceMode.DARK, AppearanceMode.OLED_DARK)
            .forEach { chosen ->
                assertEquals(chosen, of(AppSettings(appearance = chosen)).chrome)
            }
    }

    @Test
    fun `OLED Dark reaches the chrome even with Material You on`() {
        val reader = of(AppSettings(appearance = AppearanceMode.OLED_DARK))

        // Both halves matter. `StoryArcTheme` gives true black precedence over the
        // wallpaper scheme, so the chrome only turns black if the appearance arrives
        // unaltered -- and the opt-out has to arrive with it or a reader who turned
        // Material You off keeps it inside a book.
        assertTrue(reader.chrome.isTrueBlack)
        assertTrue(reader.useDynamicColor)
        assertEquals(false, of(AppSettings(useDynamicColor = false)).useDynamicColor)
    }

    @Test
    fun `System stays System, so the theme can keep asking the device`() {
        // Handing over the resolved answer instead would freeze the reader in whatever the
        // device was showing when the book opened. `settings-and-about` requires the app to
        // follow when the device switches theme, and a book is not outside the app.
        val reader = of(AppSettings(appearance = AppearanceMode.SYSTEM), device = AppearanceMode.DARK)

        assertEquals(AppearanceMode.SYSTEM, reader.chrome)
    }

    @Test
    fun `no linked preset until the reader asks for one`() {
        // Off by default: appearance and reading theme are separate settings, and a dark
        // chrome around a paper-white page is a preference rather than a mistake.
        assertNull(of(AppSettings(appearance = AppearanceMode.DARK), device = AppearanceMode.DARK).linkedPreset)
    }

    @Test
    fun `a linked preset follows the device rather than the literal choice`() {
        val settings = AppSettings(
            appearance = AppearanceMode.SYSTEM,
            linkReadingThemeToAppearance = true,
        )

        assertEquals(ThemePreset.QUIET, of(settings, device = AppearanceMode.DARK).linkedPreset)
        assertEquals(ThemePreset.PAPER, of(settings, device = AppearanceMode.LIGHT).linkedPreset)
    }

    @Test
    fun `OLED Dark blackens the chrome and does not darken the page`() {
        val settings = AppSettings(
            appearance = AppearanceMode.OLED_DARK,
            linkReadingThemeToAppearance = true,
        )

        val reader = of(settings, device = AppearanceMode.OLED_DARK)

        // The sentence `settings-and-about` writes as one: honoured where it helps, declined
        // where it does not. Quiet rather than anything darker, because pure black smears on
        // OLED during a page turn.
        assertTrue(reader.chrome.isTrueBlack)
        assertEquals(ThemePreset.QUIET, reader.linkedPreset)
    }
}
