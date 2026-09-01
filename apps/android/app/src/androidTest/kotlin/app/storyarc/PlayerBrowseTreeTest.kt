package app.storyarc

import android.content.ComponentName
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.session.LibraryResult
import androidx.media3.session.MediaBrowser
import androidx.media3.session.SessionToken
import androidx.test.platform.app.InstrumentationRegistry
import app.storyarc.core.playback.PlaybackService
import com.google.common.collect.ImmutableList
import com.google.common.util.concurrent.ListenableFuture
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.concurrent.TimeUnit

/**
 * The tree a car's head unit reads, asked for from outside the app.
 *
 * `design.md`: "an audiobook player that cannot be driven from a car is missing its best
 * use", and the service has been a `MediaLibraryService` with an `automotive_app_desc.xml`
 * since §3. What it did not have was a tree: `onGetLibraryRoot` was unimplemented, so
 * media3's default answered an error and a head unit that had found the app in its launcher
 * could drive what was already playing and start nothing.
 *
 * **Through a real `MediaBrowser`**, for the same reason `PlayerServiceIsDeclaredTest` asks
 * the `PackageManager`: a callback returning the right value in a unit test proves nothing
 * about a session a browser can actually connect to and query. This binds to the service the
 * way a car does.
 *
 * **Every `MediaController` call goes to the main thread and every wait comes off it.**
 * media3 checks the calling thread and throws otherwise, and blocking the main thread on a
 * future the main thread has to complete is a deadlock rather than a failure — which is why
 * the two are split rather than wrapped together.
 */
class PlayerBrowseTreeTest {

    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.targetContext

    /** Runs [body] on the main thread and hands its future back to be waited on here. */
    private fun <T> onMain(body: () -> T): T {
        var value: Result<T>? = null
        instrumentation.runOnMainSync { value = runCatching(body) }
        return requireNotNull(value).getOrThrow()
    }

    private fun <T> browsing(body: (MediaBrowser) -> ListenableFuture<T>): T {
        val token = SessionToken(context, ComponentName(context, PlaybackService::class.java))
        val browser = onMain { MediaBrowser.Builder(context, token).buildAsync() }
            .get(TIMEOUT_SECONDS, TimeUnit.SECONDS)
        return try {
            onMain { body(browser) }.get(TIMEOUT_SECONDS, TimeUnit.SECONDS)
        } finally {
            onMain { browser.release() }
        }
    }

    @Test
    fun aHeadUnitIsGivenARootRatherThanAnError() {
        val result: LibraryResult<MediaItem> = browsing { it.getLibraryRoot(null) }

        assertEquals("the root is refused, so nothing can be browsed", 0, result.resultCode)
        val root = requireNotNull(result.value)
        assertEquals("a car has to be able to open it", true, root.mediaMetadata.isBrowsable)
        assertEquals(
            "a car lays out a list of books differently from a wall of album art",
            MediaMetadata.MEDIA_TYPE_FOLDER_AUDIO_BOOKS,
            root.mediaMetadata.mediaType,
        )
        assertTrue("the root's id has to be stable, because a car caches it", root.mediaId.isNotEmpty())
    }

    /**
     * The root's children answer, whether or not there is anything to carry on with.
     *
     * A car showing an empty list is a car saying there is nothing to continue, which is
     * true on a device that has not played a book. An error is a car showing a failure, and
     * that is what an unimplemented callback produced.
     */
    @Test
    fun theRootsChildrenAreAnAnswerRatherThanAFailure() {
        val result: LibraryResult<ImmutableList<MediaItem>> = browsing {
            it.getChildren(PlaybackService.ROOT_ID, 0, PAGE, null)
        }

        assertEquals(0, result.resultCode)
        assertNotNull("the children came back as an error rather than as a list", result.value)
    }

    private companion object {
        const val PAGE = 20
        const val TIMEOUT_SECONDS = 10L
    }
}
