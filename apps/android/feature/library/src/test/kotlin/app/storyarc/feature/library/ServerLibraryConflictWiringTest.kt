package app.storyarc.feature.library

import java.io.File
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Task 2.9's corrected note: `ServerLibrary`'s per-source refresh already called
 * `KavitaSync.pull`, and it already discarded what came back -- so a conflict a background
 * refresh resolved never reached a reader, where the series screen's own pull reaches
 * `SyncConflictNotice` for the same kind of conflict. Read as source, the way
 * `LocalNetworkPermissionWiringTest` reads `SmbConnection` and `SmbSheet` for the same
 * reason: the three files below only agree with each other once a `LibraryScreen` is composed
 * with a live `LibraryViewModel`, which needs a reachable Kavita server to prove anything
 * through -- `KavitaContributorTest` and `KavitaSyncQueueTest` already cover the merge and the
 * row-building pull itself depends on, with no server either.
 */
class ServerLibraryConflictWiringTest {

    private fun read(path: String): String {
        val module = System.getProperty(MODULE_DIRECTORY)?.let(::File)
            ?: error(
                "$MODULE_DIRECTORY is unset. This test reads the module's own source and will" +
                    " not go looking for it elsewhere — run it through Gradle" +
                    " (`pnpm gradle :feature:library:testDebugUnitTest`), which sets the" +
                    " property from the module directory.",
            )
        val file = File(module, path)
        if (!file.isFile) error("$path is not under ${module.absolutePath} — has it moved?")
        return file.readText()
    }

    private val serverLibrary: String by lazy { read(SERVER_LIBRARY_SOURCE) }
    private val viewModel: String by lazy { read(VIEW_MODEL_SOURCE) }
    private val screen: String by lazy { read(SCREEN_SOURCE) }

    @Test
    fun `a Kavita source's own refresh keeps what its pull found, rather than throwing it away`() {
        assertTrue(
            "ServerLibrary.slice no longer collects KavitaSync.pull's conflicts.",
            serverLibrary.contains("conflicts += KavitaSync.pull("),
        )
        assertTrue(
            "ServerLibrary.Reading no longer carries the conflicts a refresh found.",
            serverLibrary.contains("conflicts = conflicts,"),
        )
    }

    @Test
    fun `the view model hands what a refresh found to the holder the screen reads`() {
        val body = viewModel.substringAfter("fun readServers(")
        val read = body.indexOf("ServerLibrary.read(")
        val reported = body.indexOf("RefreshConflicts.report(reading.conflicts)")
        assertTrue("readServers no longer reports to RefreshConflicts.", reported >= 0)
        assertTrue(
            "The report must happen after the read it names, not before the Reading it" +
                " reports even exists.",
            reported > read,
        )
    }

    @Test
    fun `the library screen mounts the notice, or a background refresh's conflict is never shown`() {
        assertTrue(
            "LibraryScreen no longer mounts RefreshConflictNotice.",
            screen.contains("RefreshConflictNotice(viewModel)"),
        )
    }

    private companion object {
        const val MODULE_DIRECTORY = "storyarc.library.projectDir"
        const val SERVER_LIBRARY_SOURCE =
            "src/main/kotlin/app/storyarc/feature/library/ServerLibrary.kt"
        const val VIEW_MODEL_SOURCE =
            "src/main/kotlin/app/storyarc/feature/library/LibraryViewModel.kt"
        const val SCREEN_SOURCE =
            "src/main/kotlin/app/storyarc/feature/library/LibraryScreen.kt"
    }
}
