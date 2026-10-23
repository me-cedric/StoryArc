package app.storyarc.feature.library

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import app.storyarc.core.model.Download
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
 * Catalogue entry 5d: a publication page while its copy travels. The page draws the transfer
 * record: a "Downloading" label and the fraction the feed's stated length allows, and no read
 * in the hero (`publication-detail` 6.2 and 6.5 frame 2; task 28.3 of `close-the-audited-gaps`).
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34], qualifiers = CATALOGUE_QUALIFIERS)
class Catalogue05dPublicationCopyTravellingTest {

    @get:Rule
    val compose = createComposeRule()

    private fun draw(look: Look) = compose.catalogue(
        "05d-publication-copy-travelling",
        look,
        act = { onNodeWithText("Downloading").assertIsDisplayed() },
    ) {
        val book = CatalogueShelf.publications[0]
        val model = CatalogueShelf.viewModel(withCovers = true)
        PublicationDetailScreen(
            publication = book,
            viewModel = model,
            isOnDevice = false,
            transfer = Download(
                id = book.id,
                title = book.displayTitle,
                remote = "https://books.example/harbour-lights.epub",
                mediaType = "application/epub+zip",
                state = Download.State.Running,
                expectedBytes = 4_000_000,
                downloadedBytes = 1_400_000,
            ),
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
