package app.storyarc.feature.settings

import android.content.Context
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.designsystem.theme.StoryArcTheme
import app.storyarc.core.model.AppSettings
import app.storyarc.core.model.ReadingTheme
import app.storyarc.core.model.ShelfMemory
import app.storyarc.core.model.ShelfSettings
import app.storyarc.core.model.ThemePreset
import app.storyarc.core.model.ThemeScope
import app.storyarc.core.persistence.ReaderPreferences
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Task 19.2: the Reading and About rows state their values, on the screen that draws them.
 *
 * `settings-and-about`: each summary row "states its current value, so a setting can be
 * checked without entering the group". The rows are drawn from the real [SettingsScreen]
 * over a real [ReaderPreferences], so the test reads what a reader reads. Mirrors iOS's
 * `SettingsGroupSummaryTests`.
 */
@RunWith(RobolectricTestRunner::class)
// Tall enough that the whole group list and the reset row are composed without a scroll.
@Config(sdk = [34], qualifiers = "w400dp-h1600dp")
class SettingsSummaryTest {

    @get:Rule
    val compose = createComposeRule()

    private val context: Context = ApplicationProvider.getApplicationContext()

    private fun store(): ReaderPreferences = ReaderPreferences(
        context.getSharedPreferences("SettingsSummaryTest-${System.nanoTime()}", Context.MODE_PRIVATE),
    )

    private fun readingSummary(preset: ThemePreset): String = context.getString(
        R.string.settings_reading_summary_values,
        context.getString(preset.labelRes),
        context.getString(R.string.reading_matte_none),
    )

    private fun show(store: ReaderPreferences, onReset: () -> Unit = {}) {
        compose.setContent {
            StoryArcTheme {
                SettingsScreen(
                    settings = AppSettings(),
                    onChange = {},
                    readerStore = store,
                    onReset = onReset,
                    onClose = {},
                )
            }
        }
    }

    @Test
    fun `the Reading row states the stored book default`() {
        val store = store()
        store.save(ShelfMemory().settingDefault(ShelfSettings(theme = ReadingTheme(ThemePreset.CALM)), ThemeScope.REFLOWABLE))

        show(store)

        compose.onNodeWithText(readingSummary(ThemePreset.CALM)).assertExists()
    }

    @Test
    fun `the About row states the version`() {
        show(store())

        compose.onNodeWithText(context.getString(R.string.about_version, BuildInfo.version, BuildInfo.build))
            .assertExists()
    }

    @Test
    fun `a reset that clears only the reading defaults moves the Reading row`() {
        val store = store()
        store.save(ShelfMemory().settingDefault(ShelfSettings(theme = ReadingTheme(ThemePreset.CALM)), ThemeScope.REFLOWABLE))
        // What `MainActivity`'s reset does to this store. `AppSettings` stays equal, so the
        // row cannot rely on a new settings value to recompose it.
        show(store) { store.save(store.themes().clearingDefaults()) }

        compose.onNodeWithText(context.getString(R.string.settings_reset)).performClick()
        compose.onNodeWithText(context.getString(R.string.settings_reset_confirm)).performClick()

        compose.onNodeWithText(readingSummary(ThemePreset.CALM)).assertDoesNotExist()
        compose.onNodeWithText(readingSummary(ShelfSettings().theme.preset)).assertExists()
    }
}
