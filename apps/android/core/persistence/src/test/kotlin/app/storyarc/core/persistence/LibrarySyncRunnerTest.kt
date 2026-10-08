package app.storyarc.core.persistence

import app.storyarc.core.model.LibraryDocumentCoder
import app.storyarc.core.model.LibrarySync
import app.storyarc.core.model.PublicationCollection
import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.model.ReadingPosition
import app.storyarc.core.model.ReadingProgress
import app.storyarc.core.model.Shelves
import app.storyarc.core.model.SyncFile
import app.storyarc.core.model.SyncPlace
import java.io.IOException
import java.util.UUID
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.yield
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

/**
 * `library-sync` tasks 2.1, 2.4, 4.1 and 4.2: when a sync runs, through the real stores and
 * the real engine. iOS's `LibrarySyncRunnerTests` makes the same claims.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class LibrarySyncRunnerTest {

    /** A place that counts what it is asked, and that can stop answering. */
    private class Place : SyncPlace {
        val files = mutableMapOf<String, SyncFile>()
        var calls = 0
        var writes = 0
        var isAway = false
        var beforeWrite: (suspend () -> Unit)? = null
        private var version = 0

        private fun answer() {
            calls++
            if (isAway) throw IOException("away")
        }

        override suspend fun names(): List<String> = answer().let { files.keys.toList() }

        override suspend fun read(name: String): SyncFile? = answer().let { files[name] }

        override suspend fun write(name: String, text: String, replacing: String?): Boolean {
            answer()
            beforeWrite?.let { hook ->
                beforeWrite = null
                hook()
            }
            if (files[name]?.version != replacing) return false
            writes++
            files[name] = SyncFile(text, "v${++version}")
            return true
        }

        override suspend fun delete(name: String) = answer().let { files.remove(name) != null }

        fun positions() = LibraryDocumentCoder.decode(files.getValue(LibrarySync.FILE_NAME).text)
            .getOrThrow().library.progress
    }

    private class Device {
        var now = 1_767_225_600_000L
        val place = Place()
        val places = SyncPlaceStore(FakePreferences())
        val shelves = ShelvesStore(FakePreferences()) { now }
        val progress = ProgressStore.inMemory(RuntimeEnvironment.getApplication())
        val transfer = LibraryTransfer(
            LibraryArchive(
                sources = SourceStore(FakePreferences()),
                certificatePins = CertificatePinStore(FakePreferences()),
                shelves = shelves,
                library = LibraryPreferences(FakePreferences()),
                settings = SettingsStore(FakePreferences()) { now },
                reader = ReaderPreferences(FakePreferences()) { now },
                progress = progress,
            ),
            secrets = null,
        )
        val state = LibrarySyncState(FakePreferences())
        var placesBuilt = 0
        val runner = LibrarySyncRunner(
            places = places,
            placeFor = {
                placesBuilt++
                place
            },
            sync = { transfer.sync(it, state, "1.0", now) },
            now = { now },
        )
    }

    private val folder = SyncPlaceChoice.Folder("content://tree/Sync")
    private val book = PublicationIdentity(contentDigest = "d1")

    @Test
    fun `sync is off until a place is chosen, and off reads and writes nothing`() = runTest {
        val device = Device()
        assertEquals(SyncStatus.Off, device.runner.status.value)
        for (trigger in LibrarySyncRunner.Trigger.entries) assertFalse(device.runner.run(trigger))
        assertFalse(device.runner.leftPublication(ownedByKavita = false))

        assertEquals(0, device.placesBuilt)
        assertEquals(0, device.place.calls)
        assertEquals(SyncStatus.Off, device.runner.status.value)
    }

    @Test
    fun `the foreground runs one sync and skips a second one inside 30 seconds`() = runTest {
        val device = Device()
        device.runner.choose(folder)

        assertTrue(device.runner.run(LibrarySyncRunner.Trigger.FOREGROUND))
        assertEquals(1, device.place.writes)
        device.now += 10_000
        assertFalse(device.runner.run(LibrarySyncRunner.Trigger.FOREGROUND))
        assertEquals(1, device.place.writes)

        device.now += LibrarySyncRunner.THROTTLE_MILLIS
        assertTrue(device.runner.run(LibrarySyncRunner.Trigger.FOREGROUND))
        assertEquals(2, device.placesBuilt)
    }

    @Test
    fun `a place that does not answer leaves the library working and grey, and a later sync recovers`() =
        runTest {
            val device = Device()
            device.runner.choose(folder)
            device.shelves.save(Shelves().adding(PublicationCollection(id = UUID.randomUUID(), name = "Kept")))
            device.place.isAway = true

            assertTrue(device.runner.run(LibrarySyncRunner.Trigger.FOREGROUND))
            assertEquals(SyncStatus.Unreachable, device.runner.status.value)
            assertEquals(listOf("Kept"), device.shelves.shelves().collections.map { it.name })

            // The failure queued a retry, so the next trigger runs inside the throttle.
            device.place.isAway = false
            device.now += 1_000
            assertTrue(device.runner.run(LibrarySyncRunner.Trigger.FOREGROUND))
            assertEquals(SyncStatus.Synced(device.now), device.runner.status.value)
        }

    @Test
    fun `leaving a publication writes its position at once, and a Kavita publication writes nothing`() =
        runTest {
            val device = Device()
            device.runner.choose(folder)
            device.progress.save(ReadingProgress(book, ReadingPosition.Page(40, 100), updatedAtEpochMillis = device.now))

            assertFalse(device.runner.leftPublication(ownedByKavita = true))
            assertEquals(0, device.place.calls)

            assertTrue(device.runner.leftPublication(ownedByKavita = false))
            assertEquals(1, device.place.writes)
            assertEquals(listOf("d1"), device.place.positions().map { it.identity.contentDigest })
        }

    @Test
    fun `a trigger during a sync runs the sync once more when it ends`() = runTest {
        val device = Device()
        device.runner.choose(folder)
        val inside = CompletableDeferred<Unit>()
        val release = CompletableDeferred<Unit>()
        device.place.beforeWrite = {
            inside.complete(Unit)
            release.await()
        }

        val first = async { device.runner.run(LibrarySyncRunner.Trigger.FOREGROUND) }
        inside.await()
        // The position is saved while the first sync waits on the place.
        device.progress.save(ReadingProgress(book, ReadingPosition.Page(7, 100), updatedAtEpochMillis = device.now))
        assertFalse(device.runner.leftPublication(ownedByKavita = false))
        release.complete(Unit)
        yield()
        assertTrue(first.await())

        assertEquals(2, device.place.writes)
        assertEquals(listOf("d1"), device.place.positions().map { it.identity.contentDigest })
    }
}
