package app.storyarc.feature.library

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.unit.dp
import app.storyarc.core.catalogue.CoverCandidate
import app.storyarc.core.catalogue.CoverFetched
import app.storyarc.core.catalogue.CoverLookupCache
import app.storyarc.core.catalogue.CoverLookupClient
import app.storyarc.core.catalogue.CoverTransport
import app.storyarc.core.model.CoverTitleProvider
import app.storyarc.core.snapshots.CATALOGUE_QUALIFIERS
import app.storyarc.core.snapshots.Fixtures
import app.storyarc.core.snapshots.Look
import app.storyarc.core.snapshots.catalogue
import java.io.ByteArrayOutputStream
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * Catalogue entry 5c: the cover chooser with candidate pictures. The three title catalogues
 * answer, each row draws its picture, and nothing is chosen until the reader taps.
 *
 * The transport is a recording one, because the lookup hosts allow https only and the emulator
 * on this network cannot validate their certificates. The bottom sheet's own frame is not drawn:
 * Robolectric does not draw a window, so the content sits on the sheet's surface colour.
 */
@OptIn(ExperimentalTestApi::class)
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34], qualifiers = CATALOGUE_QUALIFIERS)
class Catalogue05cCoverChooserCandidatesTest {

    @get:Rule
    val compose = createComposeRule()

    @get:Rule
    val folder = TemporaryFolder()

    private val book = CatalogueShelf.publications[0]

    private val candidates = listOf(
        CoverCandidate(
            "Harbour Lights",
            "https://covers.openlibrary.org/b/id/1-L.jpg",
            CoverTitleProvider.OPEN_LIBRARY,
            "Mara Quill, 2014",
        ),
        CoverCandidate(
            "Harbour Lights, volume 1",
            "https://s4.anilist.co/file/anilistcdn/media/manga/cover/2.jpg",
            CoverTitleProvider.ANILIST,
            "2016",
        ),
        CoverCandidate(
            "The Harbour Lights",
            "https://cdn.mangaupdates.com/image/i3.jpg",
            CoverTitleProvider.MANGA_UPDATES,
            "2019",
        ),
    )

    private fun client(): CoverLookupClient {
        val pictures = candidates.mapIndexed { index, candidate ->
            candidate.imageUrl to ByteArrayOutputStream().also {
                Fixtures.cover(index + 1, 200, 300).compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it)
            }.toByteArray()
        }.toMap()
        val transport = CoverTransport { request -> CoverFetched(200, pictures.getValue(request.url), request.url) }
        return CoverLookupClient({ true }, CoverLookupCache(folder.newFile()), transport)
    }

    private fun draw(look: Look) = compose.catalogue(
        "05c-cover-chooser-candidates",
        look,
        act = {
            waitUntil(timeoutMillis = 5_000) {
                onAllNodesWithTag(CANDIDATE_PICTURE_TAG, useUnmergedTree = true).fetchSemanticsNodes().size == 3
            }
        },
    ) {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.BottomCenter) {
            Box(
                Modifier
                    .fillMaxWidth()
                    .background(MaterialTheme.colorScheme.surfaceContainerLow, RoundedCornerShape(topStart = 28.dp, topEnd = 28.dp))
                    .padding(top = 24.dp, bottom = 24.dp),
            ) {
                CoverFinderContent(
                    publication = book,
                    store = { true },
                    onDone = {},
                    client = client(),
                    search = { _, _ -> candidates },
                )
            }
        }
    }

    @Test
    fun light() = draw(Look.Light)

    @Test
    fun dark() = draw(Look.Dark)
}
