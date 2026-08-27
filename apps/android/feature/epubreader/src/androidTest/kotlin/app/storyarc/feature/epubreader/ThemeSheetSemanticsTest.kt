package app.storyarc.feature.epubreader

import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.test.platform.app.InstrumentationRegistry
import app.storyarc.core.designsystem.theme.StoryArcTheme
import app.storyarc.core.model.FontSizeStep
import app.storyarc.core.model.PageTransition
import app.storyarc.core.model.TransitionChoices
import app.storyarc.core.model.ReadingTheme
import app.storyarc.core.model.ScrollAxis
import app.storyarc.core.model.ThemeAxis
import app.storyarc.core.model.ThemePreset
import app.storyarc.core.model.sliderRange
import app.storyarc.core.model.values
import org.junit.Rule
import org.junit.Test

/**
 * What a screen reader learns from the theme sheet.
 *
 * `native-experience` requires every slider to carry an accessibility value, the
 * preset grid to announce which card is selected, and the size stepper to say its
 * position out of the total. None of that is visible in a screenshot, and
 * `uiautomator dump` reports every Compose slider as an unnamed `SeekBar` however
 * its semantics are set. A composition is the only place the question can be asked.
 */
class ThemeSheetSemanticsTest {
    @get:Rule
    val compose = createComposeRule()

    private val context = InstrumentationRegistry.getInstrumentation().targetContext

    private fun showSheet(preset: ThemePreset = ThemePreset.PAPER) {
        compose.setContent {
            StoryArcTheme(useDynamicColor = false) {
                ThemeSheet(
                    theme = ReadingTheme(preset),
                    values = preset.values,
                    brightness = 0.5f,
                    onAdopt = {},
                    onChange = { _, _ -> },
                    onSet = { _, _ -> },
                    onBrightness = {},
                    onRestore = {},
                    onLeavePublisherStyles = {},
                    onAdoptColours = { true },
                    onDiscardColours = {},
                    // Everything available. This suite is about what the sheet *says*, and
                    // an unavailable mode is a different assertion in a different test.
                    choices = TransitionChoices(
                        chosen = PageTransition.SLIDE,
                        axis = ScrollAxis.VERTICAL,
                        reduceMotion = false,
                        canCurl = true,
                        isReflowable = true,
                    ),
                    onChooseTransition = {},
                )
            }
        }
    }

    @Test
    fun everySliderSaysWhichAxisItIsAndWhatItReads() {
        showSheet()
        ThemeAxis.entries.filter { it.sliderRange != null }.forEach { axis ->
            val name = context.getString(axis.labelRes)
            compose.onNodeWithContentDescription(name)
                .assert(hasAStateDescription())
        }
    }

    @Test
    fun brightnessSaysWhatItReads() {
        showSheet()
        val name = context.getString(R.string.theme_brightness)
        compose.onNodeWithContentDescription(name).assert(hasAStateDescription())
    }

    @Test
    fun theChosenPresetAnnouncesItselfAsChosen() {
        showSheet(ThemePreset.CALM)
        compose.onNodeWithText(
            context.getString(ThemePreset.CALM.labelRes),
        ).assertIsSelected()
    }

    @Test
    fun theSizeStepperSaysItsPositionOutOfTheTotal() {
        val preset = ThemePreset.PAPER
        showSheet(preset)
        // The position, not only "larger": a reader who cannot see the dots has no
        // other way to know how much room is left on the ladder. Read from the
        // preset rather than written down, so re-tuning a preset's default size
        // cannot turn this into a test of a number nobody chose.
        val position = context.getString(
            R.string.theme_font_size_position,
            preset.values.fontSize.position + 1,
            FontSizeStep.count,
        )
        compose.onNode(
            SemanticsMatcher("content description contains \"$position\"") { node ->
                node.config.getOrNull(SemanticsProperties.ContentDescription)
                    ?.any { it.contains(position) } == true
            },
        ).assertExists()
    }

    private fun hasAStateDescription() = SemanticsMatcher("has a state description") { node ->
        node.config.getOrNull(SemanticsProperties.StateDescription)?.isNotEmpty() == true
    }
}
