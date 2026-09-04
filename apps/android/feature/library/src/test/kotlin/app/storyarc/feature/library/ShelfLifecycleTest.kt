package app.storyarc.feature.library

import android.app.Application
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.model.ReadingPosition
import app.storyarc.core.model.ReadingProgress
import app.storyarc.core.persistence.ProgressStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.io.File

/**
 * What the shelf does between one walk and the next: the empty state, the cached notice, a
 * refresh that adds, and a book that is gone.
 *
 * Four behaviours `library-browsing` and `sources` both name, and until now **nothing on
 * either platform asserted any of them** -- task 6.2. Two of them were broken and neither
 * broke a test: the reconcile treated "found nothing" and "could see nothing" as one answer,
 * and on iOS nothing had ever written a snapshot after a walk at all.
 *
 * Robolectric, for [RecentSearchMemoryTest]'s reason: [LibraryViewModel] takes an
 * `Application`, and its cache and managed folder both come out of one. **No document tree
 * is involved and that is what makes this possible** -- with no picked folder, `rescan`
 * walks the app's own managed folder as a `File`, which is the overload a JVM can reach.
 * Real files from the committed corpus, because a shelf asserted against a fake walk proves
 * nothing about a directory a reader can revoke.
 *
 * iOS's `LibraryShelfLifecycleTests` asserts the same eight, case for case.
 */
