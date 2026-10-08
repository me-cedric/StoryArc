package app.storyarc.core.model

import app.storyarc.core.model.SyncDocumentFixture.ANDROID_DEVICE
import app.storyarc.core.model.SyncDocumentFixture.APP_VERSION
import app.storyarc.core.model.SyncDocumentFixture.IOS_DEVICE
import app.storyarc.core.model.SyncDocumentFixture.at
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * `library-sync` task 5.2: a document one platform's sync path writes merges on the other.
 *
 * This suite pins `sync-written-by-android.json` and merges `sync-written-by-ios.json`. iOS's
 * `LibrarySyncBoundaryTests` does the reverse.
 */
class LibrarySyncBoundaryTest {

    private suspend fun writtenHere(): String {
        val place = MemoryPlace()
        LibrarySync(place, ANDROID_DEVICE, APP_VERSION).sync(SyncDocumentFixture.snapshot, SyncDocumentFixture.written)
        return place.files.getValue(LibrarySync.FILE_NAME).text
    }

    @Test
    fun `this platform's sync path still writes the committed document`() = runTest {
        assertEquals(SyncDocumentFixture.writtenByAndroid(), writtenHere())
    }

    @Test
    fun `a document iOS wrote names the device and the moment of each record`() {
        val library = LibraryDocumentCoder.decode(SyncDocumentFixture.writtenByIos()).getOrThrow().library

        val collection = library.collections.single()
        assertEquals(wireMoment(at(100)) to IOS_DEVICE, collection.changedAt to collection.changedBy)
        val list = library.readingLists.single()
        assertEquals(wireMoment(at(200)) to IOS_DEVICE, list.changedAt to list.changedBy)
        val tombstone = library.removedShelves.single()
        assertEquals(wireMoment(at(300)) to IOS_DEVICE, tombstone.removedAt to tombstone.removedBy)
        assertEquals(DocumentStamp(wireMoment(at(400)), IOS_DEVICE), library.settings.changed["appearance"])
        assertEquals(
            DocumentStamp(wireMoment(at(500)), IOS_DEVICE),
            library.readingThemes.changed[SyncDocumentFixture.fontSizeField],
        )
        // The Kavita position stayed with Kavita.
        assertEquals(listOf(IOS_DEVICE), library.progress.map { it.changedBy })
    }

    @Test
    fun `a document iOS wrote merges here`() = runTest {
        val place = MemoryPlace()
        place.put(LibrarySync.FILE_NAME, SyncDocumentFixture.writtenByIos())
        val device = SyncDevice(ANDROID_DEVICE, SyncDocumentFixture.receiver)

        val outcome = device.sync(place, at(2_000))

        assertTrue(outcome is LibrarySyncOutcome.Synced)
        val library = device.library
        assertEquals(ReadingPosition.Page(12, 40), device.position(SyncDocumentFixture.book)?.position)
        assertEquals(listOf(SyncDocumentFixture.collectionId), library.shelves.collections.map { it.id })
        assertEquals("Image Comics", library.shelves.collections.single().name)
        assertEquals(setOf("path:/a.cbz", "path:/c.cbz"), library.shelves.collections.single().members)
        assertEquals(listOf("path:/b.cbz", "path:/a.cbz"), library.shelves.lists.single().entries)
        assertEquals(listOf(SyncDocumentFixture.removedId), library.removedShelves.map { it.id })
        assertEquals(AppearanceMode.DARK, library.settings.appearance)
        assertEquals(FontSizeStep.LARGE, library.themes.default(ThemeScope.REFLOWABLE).values.fontSize)
        assertEquals(emptyList<ProgressPull.Conflict>(), device.conflicts)

        // What this device writes back still names the device that made each change.
        val written = place.document().library
        assertEquals(IOS_DEVICE, written.collections.single().changedBy)
        assertEquals(IOS_DEVICE, written.removedShelves.single().removedBy)
        assertEquals(IOS_DEVICE, written.settings.changed.getValue("appearance").by)
    }
}
