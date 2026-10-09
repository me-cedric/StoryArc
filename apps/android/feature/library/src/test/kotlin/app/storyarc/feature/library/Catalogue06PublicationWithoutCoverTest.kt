package app.storyarc.feature.library

import androidx.compose.ui.test.junit4.v2.createComposeRule
import app.storyarc.core.snapshots.CATALOGUE_QUALIFIERS
import app.storyarc.core.snapshots.Look
import app.storyarc.core.snapshots.brandAccentText
import app.storyarc.core.snapshots.catalogue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/** Catalogue entry 6: a publication page with no cover, so the coverless well stands in for it. */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34], qualifiers = CATALOGUE_QUALIFIERS)
class Catalogue06PublicationWithoutCoverTest {

    @get:Rule
    val compose = createComposeRule()

    private fun draw(look: Look) = compose.catalogue("06-publication-without-cover", look, listOf(brandAccentText("Add a cover"))) {
        val book = CatalogueShelf.publications[0]
        val model = CatalogueShelf.viewModel(withCovers = false)
        PublicationDetailScreen(
            publication = book,
            viewModel = model,
            isOnDevice = true,
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
}
