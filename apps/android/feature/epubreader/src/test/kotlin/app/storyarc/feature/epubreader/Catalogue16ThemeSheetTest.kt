package app.storyarc.feature.epubreader

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.junit4.v2.createComposeRule
import app.storyarc.core.model.ReadingTheme
import app.storyarc.core.model.ThemePreset
import app.storyarc.core.model.values
import app.storyarc.core.snapshots.CATALOGUE_QUALIFIERS
import app.storyarc.core.snapshots.Look
import app.storyarc.core.snapshots.catalogue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * Catalogue entry 16: the reading theme sheet, level one. It shows a live preview, the six
 * presets with Paper chosen, and the action that opens the axes.
 *
 * The sheet content is drawn on a surface of the sheet's container colour. The sheet's own
 * scrim and drag handle belong to the system window and are not drawn here. The live preview is a
 * web view, which Robolectric does not draw, so its box is empty in the picture.
 */
@OptIn(ExperimentalMaterial3Api::class)
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34], qualifiers = CATALOGUE_QUALIFIERS)
class Catalogue16ThemeSheetTest {

    @get:Rule
    val compose = createComposeRule()

    private fun draw(look: Look) = compose.catalogue("16-theme-sheet", look) {
        Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.surfaceContainerLow) {
            ThemeSheet(
                theme = ReadingTheme(ThemePreset.PAPER),
                values = ThemePreset.PAPER.values,
                onAdopt = {},
                onAdoptColours = { true },
                onCustomise = {},
                chapter = "Chapter Two",
                excerpt = "The tide came in slowly, and the harbour lights went out one by one.",
            )
        }
    }

    @Test
    fun light() = draw(Look.Light)

    @Test
    fun dark() = draw(Look.Dark)
}
