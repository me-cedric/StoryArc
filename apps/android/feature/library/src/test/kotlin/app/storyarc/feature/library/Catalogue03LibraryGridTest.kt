package app.storyarc.feature.library

import androidx.compose.ui.test.junit4.v2.createComposeRule
import app.storyarc.core.model.LibraryLayout
import app.storyarc.core.snapshots.CATALOGUE_QUALIFIERS
import app.storyarc.core.snapshots.FOLD_OUTER_QUALIFIERS
import app.storyarc.core.snapshots.Look
import app.storyarc.core.snapshots.catalogue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/** Catalogue entry 3: the library as a grid of covers. */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34], qualifiers = CATALOGUE_QUALIFIERS)
class Catalogue03LibraryGridTest {

    @get:Rule
    val compose = createComposeRule()

    private fun draw(look: Look, entry: String = "03-library-grid") = compose.catalogue(entry, look) {
        val model = CatalogueShelf.viewModel(CatalogueShelf.publications)
        model.setLayout(LibraryLayout.GRID)
        LibraryScreen(viewModel = model)
    }

    @Test
    fun light() = draw(Look.Light)

    @Test
    fun dark() = draw(Look.Dark)

    @Test
    fun largest() = draw(Look.Largest)

    /** 2.5: the Pixel Fold's outer display. Light and dark only: new images take the default text size. */
    @Test
    @Config(qualifiers = FOLD_OUTER_QUALIFIERS)
    fun foldOuterLight() = draw(Look.Light, "03-library-grid-fold-outer")

    @Test
    @Config(qualifiers = FOLD_OUTER_QUALIFIERS)
    fun foldOuterDark() = draw(Look.Dark, "03-library-grid-fold-outer")
}
