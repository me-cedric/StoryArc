package app.storyarc.feature.reader

import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performClick
import app.storyarc.core.snapshots.FOLD_OUTER_QUALIFIERS
import app.storyarc.core.snapshots.Look
import app.storyarc.core.snapshots.catalogue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * Catalogue entry 15 on the Pixel Fold's outer display (2.5): the comic reader with its chrome up.
 *
 * A class of its own, not two cases in `Catalogue15ReaderChromeTest`: a case there with other
 * qualifiers made a later case's page decode fail in a full module run. Light and dark only,
 * because new images take the default text size.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34], qualifiers = FOLD_OUTER_QUALIFIERS)
class Catalogue15eReaderChromeFoldOuterTest {

    @get:Rule
    val compose = createComposeRule()

    @get:Rule
    val folder = TemporaryFolder()

    private fun draw(look: Look) {
        val model = FoldFixtures.model(folder.root)
        compose.catalogue(
            "15-reader-chrome-fold-outer",
            look,
            act = {
                loaded(model)
                // A centre tap toggles the chrome, so tap only while it is down.
                if (!shows("Menu")) onRoot().performClick()
                waitUntil(timeoutMillis = 5_000) { shows("Menu") }
            },
        ) { ReaderScreen(viewModel = model, onClose = {}) }
    }

    @Test
    fun light() = draw(Look.Light)

    @Test
    fun dark() = draw(Look.Dark)
}
