package app.storyarc.feature.epubreader

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * `reading-themes`, *Original*, and `ebook-reader`'s publisher-styles scenario: under
 * Original, every axis Readium cannot honour draws as unavailable, in the notice — and every
 * axis it can honour stays a live control, margins included.
 *
 * A source tripwire, for the reason `ThemeSheetTest` gives: no JVM test can lay out a
 * composable, so these cases say the wiring is written and never that a reader saw it. What
 * `ReadiumMapping` sends to Readium under Original is proved over `preferences(values:)` in
 * `ReadiumMappingTest`. iOS mirrors this suite in `OriginalKeepsWhatItCanTests`.
 */
class OriginalKeepsWhatItCanTest {

    @Test
    fun `margins draws outside the branch publisher styles hides`() {
        val screen = code("ThemeAxesScreen.kt")

        val margins = screen.indexOf("MarginsControl(theme.preset, values, onSet)")
        val branch = screen.indexOf("if (theme.preset.keepsPublisherStyles)")

        assertTrue("The screen no longer draws `MarginsControl` at all, so margins is gone" +
            " under every preset, Original included.", margins >= 0)
        assertTrue("The screen no longer branches on `keepsPublisherStyles`, so this test" +
            " cannot say which side of it margins is on.", branch >= 0)
        assertTrue(
            "`MarginsControl` moved inside the `keepsPublisherStyles` branch, so margins is" +
                " hidden under Original again. `ThemeAxis.requiresPublisherStylesOff` says" +
                " margins reaches the page under every preset, the same as font size, family" +
                " and weight.",
            margins < branch,
        )
    }

    @Test
    fun `hyphenation is not a live control under Original`() {
        val screen = code("ThemeAxesScreen.kt")

        val typefaceStart = screen.indexOf("private fun TypefaceControl(")
        assertTrue("`TypefaceControl` no longer exists in ThemeAxesScreen.kt.", typefaceStart >= 0)
        val typefaceEnd = screen.indexOf("private fun HyphenationToggle(", typefaceStart)
        assertTrue(
            "`HyphenationToggle` no longer follows `TypefaceControl`, so this test cannot" +
                " say where `TypefaceControl`'s own body ends.",
            typefaceEnd >= 0,
        )
        val typefaceBody = screen.substring(typefaceStart, typefaceEnd)

        assertFalse(
            "`TypefaceControl` still toggles hyphenation, and it draws under every preset" +
                " including Original, where a publisher's own stylesheet can set `hyphens`" +
                " — `ThemeAxis.requiresPublisherStylesOff` puts hyphenation with the axes" +
                " publisher styles overrides. A live toggle that changes nothing on the" +
                " page is the defect `reading-themes`'s publisher-styles scenario forbids.",
            typefaceBody.contains("ThemeAxis.HYPHENATION"),
        )
    }

    @Test
    fun `hyphenation moves into the branch that only draws off Original`() {
        val screen = code("ThemeAxesScreen.kt")

        val toggle = screen.indexOf("HyphenationToggle(values, onChange)")
        val elseBranch = screen.indexOf("} else {")

        assertTrue(
            "The screen no longer draws `HyphenationToggle` anywhere, so the reader has no" +
                " way left to turn hyphenation on or off.",
            toggle >= 0,
        )
        assertTrue(
            "The screen's preset branch no longer has an else, so this test cannot say" +
                " which side of it hyphenation is on.",
            elseBranch >= 0,
        )
        assertTrue(
            "`HyphenationToggle` draws outside the branch that only runs when publisher" +
                " styles are off, so it would still show as a live control under Original.",
            toggle > elseBranch,
        )
    }

    @Test
    fun `the notice still names hyphenation as unavailable under Original`() {
        val screen = code("ThemeAxesScreen.kt")

        assertTrue(
            "The publisher-styles notice no longer lists every axis" +
                " `requiresPublisherStylesOff` names, which is where hyphenation now has" +
                " to be named instead of a live control.",
            screen.contains("ThemeAxis.entries.filter { it.requiresPublisherStylesOff }"),
        )
    }

    private val module: File by lazy {
        System.getProperty(MODULE_DIRECTORY)?.let(::File)
            ?: error(
                "$MODULE_DIRECTORY is unset. This test reads the module's own source and will" +
                    " not go looking for it elsewhere — run it through Gradle" +
                    " (`pnpm gradle :feature:epubreader:testDebugUnitTest`), which sets the" +
                    " property from the module directory.",
            )
    }

    private fun code(name: String): String {
        val file = File(module, "src/main/kotlin/app/storyarc/feature/epubreader/$name")
        if (!file.isFile) {
            error("$name is not under ${module.absolutePath} — has it moved?")
        }
        return file.readText()
    }

    private companion object {
        const val MODULE_DIRECTORY = "storyarc.epubreader.projectDir"
    }
}
