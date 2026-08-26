package app.storyarc.feature.settings

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsOff
import androidx.compose.ui.test.assertIsOn
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextInput
import androidx.test.platform.app.InstrumentationRegistry
import app.storyarc.core.designsystem.theme.StoryArcTheme
import app.storyarc.core.model.AppSettings
import app.storyarc.core.model.SUGGESTED_BACKGROUNDS
import app.storyarc.core.persistence.ReaderPreferences
import org.junit.Rule
import org.junit.Test
import java.util.UUID

/**
 * What a screen reader learns from the settings lists and the search.
 *
 * The same reasoning as the theme sheet's `ThemeSheetSemanticsTest`: none of this is
 * visible in a screenshot, and `uiautomator dump` cannot report what a Compose node
 * merges. A composition is the only place the question can be asked.
 *
 * The defects these pin were real. Both switches were bare `Switch`es whose label was a
 * sibling — a nameless on/off to TalkBack. The two Privacy buttons both read "Clear".
 * A matte swatch announced a raw hex with no word saying what the hex was.
 */
class SettingsSemanticsTest {
    @get:Rule
    val compose = createComposeRule()

    private val context = InstrumentationRegistry.getInstrumentation().targetContext

    /** The real screen over a private preferences file, hosted the way the app hosts it. */
    private fun showSettings() {
        compose.setContent {
            var settings by remember { mutableStateOf(AppSettings()) }
            val store = remember {
                ReaderPreferences(
                    context.getSharedPreferences(
                        "semantics-${UUID.randomUUID()}",
                        Context.MODE_PRIVATE,
                    ),
                )
            }
            StoryArcTheme(useDynamicColor = false) {
                SettingsScreen(
                    settings = settings,
                    onChange = { settings = it },
                    readerStore = store,
                    onReset = {},
                    onClose = {},
                )
            }
        }
    }

    private fun open(groupTitleRes: Int) {
        compose.onNodeWithText(context.getString(groupTitleRes)).performClick()
    }

    @Test
    fun theVolumeSwitchCarriesItsNameAndItsState() {
        showSettings()
        open(R.string.settings_reading)
        // One node holding both the label and the toggle state — which is what makes
        // the switch a named thing rather than a bare on/off beside a paragraph.
        val row = compose.onNodeWithText(context.getString(R.string.reading_volume_buttons))
        row.assertIsOff()
        row.performClick()
        row.assertIsOn()
    }

    @Test
    fun theAppearanceLinkSwitchCarriesItsNameAndItsState() {
        showSettings()
        open(R.string.settings_appearance)
        val row = compose.onNodeWithText(context.getString(R.string.appearance_link_theme))
        row.assertIsOff()
        row.performClick()
        row.assertIsOn()
    }

    @Test
    fun theChosenAppearanceAnnouncesItselfAsChosen() {
        showSettings()
        open(R.string.settings_appearance)
        compose.onNodeWithText(context.getString(R.string.appearance_system)).assertIsSelected()
    }

    @Test
    fun everyMatteSwatchSaysWhatItIsAndBlackSaysItIsTheDefault() {
        showSettings()
        open(R.string.settings_reading)
        SUGGESTED_BACKGROUNDS.forEach { hex ->
            compose.onNodeWithContentDescription(
                context.getString(R.string.reading_matte_swatch, hex),
            ).assertExists()
        }
        compose.onNodeWithContentDescription(context.getString(R.string.reading_matte_none))
            .assertIsSelected()
    }

    @Test
    fun theTwoClearButtonsCanBeToldApartByEar() {
        showSettings()
        open(R.string.settings_privacy)
        compose.onNodeWithContentDescription(context.getString(R.string.privacy_clear_cache))
            .assertExists()
        compose.onNodeWithContentDescription(context.getString(R.string.privacy_clear_history))
            .assertExists()
    }

    @Test
    fun searchingForASettingListsItWithItsGroupPath() {
        showSettings()
        compose.onNodeWithText(context.getString(R.string.settings_search))
            .performTextInput("volume")
        // The match row: the setting's own name, with the group it lives in beneath —
        // the "group path" clause, and what makes the match actionable.
        compose.onNodeWithText(context.getString(R.string.reading_volume_buttons))
            .assertIsDisplayed()
        compose.onNodeWithText(context.getString(R.string.settings_reading))
            .assertIsDisplayed()
    }

    @Test
    fun aGroupRowIsOneButtonCarryingItsSummary() {
        showSettings()
        // Merged by `clickableRow`, so the row is one node: title, summary and role
        // together. Split nodes would read as a heading beside an orphaned value.
        compose.onNodeWithText(context.getString(R.string.settings_appearance))
            .assert(SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Button))
            .assert(
                SemanticsMatcher("carries its summary") { node ->
                    node.config.getOrNull(SemanticsProperties.Text)?.any {
                        it.text == context.getString(R.string.appearance_system)
                    } == true
                },
            )
    }
}
