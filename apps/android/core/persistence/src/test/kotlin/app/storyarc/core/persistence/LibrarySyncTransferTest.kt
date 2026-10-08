package app.storyarc.core.persistence

import app.storyarc.core.model.AppearanceMode
import app.storyarc.core.model.FontSizeStep
import app.storyarc.core.model.LibrarySyncOutcome
import app.storyarc.core.model.PublicationCollection
import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.model.ReadingPosition
import app.storyarc.core.model.ReadingProgress
import app.storyarc.core.model.Shelves
import app.storyarc.core.model.SyncFile
import app.storyarc.core.model.SyncPlace
import app.storyarc.core.model.ThemeScope
import java.util.UUID
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

/**
 * `library-sync` tasks 3.1, 3.4 and 3.5 through the real stores: what a screen saves is stamped,
 * a sync carries it, and the other device's stores hold it after its own sync. iOS's
 * `LibrarySyncTransferTests` makes the same claims.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class LibrarySyncTransferTest {

    private class Place : SyncPlace {
        val files = mutableMapOf<String, SyncFile>()
        private var version = 0

        override suspend fun names() = files.keys.toList()

        override suspend fun read(name: String) = files[name]

        override suspend fun write(name: String, text: String, replacing: String?): Boolean {
            if (files[name]?.version != replacing) return false
            files[name] = SyncFile(text, "v${++version}")
            return true
        }

        override suspend fun delete(name: String) = files.remove(name) != null
    }

    /** One device with real stores, a clock the test moves, and its own sync state. */
    private class Device {
        var now = 1_767_225_600_000L
        val shelves = ShelvesStore(FakePreferences()) { now }
        val settings = SettingsStore(FakePreferences()) { now }
        val progress = ProgressStore.inMemory(RuntimeEnvironment.getApplication())
        val state = LibrarySyncState(FakePreferences())
        val transfer = LibraryTransfer(
            LibraryArchive(
                sources = SourceStore(FakePreferences()),
                certificatePins = CertificatePinStore(FakePreferences()),
                shelves = shelves,
                library = LibraryPreferences(FakePreferences()),
                settings = settings,
                reader = ReaderPreferences(FakePreferences()) { now },
                progress = progress,
            ),
            secrets = null,
        )

        suspend fun sync(place: Place): LibrarySyncOutcome {
            now += 1_000
            return transfer.sync(place, state, "1.0", now)
        }
    }

    private val shelf = UUID.fromString("cccccccc-0000-0000-0000-000000000003")

    @Test
    fun `a shelf deleted on one device is gone from the other device's store`() = runTest {
        val place = Place()
        val a = Device()
        val b = Device()
        a.shelves.save(Shelves().adding(PublicationCollection(id = shelf, name = "Image")))
        a.sync(place)
        b.sync(place)
        assertEquals(listOf(shelf), b.shelves.shelves().collections.map { it.id })

        a.now += 5_000
        a.shelves.save(a.shelves.shelves().deletingCollection(shelf))
        a.sync(place)
        b.sync(place)
        b.sync(place)

        assertTrue(b.shelves.shelves().collections.isEmpty())
        assertEquals(listOf(shelf), b.shelves.removed().map { it.id })
    }

    @Test
    fun `a setting changed on each device survives on both`() = runTest {
        val place = Place()
        val a = Device()
        val b = Device()
        a.settings.save(a.settings.settings().copy(appearance = AppearanceMode.DARK))
        b.now += 2_000
        b.settings.save(b.settings.settings().copy(language = "fr"))

        a.sync(place)
        b.sync(place)
        a.sync(place)

        for (device in listOf(a, b)) {
            assertEquals(AppearanceMode.DARK, device.settings.settings().appearance)
            assertEquals("fr", device.settings.settings().language)
        }
    }

    @Test
    fun `a position reaches the other device with its watermark`() = runTest {
        val place = Place()
        val a = Device()
        val b = Device()
        val book = PublicationIdentity(contentDigest = "d1")
        a.progress.save(ReadingProgress(book, ReadingPosition.Page(40, 100), updatedAtEpochMillis = a.now))

        a.sync(place)
        b.sync(place)

        val arrived = b.progress.recent(10).single()
        assertEquals(ReadingPosition.Page(40, 100), arrived.position)
        assertEquals(arrived.position.fraction, arrived.syncedPosition?.fraction)
    }

    @Test
    fun `an install keeps one device id`() {
        val state = LibrarySyncState(FakePreferences())
        val first = state.deviceId()
        assertEquals(first, state.deviceId())
        assertTrue(first != LibrarySyncState(FakePreferences()).deviceId())
    }

    @Test
    fun `a store stamps a change and records a deletion`() {
        var now = 5_000L
        val store = ShelvesStore(FakePreferences()) { now }
        store.save(Shelves().adding(PublicationCollection(id = shelf, name = "Image")))
        assertEquals(5_000L, store.shelves().collections.single().changedAtEpochMillis)

        now = 9_000L
        store.save(store.shelves().deletingCollection(shelf))
        assertEquals(9_000L, store.removed().single().removedAtEpochMillis)
    }

    @Test
    fun `a settings store stamps the field the reader changed`() {
        val store = SettingsStore(FakePreferences()) { 7_000L }
        store.save(store.settings().copy(language = "de"))
        assertEquals(mapOf("language" to 7_000L), store.changedAt())
    }

    @Test
    fun `a theme store stamps the field the reader changed`() {
        val reader = ReaderPreferences(FakePreferences()) { 8_000L }
        val themes = reader.themes()
        val larger = themes.default(ThemeScope.REFLOWABLE).let { it.copy(values = it.values.copy(fontSize = FontSizeStep.LARGE)) }
        reader.save(themes.settingDefault(larger, ThemeScope.REFLOWABLE))
        assertEquals(mapOf("reflowable/|values.fontSizePercent" to 8_000L), reader.themesChangedAt())
    }
}
