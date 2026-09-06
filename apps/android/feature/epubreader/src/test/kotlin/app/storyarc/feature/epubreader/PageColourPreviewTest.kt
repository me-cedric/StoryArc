package app.storyarc.feature.epubreader

import app.storyarc.core.model.ReaderPalette
import app.storyarc.core.model.ReadingTheme
import app.storyarc.core.model.ThemePreset
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import java.io.File

/**
 * A background is shown before it is applied, not after.
 *
 * `reading-themes` / *Choosing a background* asks for the background and the derived text
 * colour to be "shown in the preview before being applied". The section did the opposite: the
 * swatch called `onAdopt`, which reached the rendered page, and the sample under it then drew
 * the pairing already in force. That is a preview of the past — a reader could not see what a
 * colour would do to their book until it had already done it.
 *
 * So a tap now sets a **pending** pairing, the sample, the band and the ratio describe that,
 * and one confirmation applies it. Nothing else about the section moves: a pairing below 4.5
 * to 1 is still refused on that confirmation, with the band first and the measured ratio after
 * it, which `PageColourBandTest` owns.
 *
 * **What each half of this suite proves.** [previewedPairing] is a pure rule and is driven
 * directly. What a tap *does* cannot be: no JVM test can lay out a composable, so the call
 * sites are read as text, which is the tripwire `PageColourBandTest` and `ThemeSheetTest`
 * already use for this sheet.
 *
 * iOS mirrors this suite in `PageColourPreviewTests`.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class PageColourPreviewTest {

    private val inForce = ReaderPalette.derived("In force", "#FFFFFF")
    private val pending = ReaderPalette.derived("Pending", "#101010")

    // region What the preview describes

    @Test
    fun `with nothing pending, the preview describes the pairing in force`() {
        assertEquals(
            "The section stopped describing the reader's own colours once nothing was pending.",
            inForce,
            previewedPairing(pending = null, inForce = inForce),
        )
    }

    @Test
    fun `a pending pairing is what the preview describes, and the page keeps the old one`() {
        assertEquals(
            "The preview describes the pairing in force rather than the one the reader just" +
                " chose. `reading-themes`: the background and the derived text colour are" +
                " \"shown in the preview before being applied\".",
            pending,
            previewedPairing(pending = pending, inForce = inForce),
        )
    }

    @Test
    fun `a pending pairing is describable before any pairing has ever been applied`() {
        assertEquals(
            "The first colour a reader ever picks cannot be previewed, which is the one that" +
                " most needs it.",
            pending,
            previewedPairing(pending = pending, inForce = null),
        )
    }

    // endregion

    @Test
    fun `the specimen above the controls is drawn with the pairing being previewed`() {
        val inUse = ReadingTheme(ThemePreset.PAPER, custom = inForce)

        assertEquals(
            "The screen's own specimen still draws the pairing in force while the three-line" +
                " sample under it draws the pending one, so one screen shows two answers for" +
                " one pairing and the larger one is stale. `ebook-reader` asks the specimen" +
                " to update \"as an axis changes\", and `reading-themes` asks a background to" +
                " be \"shown in the preview before being applied\".",
            pending,
            previewedTheme(inUse, pending).custom,
        )
        assertEquals(
            "The specimen stopped drawing the reader's own colours once nothing was pending.",
            inForce,
            previewedTheme(inUse, null).custom,
        )
    }

    // region What a tap does, and what it does not do

    @Test
    fun `a swatch previews the pairing and does not put it on the page`() {
        val source = code("PageColourSection.kt")

        assertTrue(
            "The background swatch no longer previews the pairing it makes. `reading-themes`" +
                " asks for the pairing to be shown before it is applied, and a swatch that" +
                " applies it leaves the sample below describing what already happened.",
            source.contains("preview(ReaderPalette.derived(chosenName, it))"),
        )
        assertFalse(
            "The background swatch still applies the pairing straight to the page. The preview" +
                " under it then draws the palette already in force, which is the defect this" +
                " suite exists for.",
            source.contains("adopt(ReaderPalette.derived(chosenName, it))"),
        )
    }

    @Test
    fun `the picker previews too, so a drag does not repaint the book`() {
        val source = code("PageColourSection.kt")

        assertTrue(
            "Dragging a hue, saturation or lightness slider still repaints the reader's book" +
                " on every step. The three sliders are the second way into a background and" +
                " the one a reader explores with.",
            source.contains("preview(ReaderPalette.derived(chosenName, hslHex(h, s, l)))"),
        )
    }

    @Test
    fun `the derived text colour is previewed as well as the background`() {
        val source = code("PageColourSection.kt")

        assertTrue(
            "Overriding the derived text colour still applies straight to the page." +
                " `reading-themes` names both halves of the pairing: the background \"and the" +
                " derived text colour\" are shown in the preview before being applied.",
            source.contains("preview(palette.copy(foreground = it))"),
        )
    }

    @Test
    fun `one confirmation is what applies the pairing`() {
        val source = code("PageColourSection.kt")

        assertTrue(
            "The section draws no way to apply what it is previewing, so a reader can choose a" +
                " colour and never reach it.",
            source.contains("R.string.theme_page_colour_apply"),
        )
        // `adopt(candidate)` rather than `adopt(pending)`, which is what iOS reads for. A
        // `var` held by `remember` is a delegated property and Kotlin will not smart-cast
        // one, so the pending pairing reaches the button through a `let` binding.
        assertTrue(
            "The confirmation applies something other than the pairing the reader was shown.",
            source.contains("adopt(candidate)"),
        )
    }

    // endregion

    // region Four languages

    @Test
    fun `the confirmation is named in English`() = assertTheSheetNamesTheAction()

    @Test
    @Config(qualifiers = "fr-rFR")
    fun `the confirmation is named in French`() = assertTheSheetNamesTheAction()

    @Test
    @Config(qualifiers = "de-rDE")
    fun `the confirmation is named in German`() = assertTheSheetNamesTheAction()

    @Test
    @Config(qualifiers = "es-rES")
    fun `the confirmation is named in Spanish`() = assertTheSheetNamesTheAction()

    // endregion

    private fun assertTheSheetNamesTheAction() {
        val context = RuntimeEnvironment.getApplication()
        val named = context.getString(R.string.theme_page_colour_apply)

        assertTrue(
            "The action that applies a previewed pairing resolved to nothing.",
            named.isNotBlank(),
        )
    }

    /**
     * One source file of this module, read from the path Gradle hands the test JVM.
     *
     * A tripwire rather than a proof, for the reason `PageColourBandTest` gives at length.
     */
    private fun code(name: String): String {
        val directory = System.getProperty(MODULE_DIRECTORY)
            ?: error(
                "$MODULE_DIRECTORY is unset. This test reads the module's own source and will" +
                    " not go looking for it elsewhere — run it through Gradle" +
                    " (`pnpm gradle :feature:epubreader:testDebugUnitTest`), which sets the" +
                    " property from the module directory.",
            )
        val file = File(directory, "src/main/kotlin/app/storyarc/feature/epubreader/$name")
        if (!file.isFile) {
            error("$name is not under $directory — has it moved?")
        }
        return file.readText()
    }

    private companion object {
        /** Set by this module's `build.gradle.kts`, from its own `projectDir`. */
        const val MODULE_DIRECTORY = "storyarc.epubreader.projectDir"
    }
}
