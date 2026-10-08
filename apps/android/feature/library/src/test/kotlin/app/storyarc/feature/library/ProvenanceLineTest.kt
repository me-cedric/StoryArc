package app.storyarc.feature.library

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import app.storyarc.core.designsystem.theme.StoryArcTheme
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * The provenance line is one whole sentence per state, and the second place is named
 * (`one-vocabulary-in-four-languages` 4.6, `close-the-audited-gaps` 15.10, O19).
 *
 * **Drawn, not only decided.** `PublicationProvenanceTest` pins which state a publication is
 * in; this pins the words each state draws, through [ProvenanceLine], so swapping the sentence
 * a state asks for fails here by name. iOS asserts the same in `ProvenanceSentenceTests`, and
 * `ReconciledWordingTest` holds the four languages of both platforms to one table.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34], qualifiers = "w411dp-h891dp")
class ProvenanceLineTest {

    @get:Rule
    val compose = createComposeRule()

    private fun show(provenance: Provenance) {
        compose.setContent { StoryArcTheme { ProvenanceLine(provenance) } }
    }

    private fun library(readiness: Provenance.Readiness, alsoIn: String? = null) = Provenance(
        place = Provenance.Place.LIBRARY,
        libraryName = "Home NAS",
        readiness = readiness,
        alsoIn = alsoIn,
    )

    @Test
    fun `a copy on the device says it is readable with no network`() {
        show(Provenance(Provenance.Place.DEVICE, null, Provenance.Readiness.READY, alsoIn = null))
        compose.onNodeWithText("On this device, readable with no network").assertIsDisplayed()
    }

    @Test
    fun `a library that has not sent the copy says so, naming the library`() {
        show(library(Provenance.Readiness.NOT_DOWNLOADED))
        compose.onNodeWithText("From Home NAS, not on this device").assertIsDisplayed()
    }

    @Test
    fun `a library that is not answering says so, naming the library`() {
        show(library(Provenance.Readiness.SOURCE_AWAY))
        compose.onNodeWithText("From Home NAS, not answering right now").assertIsDisplayed()
    }

    @Test
    fun `a publication nobody holds says it is in no library you added`() {
        show(Provenance(Provenance.Place.UNATTRIBUTED, null, Provenance.Readiness.NOT_DOWNLOADED, alsoIn = null))
        compose.onNodeWithText("Not in a library you added, not on this device").assertIsDisplayed()
    }

    @Test
    fun `the second place is a sentence of its own that names it`() {
        show(library(Provenance.Readiness.NOT_DOWNLOADED, alsoIn = "Cellar"))
        compose.onNodeWithText("From Home NAS, not on this device").assertIsDisplayed()
        compose.onNodeWithText("Also in Cellar").assertIsDisplayed()
    }
}
