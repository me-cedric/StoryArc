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
 *
 * The two `refreshingChrome` cases are the second half of that defect: the appearance was
 * then read once, at open, so an appearance chosen while the book stayed open reached the
 * book only after it was closed and reopened. `ReaderChromeWiringTest` is what checks the
 * activity calls this on the way back in; these two check what it means when it does.
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
    fun `coming back from Settings redraws the chrome`() {
        // The defect this pins: the reader is its own activity, so a choice made in
        // `MainActivity` while a book stayed open reached every screen except the book.
        // `settings-and-about` requires an appearance to apply "immediately across the whole
        // app without a restart", and a reader still looking at the old scheme is that clause
        // failing.
        val opened = of(AppSettings(appearance = AppearanceMode.LIGHT, useDynamicColor = true))
        val now = of(AppSettings(appearance = AppearanceMode.OLED_DARK, useDynamicColor = false))

        val back = opened.refreshingChrome(now)

        assertEquals(AppearanceMode.OLED_DARK, back.chrome)
        assertEquals(false, back.useDynamicColor)
    }

    @Test
    fun `coming back from Settings leaves the reading theme the book opened with`() {
        // The other half, and the reason this is a merge rather than a fresh read: by now the
        // reader may have adopted a preset by hand in the theme sheet, and `settings-and-about`
        // says a change of app appearance does not override the reading theme.
        val linked = AppSettings(linkReadingThemeToAppearance = true)
        val opened = of(linked.copy(appearance = AppearanceMode.LIGHT), device = AppearanceMode.LIGHT)
        val now = of(linked.copy(appearance = AppearanceMode.DARK), device = AppearanceMode.DARK)

        val back = opened.refreshingChrome(now)

        assertEquals(ThemePreset.PAPER, back.linkedPreset)
        assertEquals(AppearanceMode.DARK, back.chrome)

        // And in the other direction: a reader who opted in *while* the book was open does not
        // get a preset pushed at them either. The setting takes effect on the next book.
        assertNull(of(AppSettings()).refreshingChrome(now).linkedPreset)
    }

    @Test
    fun `OLED Dark blackens the chrome and stops short of the reading surface`() {
        val settings = AppSettings(
            appearance = AppearanceMode.OLED_DARK,
            linkReadingThemeToAppearance = true,
        )

        val reader = of(settings, device = AppearanceMode.OLED_DARK)

        // `settings-and-about` writes both halves as one sentence: "honoured where it helps
        // and explained where it does not". Honoured is the chrome going true black. Quiet
        // rather than anything darker is the other half, and the Appearance screen is where
        // it gets explained -- pure black smears on OLED during a page turn.
        assertTrue(reader.chrome.isTrueBlack)
        assertEquals(ThemePreset.QUIET, reader.linkedPreset)

        // Named for the colour, and only the colour. OLED Dark does reach the page by one
        // other route -- it withdraws Natural, and Natural's grain with it -- which is the
        // rule the whole app follows and is pinned in `ReaderNaturalGrainTest`. This test
        // used to be called "does not darken the page", which read as a promise that nothing
        // on the page moved at all.
    }
}
