package app.storyarc.feature.library

import android.graphics.Bitmap
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import app.storyarc.core.catalogue.CoverCandidate
import app.storyarc.core.catalogue.CoverFetch
import app.storyarc.core.catalogue.CoverFetched
import app.storyarc.core.catalogue.CoverLookupCache
import app.storyarc.core.catalogue.CoverLookupClient
import app.storyarc.core.catalogue.CoverTransport
import app.storyarc.core.designsystem.theme.StoryArcTheme
import app.storyarc.core.model.CoverTitleProvider
import java.io.ByteArrayOutputStream
import java.net.URI
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * The candidate sheet shows each picture, and shows it through the client.
 *
 * Task 6.3 of `cover-for-every-publication`. The sheet drew no picture, so the reader chose
 * blind, and its rows were keyed on the picture's address, which two equal answers share. A
 * lazy list that meets a key twice throws, so a title two catalogues answered the same way took
 * the screen down. iOS's `CoverCandidateSheetPicturesTests` is the twin of this file.
 */
@OptIn(ExperimentalTestApi::class)
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34])
class CoverCandidateSheetPicturesTest {

    @get:Rule
    val compose = createComposeRule()

    @get:Rule
    val folder = TemporaryFolder()

    private val asked = mutableListOf<CoverFetch>()

    private val listed = CoverCandidate(
        title = "Fine Print",
        imageUrl = "https://covers.openlibrary.org/b/id/1-L.jpg",
        provider = CoverTitleProvider.OPEN_LIBRARY,
    )
    private val unlisted = listed.copy(title = "Elsewhere", imageUrl = "https://tracker.example/c.jpg")

    private fun png(): ByteArray = ByteArrayOutputStream().also {
        Bitmap.createBitmap(8, 12, Bitmap.Config.ARGB_8888).compress(Bitmap.CompressFormat.PNG, 100, it)
    }.toByteArray()

    private fun client(enabled: Boolean = true): CoverLookupClient {
        val picture = png()
        val transport = CoverTransport { request ->
            asked += request
            CoverFetched(200, picture, request.url)
        }
        return CoverLookupClient({ enabled }, CoverLookupCache(folder.newFile()), transport)
    }

    private fun show(candidates: List<CoverCandidate>, client: CoverLookupClient, onChoose: (CoverCandidate) -> Unit = {}) {
        compose.setContent {
            StoryArcTheme { CoverCandidateSheet(candidates, onChoose, client = client) }
        }
    }

    private fun pictures() = compose.onAllNodesWithTag(CANDIDATE_PICTURE_TAG, useUnmergedTree = true).fetchSemanticsNodes().size

    @Test
    fun `a candidate's picture is drawn beside its title`() {
        show(listOf(listed), client())

        compose.waitUntil(timeoutMillis = 5_000) { pictures() == 1 }

        compose.onNodeWithText("Fine Print").assertExists()
        assertEquals(listOf(listed.imageUrl), asked.map { it.url })
    }

    @Test
    fun `a picture from a host the setting does not name is not requested and not drawn`() {
        show(listOf(listed, unlisted), client())

        compose.waitUntil(timeoutMillis = 5_000) { pictures() == 1 }
        compose.waitForIdle()

        assertEquals(1, pictures())
        assertTrue(
            "asked ${asked.map { it.url }}",
            asked.none { URI(it.url).host == "tracker.example" },
        )
        compose.onNodeWithText("Elsewhere").assertExists()
    }

    @Test
    fun `two equal answers are two rows and do not take the list down`() {
        show(listOf(listed, listed, listed.copy(provider = CoverTitleProvider.ANILIST)), client())

        compose.waitUntil(timeoutMillis = 5_000) { pictures() == 3 }

        assertEquals(3, pictures())
    }

    @Test
    fun `no picture is requested while the setting is off, and the row can still be chosen`() {
        var chosen: CoverCandidate? = null
        show(listOf(listed), client(enabled = false)) { chosen = it }
        compose.waitForIdle()

        compose.onNodeWithText("Fine Print").performClick()

        assertTrue(asked.isEmpty())
        assertEquals(0, pictures())
        assertEquals(listed, chosen)
    }
}
