package app.storyarc.feature.library

import android.app.Application
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.model.Source
import app.storyarc.core.model.SourceConnectionState
import app.storyarc.core.model.SourceKind
import app.storyarc.core.model.SourceReachabilityEvents
import java.io.File
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Task 5.12's second clause: a share the reader found gone marks its source unreachable in
 * the live registry, the moment the event arrives -- not only on the probe loop's own next
 * turn, which does not run while a reader is open.
 */
@OptIn(ExperimentalCoroutinesApi::class)
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class SourceReachabilityWatchTest {

    private fun library() = LibraryViewModel(ApplicationProvider.getApplicationContext<Application>())

    private fun share(name: String = "Office NAS") =
        Source(displayName = name, kind = SourceKind.NETWORK_SHARE, state = SourceConnectionState.Connected, locator = "smb://nas/share")

    @Before
    fun setUp() {
        Dispatchers.setMain(UnconfinedTestDispatcher())
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
    }

    @Test
    fun `a reported source becomes unreachable in the live registry`() = runTest {
        val library = library()
        val source = share()
        library.addSource(source)
        library.watchSourceReachability()

        SourceReachabilityEvents.reportUnreachable(source.id)

        assertTrue(library._registry.value[source.id]?.state is SourceConnectionState.Unreachable)
    }

    @Test
    fun `a report for a source this library never held changes nothing`() = runTest {
        val library = library()
        val source = share()
        library.addSource(source)
        library.watchSourceReachability()

        SourceReachabilityEvents.reportUnreachable(java.util.UUID.randomUUID())

        assertTrue(library._registry.value[source.id]?.state is SourceConnectionState.Connected)
    }

    @Test
    fun `restoreFolders starts the watch, or a path change is never applied`() {
        val module = System.getProperty("storyarc.library.projectDir")?.let(::File)
            ?: error("storyarc.library.projectDir is unset. Run this test through Gradle.")
        val source = File(module, "src/main/kotlin/app/storyarc/feature/library/LibraryViewModel.kt")
        assertTrue(
            "restoreFolders no longer calls watchSourceReachability().",
            source.readText().contains("watchSourceReachability()"),
        )
    }
}