@OptIn(ExperimentalCoroutinesApi::class)
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class ShelfLifecycleTest {

    private val application: Application get() = ApplicationProvider.getApplicationContext()

    /** The committed fixture corpus, from this module's own directory rather than a walk. */
    private val corpus: File = File(
        requireNotNull(System.getProperty(MODULE_DIRECTORY)) {
            "$MODULE_DIRECTORY is not set — see this module's build.gradle.kts"
        },
        // apps/android/feature/library -> repository root
    ).resolve("../../../..").canonicalFile.resolve("packages/test-fixtures")

    /** Where a walk with no picked folder looks: the app's own storage. */
    private val managed: File
        get() = application.getExternalFilesDir(null) ?: application.filesDir

    @Before
    fun setUp() {
        // `viewModelScope` posts to the main dispatcher, and unconfined runs the launch
        // eagerly so `scanJob` exists the moment `rescan` returns.
        Dispatchers.setMain(UnconfinedTestDispatcher())
        managed.deleteRecursively()
        managed.mkdirs()
        application.cacheDir.resolve("library.json").delete()
    }

    @After
    fun tearDown() {
        // Put the permissions back before the harness tries to clean up after itself.
        managed.walkTopDown().forEach { it.setReadable(true, false) }
        Dispatchers.resetMain()
    }

    private fun model(progress: ProgressStore? = null) =
        LibraryViewModel(application, progressStore = progress)

    private fun copy(fixture: String, name: String, into: File = managed): File {
        into.mkdirs()
        val file = into.resolve(name)
        corpus.resolve("comics/$fixture").copyTo(file, overwrite = true)
        return file
    }

    // MARK: - The empty state

    @Test
    fun `a walk that finds nothing leaves the library empty and says it finished`() = runTest {
        // The condition `LibraryScreen` branches on for the first thing a reader ever sees. A
        // shelf stuck in Scanning draws a spinner for ever, and a shelf that reports
        // publications it does not have draws nothing at all.
        val model = model()
        model.rescan()
        model.scanJob?.join()

        assertTrue(model.publications.value.isEmpty())
        assertTrue(model.visible.value.isEmpty())
        assertTrue(model.registry.value.sources.isEmpty())
        assertEquals(LibraryScanState.Finished(0, 0), model.scanState.value)
    }

    // MARK: - The cached notice

    @Test
    fun `a shelf restored from the cache says when it was last refreshed`() = runTest {
        copy("single-page.cbz", "01.cbz")
        val first = model()
        first.rescan()
        first.scanJob?.join()
        assertEquals(1, first.publications.value.size)

        val second = model()
        second.restoreCachedLibrary()

        assertEquals(1, second.publications.value.size)
        assertNotNull(
            "The shelf was restored from the cache and the indicator says nothing." +
                " `sources` asks for \"a single unobtrusive indicator\" stating that content" +
                " is cached and when it was last refreshed.",
            second.cachedAt.value,
        )
    }

    @Test
    fun `a walk that read the folder takes the cached notice down`() = runTest {
        copy("single-page.cbz", "01.cbz")
        val first = model()
        first.rescan()
        first.scanJob?.join()

        val second = model()
        second.restoreCachedLibrary()
        assertNotNull(second.cachedAt.value)
        second.rescan()
        second.scanJob?.join()

        assertNull(
            "The shelf is current and the indicator still calls it cached, which is the" +
                " indicator lying quietly in the corner.",
            second.cachedAt.value,
        )
    }

    @Test
    fun `a walk that could not read the folder keeps the cached notice`() = runTest {
        // Task 5.1, and the reader-facing half of it: a folder whose permission lapsed lists
        // nothing, opens nothing and finishes 0, 0 — the same terminal event as a reader who
        // deleted every book. Being told the shelf is current is exactly wrong at the one
        // moment it certainly is not.
        copy("single-page.cbz", "01.cbz")
        val first = model()
        first.rescan()
        first.scanJob?.join()
        assertEquals(1, first.publications.value.size)

        val second = model()
        second.restoreCachedLibrary()
        val restored = second.cachedAt.value
        assertNotNull(restored)
        lock(managed)

        second.rescan()
        second.scanJob?.join()

        assertEquals(
            "A walk that could see nothing took the cached indicator down. It must leave" +
                " only when a walk genuinely found an empty folder — `sources` promises" +
                " cached content \"remains browsable\" when a source cannot be reached.",
            restored,
            second.cachedAt.value,
        )
    }

    @Test
    fun `a walk that lost one subfolder still holds the books that were under it`() = runTest {
        // **The case the emptiness rule could never catch.** A walk that found *nothing* was
        // already treated as evidence of nothing, but a folder that loses one branch still
        // returns rows — so the walk looked complete, and every book under the branch it
        // could not list was removed as though the reader had deleted it.
        val series = managed.resolve("Bone")
        copy("single-page.cbz", "01.cbz")
        copy("natural-sort.cbz", "02.cbz", into = series)

        val model = model()
        model.rescan()
        model.scanJob?.join()
        assertEquals(2, model.publications.value.size)

        lock(series)
        model.rescan()
        model.scanJob?.join()

        assertEquals(
            "The books under the subfolder the walk could not list were forgotten. The walk" +
                " found something, so the emptiness rule did not save them — what it did not" +
                " see is unaccounted for, not gone.",
            2,
            model.publications.value.size,
        )
    }

    @Test
    fun `a walk that could not read the folder at all removes nothing either`() = runTest {
        copy("single-page.cbz", "01.cbz")
        val first = model()
        first.rescan()
        first.scanJob?.join()
        assertEquals(1, first.publications.value.size)

        lock(managed)
        val second = model()
        second.rescan()
        second.scanJob?.join()

        assertEquals(
            "A walk that could not list the folder emptied the shelf. What it did not see is" +
                " unaccounted for, not gone.",
            1,
            second.publications.value.size,
        )
    }

    // MARK: - Incremental refresh

    @Test
    fun `a refresh adds what is new without emptying the shelf first`() = runTest {
        // `sources`: a refresh updates the view "incrementally rather than clearing it and
        // re-populating". Asserted at the moment it could go wrong — the instant the walk is
        // started, before anything has been found again.
        copy("single-page.cbz", "01.cbz")
        val model = model()
        model.rescan()
        model.scanJob?.join()
        val known = model.publications.value.single().id

        copy("natural-sort.cbz", "02.cbz")
        model.rescan()
        assertTrue(
            "The shelf was emptied when the refresh started. `sources` asks the view to be" +
                " updated incrementally, and a reader watching sees their library disappear" +
                " and come back.",
            model.publications.value.isNotEmpty(),
        )
        model.scanJob?.join()

        assertEquals(2, model.publications.value.size)
        assertTrue(
            "The publication that was already on the shelf was replaced rather than kept, so" +
                " every cover it had decoded was thrown away with it.",
            model.publications.value.any { it.id == known },
        )
    }

    // MARK: - Disappearance

    @Test
    fun `a publication the walk no longer finds leaves the shelf, and its progress stays`() =
        runTest {
            // `sources`: when a refresh shows a publication "is no longer present in the
            // source", it "is removed from the library view and its reading progress is
            // retained".
            copy("single-page.cbz", "01.cbz")
            val leaving = copy("natural-sort.cbz", "02.cbz")

            val progress = ProgressStore.inMemory(application)
            val model = model(progress)
            model.rescan()
            model.scanJob?.join()
            assertEquals(2, model.publications.value.size)

            val gone = model.publications.value.single { model.location(it) == leaving.path }
            val position = ReadingPosition.Page(index = 3, total = 8)
            progress.save(
                ReadingProgress(
                    identity = gone.identity,
                    position = position,
                    updatedAtEpochMillis = System.currentTimeMillis(),
                ),
            )

            assertTrue(leaving.delete())
            model.rescan()
            model.scanJob?.join()

            assertEquals(1, model.publications.value.size)
            assertFalse(model.publications.value.any { it.id == gone.id })
            assertEquals(
                "The reading position went with the file. `sources` retains it, and ADR-0006" +
                    " makes losing one the thing this app must never do.",
                position,
                progress.progress(gone.identity)?.position,
            )
        }

    /**
     * Makes a directory genuinely unlistable, or reports the case as skipped.
     *
     * A process running as root can read a mode-0 directory and there would be nothing to
     * assert; `assumeTrue` says so out loud rather than passing quietly. `ScanReadabilityTest`
     * guards its own cases the same way.
     */
    private fun lock(directory: File) {
        assumeTrue("could not make $directory unreadable", directory.setReadable(false, false))
        assumeTrue("$directory is still readable", directory.listFiles() == null)
    }

    private companion object {
        /** Set by this module's `build.gradle.kts`, from its own `projectDir`. */
        const val MODULE_DIRECTORY = "storyarc.library.projectDir"
    }
}
