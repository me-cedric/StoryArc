package app.storyarc.feature.epubreader

import app.storyarc.core.model.AppSettings
import app.storyarc.core.model.AppearanceMode
import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.model.ThemeAxis
import app.storyarc.core.model.ThemePreset
import app.storyarc.core.model.values
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import java.io.File

/**
 * The reading theme follows the device appearance while the book stays open.
 *
 * `ebook-reader` / *Theme follows appearance* asks for the switch "then and there rather than
 * at the next open". Half of it was built: the opt-in exists and [ReaderAppearance] gates the
 * answer. The other half was not, because the answer was resolved **once**, when the activity
 * built its view model — so a device that turned dark mid-chapter moved the chrome and left
 * the page where it was.
 *
 * Two rules are under test and they are deliberately separate. [ReaderAppearance] decides
 * *whether* there is an answer at all, which `ReaderAppearanceTest` owns.
 * [EpubReaderViewModel.follow] decides what the reader does with one.
 *
 * The reading position is **not** proved here. The navigator is a fragment and this is a JVM
 * test, so what stands in its place is the tripwire `ThemeSheetTest` uses: the follow goes
 * through `adopt`, which moves the theme flow the activity's `LaunchedEffect(theme, values,
 * transition)` watches — and that effect is the one path that captures the locator, submits
 * the preferences and goes back to the locator.
 *
 * iOS mirrors this suite in `AppearanceFollowedTests`.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class AppearanceFollowedTest {

    /** A reader with no store behind it, on a named preset. */
    private fun reader(on: ThemePreset): EpubReaderViewModel {
        val model = EpubReaderViewModel(
            application = RuntimeEnvironment.getApplication(),
            location = NOWHERE,
            identity = PublicationIdentity(normalizedPath = NOWHERE),
            progress = null,
        )
        model.adopt(on)
        return model
    }

    // region What the reader does with a linked preset

    @Test
    fun `a device that turns dark mid-book changes the page when the reader opted in`() {
        val model = reader(on = ThemePreset.PAPER)
        val settings = AppSettings(
            appearance = AppearanceMode.SYSTEM,
            linkReadingThemeToAppearance = true,
        )

        model.follow(ReaderAppearance.of(settings, AppearanceMode.DARK).linkedPreset)

        assertEquals(
            "The page stayed light after the device turned dark. `ebook-reader`: the reading" +
                " theme switches \"then and there rather than at the next open\".",
            ThemePreset.QUIET,
            model.theme.value.preset,
        )
        assertEquals(
            "The preset moved without its own typography, so the page is half of each theme.",
            ThemePreset.QUIET.values,
            model.values.value,
        )
    }

    @Test
    fun `a device that turns dark mid-book leaves the page alone when the reader did not`() {
        val model = reader(on = ThemePreset.PAPER)
        val settings = AppSettings(appearance = AppearanceMode.SYSTEM)

        model.follow(ReaderAppearance.of(settings, AppearanceMode.DARK).linkedPreset)

        assertEquals(
            "An unlinked reader lost their own reading theme to the device's night mode." +
                " `ebook-reader`: \"with that setting off the reading theme is untouched\".",
            ThemePreset.PAPER,
            model.theme.value.preset,
        )
    }

    @Test
    fun `an appearance change that means the same preset leaves the reader's own changes alone`() {
        val model = reader(on = ThemePreset.QUIET)
        model.set(ThemeAxis.LINE_SPACING, 2.4)

        // Dark and OLED Dark both mean Quiet. Re-adopting on that move would throw away
        // every axis the reader had moved, for a change that names the theme already on.
        model.follow(ThemePreset.QUIET)

        assertEquals(
            "An appearance change that names the theme already in force wiped the reader's" +
                " own axes.",
            2.4,
            model.values.value.lineHeight,
            0.0,
        )
        assertTrue(
            "The deviation stopped being recorded as one.",
            model.theme.value.isModified,
        )
    }

    // endregion

    // region The wiring, which no JVM test can watch

    @Test
    fun `the follow goes through the one path that preserves the reading position`() {
        val source = code("ReaderAppearance.kt")

        assertTrue(
            "The follow no longer goes through `adopt`. That is the path a preset tap takes," +
                " and the only one that moves the theme flow the activity's" +
                " `LaunchedEffect(theme, values, transition)` watches — which captures the" +
                " locator, submits the preferences and goes back to the locator. A theme" +
                " written straight onto `_theme` would move the reader.",
            source.contains("adopt(linked)"),
        )
    }

    @Test
    fun `the activity reads the link again while the book is open`() {
        val source = code("EpubReaderActivity.kt")

        assertTrue(
            "The link is still resolved once, from `resources.configuration`, outside the" +
                " composition. `uiMode` is in this activity's `configChanges`, so a device" +
                " that turns dark does not rebuild it and the page keeps the appearance the" +
                " book opened in.",
            source.contains("linkedReadingTheme(settings)"),
        )
        assertTrue(
            "Nothing hands the re-read link to the view model, which is the same defect with" +
                " a watcher.",
            source.contains("model.follow("),
        )
        assertTrue(
            "`linkedReadingTheme` no longer reads the configuration the composition is given," +
                " so what it answers is fixed for the life of the activity again.",
            code("ReaderAppearance.kt").contains("LocalConfiguration.current"),
        )
    }

    // endregion

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
        const val NOWHERE = "/nowhere.epub"
    }
}
