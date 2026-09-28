package app.storyarc.feature.settings

import androidx.compose.ui.test.assertIsNotSelected
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.isSelectable
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.designsystem.theme.StoryArcTheme
import app.storyarc.core.persistence.ReaderPreferences
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * `reading-themes`, *Changing the global default*: the row and the ring must move the
 * moment a reader taps, not on the next unrelated recomposition.
 *
 * Before this, `ReadingDefaults` read `store.themes()` as a plain value with no Compose
 * state, so a tap called `store.save` and nothing here observed it — the change was on
 * disk and invisible on screen until something else forced a recomposition.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class ReadingDefaultsTest {

    @get:Rule
    val compose = createComposeRule()

    private fun store(): ReaderPreferences {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val prefs = context.getSharedPreferences(
            "ReadingDefaultsTest-${System.nanoTime()}",
            android.content.Context.MODE_PRIVATE,
        )
        return ReaderPreferences(prefs)
    }

    @Test
    fun `a tap moves the radio button without any other recomposition`() {
        compose.setContent {
            StoryArcTheme { ReadingDefaults(store = store()) }
        }

        compose.onNode(hasText("Calm") and isSelectable()).assertIsNotSelected()

        compose.onNodeWithText("Calm").performClick()

        compose.onNode(hasText("Calm") and isSelectable()).assertIsSelected()
        compose.onNode(hasText("Paper") and isSelectable()).assertIsNotSelected()
    }

    @Test
    fun `the fixed-layout scope offers no preset, only its own colour`() {
        compose.setContent {
            StoryArcTheme { ReadingDefaults(store = store()) }
        }

        // `reading-themes`: a comic has no typography for a preset to change, so the
        // fixed-layout scope's own section header ("Comics and picture books") is gone —
        // only the matte section ("Matte") remains for it.
        compose.onNodeWithText("Comics and picture books").assertDoesNotExist()
    }

    @Test
    fun `choosing a preset persists it, so the next read sees it`() {
        val store = store()

        compose.setContent {
            StoryArcTheme { ReadingDefaults(store = store) }
        }

        compose.onNodeWithText("Calm").performClick()

        assertEquals(
            app.storyarc.core.model.ThemePreset.CALM,
            store.themes().default(app.storyarc.core.model.ThemeScope.REFLOWABLE).theme.preset,
        )
    }
}
