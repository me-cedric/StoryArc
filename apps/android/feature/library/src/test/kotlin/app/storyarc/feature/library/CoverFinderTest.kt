package app.storyarc.feature.library

import android.app.Application
import android.graphics.Bitmap
import androidx.activity.ComponentActivity
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.catalogue.CoverCandidate
import app.storyarc.core.catalogue.CoverFetch
import app.storyarc.core.catalogue.CoverFetched
import app.storyarc.core.catalogue.CoverLookupCache
import app.storyarc.core.catalogue.CoverLookupClient
import app.storyarc.core.catalogue.CoverTransport
import app.storyarc.core.designsystem.theme.StoryArcTheme
import app.storyarc.core.format.CoverOverrideStore
import app.storyarc.core.model.AppSettings
import app.storyarc.core.model.CoverTitleProvider
import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.persistence.SettingsStore
import java.io.ByteArrayOutputStream
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * Tasks 6.2, 4.1 and 3.3 of `cover-for-every-publication`: the publication page offers the
 * title search and the web search, and a tap on a candidate is the only way one is adopted.
 *
 * The first three tests compose the real [rememberCoverChoice] against the real settings file,
 * so the switch they flip is the one the page reads. iOS's `CoverFinderTests` is the twin.
 */
@OptIn(ExperimentalTestApi::class)
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34], qualifiers = "w411dp-h891dp")
class CoverFinderTest {

    @get:Rule
    val compose = createAndroidComposeRule<ComponentActivity>()

    @get:Rule
    val folder = TemporaryFolder()

    private val application: Application get() = ApplicationProvider.getApplicationContext()

    private val publication = Publication(
        identity = PublicationIdentity(contentDigest = "finder"),
        format = PublicationFormat.EPUB,
        displayTitle = "Fine Print",
        authors = listOf("Ada"),
        origin = MetadataOrigin.INFERRED,
    )

    private val candidate = CoverCandidate(
        title = "Fine Print",
        imageUrl = "https://covers.openlibrary.org/b/id/1-L.jpg",
        provider = CoverTitleProvider.OPEN_LIBRARY,
    )

    @After
    fun restore() {
        SettingsStore.open(application).reset()
    }

    private fun lookUp(on: Boolean) {
        SettingsStore.open(application).save(AppSettings.Defaults.copy(lookUpMissingCovers = on))
    }

    private fun showControls() {
        val viewModel = LibraryViewModel(application)
        compose.setContent {
            StoryArcTheme {
                val choice = rememberCoverChoice(viewModel, publication)
                DetailHero(
                    publication = publication,
                    cover = null,
                    accent = null,
                    layout = DetailHeroLayout(isSideBySide = false, coverHeight = androidx.compose.ui.unit.Dp(360f)),
                    coverChoice = choice,
                ) {}
            }
        }
        compose.waitForIdle()
        // The rows live in the cover's menu, which the visible label opens.
        compose.onNodeWithText("Add a cover").performClick()
    }

    @Test
    fun `while the lookup is off there is no title search and the web search is still there`() {
        lookUp(false)

        showControls()

        compose.onNodeWithText(FIND).assertDoesNotExist()
        compose.onNodeWithText(WEB).assertIsDisplayed()
    }

    @Test
    fun `while the lookup is on both are offered`() {
        lookUp(true)

        showControls()

        compose.onNodeWithText(FIND).assertIsDisplayed()
        compose.onNodeWithText(WEB).assertIsDisplayed()
    }

    @Test
    fun `the web search opens the browser at an image search for the title and sends nothing itself`() {
        lookUp(false)
        showControls()

        compose.onNodeWithText(WEB).performClick()

        val started = shadowOf(compose.activity).nextStartedActivity
        assertNotNull(started)
        assertEquals("duckduckgo.com", started.data?.host)
        assertTrue(started.data.toString().contains("Fine%20Print") || started.data.toString().contains("Fine+Print"))
    }

    private fun png(): ByteArray = ByteArrayOutputStream().also {
        Bitmap.createBitmap(8, 12, Bitmap.Config.ARGB_8888).compress(Bitmap.CompressFormat.PNG, 100, it)
    }.toByteArray()

    private fun client(status: Int = 200): CoverLookupClient {
        val picture = png()
        val transport = CoverTransport { request ->
            CoverFetched(status, if (status == 200) picture else ByteArray(0), request.url)
        }
        return CoverLookupClient({ true }, CoverLookupCache(folder.newFile()), transport)
    }

    private fun showCandidates(client: CoverLookupClient, viewModel: LibraryViewModel, done: (Boolean) -> Unit) {
        compose.setContent {
            StoryArcTheme {
                CoverFinderContent(
                    publication = publication,
                    store = { viewModel.setCover(it, publication) },
                    onDone = done,
                    client = client,
                    search = { _, _ -> listOf(candidate) },
                )
            }
        }
    }

    private fun stored(viewModel: LibraryViewModel) =
        CoverOverrideStore(viewModel.coverOverrideDirectory).file(publication)

    @Test
    fun `a candidate is shown and nothing is adopted until the reader taps it`() {
        val viewModel = LibraryViewModel(application)
        var done: Boolean? = null
        showCandidates(client(), viewModel) { done = it }

        compose.waitUntil(timeoutMillis = 5_000) {
            compose.onAllNodesWithText("Fine Print").fetchSemanticsNodes().size > 0
        }
        compose.waitForIdle()

        assertNull("a candidate was adopted before any tap", stored(viewModel))
        assertNull(done)
    }

    @Test
    fun `a tap on a candidate stores its picture as the chosen cover`() {
        val viewModel = LibraryViewModel(application)
        var done: Boolean? = null
        showCandidates(client(), viewModel) { done = it }
        compose.waitUntil(timeoutMillis = 5_000) { compose.onAllNodesWithText("Fine Print").fetchSemanticsNodes().size > 0 }

        compose.onNodeWithText("Fine Print").performClick()
        compose.waitUntil(timeoutMillis = 5_000) { done != null }

        assertEquals(true, done)
        assertNotNull("the tap did not reach the override store", stored(viewModel))
    }

    @Test
    fun `a picture that does not arrive leaves the cover as it was and says so`() {
        val viewModel = LibraryViewModel(application)
        var done: Boolean? = null
        showCandidates(client(status = 404), viewModel) { done = it }
        compose.waitUntil(timeoutMillis = 5_000) { compose.onAllNodesWithText("Fine Print").fetchSemanticsNodes().size > 0 }

        compose.onNodeWithText("Fine Print").performClick()
        compose.waitUntil(timeoutMillis = 5_000) { done != null }

        assertEquals(false, done)
        assertNull(stored(viewModel))
    }

    private companion object {
        const val FIND = "Find a cover"
        const val WEB = "Find a cover on the web"
    }
}
