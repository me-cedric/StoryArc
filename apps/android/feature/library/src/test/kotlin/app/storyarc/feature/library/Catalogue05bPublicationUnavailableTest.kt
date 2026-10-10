package app.storyarc.feature.library

import androidx.compose.ui.test.junit4.v2.createComposeRule
import app.storyarc.core.snapshots.CATALOGUE_QUALIFIERS
import app.storyarc.core.snapshots.Look
import app.storyarc.core.snapshots.catalogue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/** Catalogue entry 5b: a publication page whose file is not on this device. */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34], qualifiers = CATALOGUE_QUALIFIERS)
class Catalogue05bPublicationUnavailableTest {

    @get:Rule
    val compose = createComposeRule()

    private fun draw(look: Look) = compose.catalogue("05b-publication-unavailable", look) {
        val book = CatalogueShelf.publications[0]
        val model = CatalogueShelf.viewModel(withCovers = true)
        PublicationDetailScreen(
            publication = book,
            viewModel = model,
            isOnDevice = false,
            onRead = { _, _ -> },
            onOpenPage = {},
            onMark = { _, _ -> },
            onBack = {},
        )
    }

    @Test
    fun light() = draw(Look.Light)

    @Test
    fun dark() = draw(Look.Dark)

    @Test
    fun largest() = draw(Look.Largest)
}
