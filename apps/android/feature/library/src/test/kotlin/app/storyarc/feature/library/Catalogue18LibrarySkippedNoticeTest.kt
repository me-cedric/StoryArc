package app.storyarc.feature.library

import androidx.compose.ui.test.junit4.v2.createComposeRule
import app.storyarc.core.format.SkipReason
import app.storyarc.core.model.LibraryLayout
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
 * Catalogue entry 18: the library after a scan skipped one file, with the notice that names it.
 * Android keeps its Material 3 notice, with two text buttons.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34], qualifiers = CATALOGUE_QUALIFIERS)
class Catalogue18LibrarySkippedNoticeTest {

    @get:Rule
    val compose = createComposeRule()

    private fun draw(look: Look) {
        val model = CatalogueShelf.viewModel(CatalogueShelf.publications)
        model.setLayout(LibraryLayout.GRID)
        // After the first draw: the screen's own start-up settles the skipped set, so a value
        // set before it is replaced by an empty one.
        compose.catalogue(
            "18-library-skipped-notice",
            look,
            act = {
                model._skipped.value = SkippedPublications().settling(
                    listOf(SkippedPublications.Entry("Broken Transfer.cbz", SkipReason.ArchiveUnreadable)),
                )
            },
        ) { LibraryScreen(viewModel = model) }
    }

    @Test
    fun light() = draw(Look.Light)

    @Test
    fun dark() = draw(Look.Dark)

    @Test
    fun largest() = draw(Look.Largest)
}
