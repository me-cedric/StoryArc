package app.storyarc.feature.settings

import androidx.compose.ui.test.assertIsNotSelected
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.isSelectable
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import app.storyarc.core.designsystem.theme.StoryArcTheme
import app.storyarc.core.model.AppSettings
import app.storyarc.core.model.ThemePreset
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * The pair [AppSettings.linkReadingThemeToAppearance] adopts.
 *
 * `ebook-reader` / *Theme follows appearance*: the switch lands on "the light and dark
 * reading themes the reader chose as their pair, not to an arbitrary default" -- so the
 * pair has to be choosable, and a reader who has not turned the link on has nothing to
 * choose. iOS mirrors this suite over `AppearanceSettings.swift`.
 *
 * [LinkedPresetPicker] itself is tested on its own, one list at a time, rather than
 * through two of them side by side: both halves of the pair offer the same six names, so
 * two instances put "Calm" on screen twice with nothing in the text itself to tell a test
 * which row belongs to which half. [AppearanceGroupLinkedPresetTest] below covers the one
 * thing a lone picker cannot: that [AppearanceGroup] wires each half to its own field.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class LinkedPresetPickerTest {

    @get:Rule
    val compose = createComposeRule()

    @Test
    fun `the row for the current preset is marked selected and no other is`() {
        compose.setContent {
            StoryArcTheme {
                LinkedPresetPicker(
                    titleRes = R.string.appearance_link_theme_light,
                    selected = ThemePreset.CALM,
                    onSelect = {},
                )
            }
        }

        compose.onNode(hasText("Calm") and isSelectable()).assertIsSelected()
        compose.onNode(hasText("Paper") and isSelectable()).assertIsNotSelected()
    }

    @Test
    fun `tapping a preset reports that preset and no other`() {
        var chosen: ThemePreset? = null
        compose.setContent {
            StoryArcTheme {
                LinkedPresetPicker(
                    titleRes = R.string.appearance_link_theme_dark,
                    selected = ThemePreset.QUIET,
                    onSelect = { chosen = it },
                )
            }
        }

        compose.onNodeWithText("Focus").performClick()

        assertEquals(ThemePreset.FOCUS, chosen)
    }
}

/**
 * Where [LinkedPresetPicker] meets the setting it is wired to.
 *
 * `ebook-reader` / *Theme follows appearance*: the pair is a stored setting with two
 * independent halves, so the row this test covers is whether [AppearanceGroup] shows and
 * hides the pair with the link, and starts each half on its own stored preset -- not
 * whether a tap lands on the right one, which [LinkedPresetPickerTest] already answers for
 * the one shape both halves share.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class AppearanceGroupLinkedPresetTest {

    @get:Rule
    val compose = createComposeRule()

    @Test
    fun `the pair is hidden until the reader turns the link on`() {
        compose.setContent {
            StoryArcTheme { AppearanceGroup(settings = AppSettings(), onChange = {}) }
        }

        compose.onNodeWithText("Light theme").assertDoesNotExist()
        compose.onNodeWithText("Dark theme").assertDoesNotExist()
    }

    @Test
    fun `the pair appears once the link is on, each half on its own stored preset`() {
        val settings = AppSettings(
            linkReadingThemeToAppearance = true,
            lightReadingTheme = ThemePreset.BOLD,
            darkReadingTheme = ThemePreset.CALM,
        )
        compose.setContent {
            StoryArcTheme { AppearanceGroup(settings = settings, onChange = {}) }
        }

        compose.onNodeWithText("Light theme").assertExists()
        compose.onNodeWithText("Dark theme").assertExists()

        // Two lists, one per half of the pair, each offering all six presets -- so every
        // preset name appears twice and the index is what tells the two apart. The light
        // list is built first.
        compose.onAllNodes(hasText("Bold") and isSelectable())[0].assertIsSelected()
        compose.onAllNodes(hasText("Calm") and isSelectable())[1].assertIsSelected()
    }

    // Tall enough that both lists are laid out inside the window. A row below the window's
    // edge measures to nothing, and a tap on it lands on whatever row is drawn there instead.
    @Test
    @Config(qualifiers = "w411dp-h2400dp")
    fun `a tap in one half of the pair writes that half and leaves the other alone`() {
        val settings = AppSettings(linkReadingThemeToAppearance = true)
        val written = mutableListOf<AppSettings>()
        compose.setContent {
            StoryArcTheme { AppearanceGroup(settings = settings, onChange = { written += it }) }
        }

        compose.onAllNodes(hasText("Focus") and isSelectable())[0].performClick()
        compose.onAllNodes(hasText("Calm") and isSelectable())[1].performClick()

        assertEquals(ThemePreset.FOCUS, written[0].lightReadingTheme)
        assertEquals(ThemePreset.QUIET, written[0].darkReadingTheme)
        assertEquals(ThemePreset.PAPER, written[1].lightReadingTheme)
        assertEquals(ThemePreset.CALM, written[1].darkReadingTheme)
    }
}
