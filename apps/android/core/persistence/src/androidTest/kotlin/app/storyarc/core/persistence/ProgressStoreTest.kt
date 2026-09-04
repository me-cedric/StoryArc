package app.storyarc.core.persistence

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.model.ReadingPosition
import app.storyarc.core.model.ReadingProgress
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.util.UUID

/**
 * ADR-0006's storage half. The merge rules are tested on the JVM in `:core:model`;
 * these are about the store finding the right record and keeping the right values.
 *
 * Instrumented because Room needs a real SQLite, which is a framework component.
 * iOS runs the equivalent as a plain unit test because SwiftData has an in-memory
 * store on the host — the asymmetry is in the platforms, not the coverage.
 */
@RunWith(AndroidJUnit4::class)
class ProgressStoreTest {

    private fun store() = ProgressStore.inMemory(
        InstrumentationRegistry.getInstrumentation().context,
    )

    private fun identity(
        server: Pair<UUID, String>? = null,
        digest: String? = null,
        path: String? = null,
    ) = PublicationIdentity(
        serverIdentifier = server?.let {
            PublicationIdentity.ServerIdentifier(it.first, it.second)
        },
        contentDigest = digest,
        normalizedPath = path,
    )

    @Test
    fun aSavedPositionComesBack() = runTest {
        val store = store()
        val id = identity(path = "/books/one.cbz")
        store.save(
            ReadingProgress(id, ReadingPosition.Page(4, 20), false, updatedAtEpochMillis = 1_000),
        )

        val found = store.progress(id)
        assertEquals(ReadingPosition.Page(4, 20), found?.position)
        assertEquals(false, found?.isFinished)
    }

    @Test
    fun nothingRecordedReturnsNothing() = runTest {
        // A publication never opened and one opened at page 1 are different states,
        // and a library that shows a progress bar on every unread book is useless.
        assertNull(store().progress(identity(path = "/nowhere.cbz")))
    }

    @Test
    fun savingAgainReplacesRatherThanAdding() = runTest {
        val store = store()
        val id = identity(path = "/books/one.cbz")
        store.save(
            ReadingProgress(id, ReadingPosition.Page(1, 20), false, updatedAtEpochMillis = 1_000),
        )
        store.save(
            ReadingProgress(id, ReadingPosition.Page(9, 20), false, updatedAtEpochMillis = 2_000),
        )

        assertEquals(ReadingPosition.Page(9, 20), store.progress(id)?.position)
        assertEquals(1, store.recent().size)
    }

    // Identity, which is the point of ADR-0006.

    @Test
    fun aRecordWrittenAgainstAPathIsFoundAgainByItsDigest() = runTest {
        // The scenario ADR-0006 exists for: a file read from a folder, then the
        // same file recognised by content after a rename or a move.
        val store = store()
        store.save(
            ReadingProgress(
                identity(path = "/books/one.cbz"), ReadingPosition.Page(3, 10), false,
                updatedAtEpochMillis = 1_000,
            ),
        )
        store.save(
            ReadingProgress(
                identity(digest = "abc123", path = "/books/one.cbz"),
                ReadingPosition.Page(5, 10), false, updatedAtEpochMillis = 2_000,
            ),
        )

        assertEquals(
            ReadingPosition.Page(5, 10),
            store.progress(identity(digest = "abc123"))?.position,
        )
        assertEquals("the two must be one record, not two", 1, store.recent().size)
    }

    @Test
    fun aServerIdentifierWinsOverTheOtherComponents() = runTest {
        val store = store()
        val source = UUID.randomUUID()
        store.save(
            ReadingProgress(
                identity(server = source to "chapter-9", digest = "abc123"),
                ReadingPosition.Page(7, 30), false, updatedAtEpochMillis = 1_000,
            ),
        )

        // The server is authoritative for its own content, so its key is looked at
        // first and finds the record with no digest to hand.
        assertEquals(
            ReadingPosition.Page(7, 30),
            store.progress(identity(server = source to "chapter-9"))?.position,
        )
    }

    @Test
    fun twoDifferentPublicationsStayTwoRecords() = runTest {
        val store = store()
        store.save(
            ReadingProgress(
                identity(path = "/a.cbz"), ReadingPosition.Page(1, 5), false,
                updatedAtEpochMillis = 1,
            ),
        )
        store.save(
            ReadingProgress(
                identity(path = "/b.cbz"), ReadingPosition.Page(2, 5), false,
                updatedAtEpochMillis = 2,
            ),
        )
        assertEquals(2, store.recent().size)
    }

    // Finished.

    @Test
    fun finishedIsSticky() = runTest {
        // ADR-0006: unmarking a finished publication is a deliberate act, and losing
        // it to a routine save is not something a user would ever want.
        val store = store()
        val id = identity(path = "/books/done.cbz")
        store.save(
            ReadingProgress(id, ReadingPosition.Page(19, 20), true, updatedAtEpochMillis = 1_000),
        )
        store.save(
            ReadingProgress(id, ReadingPosition.Page(2, 20), false, updatedAtEpochMillis = 2_000),
        )

        val found = store.progress(id)
        assertEquals(true, found?.isFinished)
        // The position still moves — re-reading a finished book is normal.
        assertEquals(ReadingPosition.Page(2, 20), found?.position)
    }

    @Test
    fun forgettingAPublicationRemovesIt() = runTest {
        val store = store()
        val id = identity(path = "/books/one.cbz")
        store.save(
            ReadingProgress(id, ReadingPosition.Page(1, 5), false, updatedAtEpochMillis = 1_000),
        )
        store.forget(id)
        assertNull(store.progress(id))
    }

    // Continue reading.

    @Test
    fun recentIsOrderedByWhenItWasLastRead() = runTest {
        // What library-browsing's "Continue reading" row is built from, so the order
        // is the feature rather than an implementation detail.
        val store = store()
        store.save(
            ReadingProgress(
                identity(path = "/old.cbz"), ReadingPosition.Page(1, 5), false,
                updatedAtEpochMillis = 1_000,
            ),
        )
        store.save(
            ReadingProgress(
                identity(path = "/new.cbz"), ReadingPosition.Page(1, 5), false,
                updatedAtEpochMillis = 2_000,
            ),
        )
        assertEquals("/new.cbz", store.recent().first().identity.normalizedPath)
    }

    @Test
    fun recentRespectsItsLimit() = runTest {
        val store = store()
        repeat(5) { index ->
            store.save(
                ReadingProgress(
                    identity(path = "/$index.cbz"), ReadingPosition.Page(1, 5), false,
                    updatedAtEpochMillis = index.toLong(),
                ),
            )
        }
        assertEquals(3, store.recent(limit = 3).size)
    }

    @Test
    fun aReflowablePositionSurvivesTheRoundTrip() = runTest {
        // ADR-0006 stores a locator rather than a page number, because a reflowable
        // page number is a function of the reader's typography.
        val store = store()
        val id = identity(path = "/book.epub")
        val position = ReadingPosition.Reflowable(0.42, "ch3#p7")
        store.save(ReadingProgress(id, position, false, updatedAtEpochMillis = 1_000))
        assertTrue(store.progress(id)?.position is ReadingPosition.Reflowable)
        assertEquals(position, store.progress(id)?.position)
    }

    // Positions recorded before a digest existed.

    @Test
    fun linkMigratesAPathOnlyRecord() = runTest {
        // The migration, end to end. Every position in the shipped app was written
        // against a path and nothing else, because nothing ever produced a digest.
        val store = store()
        store.save(
            ReadingProgress(
                identity(path = "/books/Bone 01.cbz"), ReadingPosition.Page(9, 30), false,
                updatedAtEpochMillis = 1_000,
            ),
        )

        // The next scan finds the same file and now knows what it is.
        store.link(identity(digest = "d1", path = "/books/Bone 01.cbz"))
        // Then the reader renames it.
        val renamed = identity(digest = "d1", path = "/books/Bone Volume One.cbz")

        assertEquals(ReadingPosition.Page(9, 30), store.progress(renamed)?.position)
    }

    @Test
    fun withoutLinkARenameIsStillLost() = runTest {
        // Why `link` exists rather than leaving it to `save`. This is the state of the
        // app before this change, pinned so the migration cannot be quietly dropped.
        val store = store()
        store.save(
            ReadingProgress(
                identity(path = "/books/Bone 01.cbz"), ReadingPosition.Page(9, 30), false,
                updatedAtEpochMillis = 1_000,
            ),
        )

        assertNull(store.progress(identity(digest = "d1", path = "/books/Bone Volume One.cbz")))
    }

    @Test
    fun linkLeavesTheReadingAlone() = runTest {
        // A backfill that touched `updatedAt` would reorder "Continue reading" for the
        // whole library on the first launch after the digest arrived.
        val store = store()
        store.save(
            ReadingProgress(
                identity(path = "/books/one.cbz"), ReadingPosition.Page(4, 20), true,
                updatedAtEpochMillis = 1_000,
            ),
        )

        store.link(identity(digest = "d1", path = "/books/one.cbz"))

        val read = store.progress(identity(digest = "d1"))
        assertEquals(1_000L, read?.updatedAtEpochMillis)
        assertEquals(ReadingPosition.Page(4, 20), read?.position)
        assertEquals(true, read?.isFinished)
    }

    @Test
    fun linkOnlyTouchesWhatExists() = runTest {
        // A whole library can be passed through this on every scan. Most of it has no
        // reading position at all, and none of it should gain one.
        val store = store()

        assertEquals(false, store.link(identity(digest = "d1", path = "/books/unread.cbz")))
        assertNull(store.progress(identity(digest = "d1")))
    }

    @Test
    fun linkIsIdempotent() = runTest {
        val store = store()
        store.save(
            ReadingProgress(
                identity(path = "/books/one.cbz"), ReadingPosition.Page(1, 5), false,
                updatedAtEpochMillis = 1_000,
            ),
        )

        val learned = identity(digest = "d1", path = "/books/one.cbz")
        assertEquals(true, store.link(learned))
        assertEquals(false, store.link(learned))
    }

    // MARK: an audiobook's place

    /**
     * `reading-progress`: a listening position "survives the app being closed, the device
     * restarting, and the file being re-downloaded, exactly as a page index does".
     *
     * The whole of the first two is that it comes back out of the store as what went in.
     * A position that round-tripped as a bare fraction would lose the offset, and the
     * listener would restart the chapter every time they closed the app.
     */
    @Test
    fun aListeningPositionComesBackWholeRatherThanAsAFraction() = runTest {
        val store = store()
        val id = identity(path = "/books/sea-room.m4b")
        val position = ReadingPosition.Listening(2, 5, 42_000, 300_000)
        store.save(ReadingProgress(id, position, false, updatedAtEpochMillis = 1_000))

        assertEquals(position, store.progress(id)?.position)
    }

    /**
     * The read-aloud shape: no duration, and none invented on the way back.
     *
     * `ofMillis` is nullable precisely so an estimate is never stated as a total, and a
     * store that wrote null and read back zero would undo that at the one point where
     * nobody would look.
     */
    @Test
    fun aListeningPositionWithNoDurationKeepsItsAbsence() = runTest {
        val store = store()
        val id = identity(path = "/books/sea-room.epub")
        val position = ReadingPosition.Listening(1, 9, 8_000, null)
        store.save(ReadingProgress(id, position, false, updatedAtEpochMillis = 1_000))

        assertEquals(position, store.progress(id)?.position)
    }

    /**
     * `reading-progress`: "there is one position, and it is wherever the reader last was by
     * either means … the app does not keep a separate listening position".
     *
     * One row, one set of columns, and the second write replaces the first.
     */
    @Test
    fun listeningToAPublicationThatWasReadReplacesItsPosition() = runTest {
        val store = store()
        val id = identity(path = "/books/sea-room.epub")
        store.save(
            ReadingProgress(
                id, ReadingPosition.Reflowable(0.2, "locator"), false,
                updatedAtEpochMillis = 1_000,
            ),
        )

        val listening = ReadingPosition.Listening(3, 9, 1_000, 120_000)
        store.save(ReadingProgress(id, listening, false, updatedAtEpochMillis = 2_000))

        assertEquals(listening, store.progress(id)?.position)
        assertEquals(1, store.recent(10).size)
    }

    /**
     * `reading-progress`: it "survives … the file being re-downloaded, exactly as a page
     * index does".
     *
     * A re-download lands the same content at a path the library has never seen, so what has
     * to hold is that the record is keyed by content identity and not by the kind of position
     * in it. That is `aRecordWrittenAgainstAPathIsFoundAgainByItsDigest` above, asked of the case
     * that arrived last — the one the columns were added for. iOS pins the same in
     * `ProgressStoreTests`.
     */
    @Test
    fun aListeningPositionIsFoundAgainByItsDigest() = runTest {
        val store = store()
        val position = ReadingPosition.Listening(3, 9, 61_000, 900_000)
        store.save(
            ReadingProgress(
                identity(path = "/downloads/sea-room.m4b"), position, false,
                updatedAtEpochMillis = 1_000,
            ),
        )
        store.save(
            ReadingProgress(
                identity(digest = "sea-room-digest", path = "/downloads/sea-room.m4b"),
                position, false, updatedAtEpochMillis = 2_000,
            ),
        )

        val again = identity(digest = "sea-room-digest", path = "/downloads/sea-room (1).m4b")
        assertEquals(position, store.progress(again)?.position)
        assertEquals("one publication, one record", 1, store.recent(10).size)
    }

    /**
     * A page position is still a page position.
     *
     * The new columns are what tells the three cases apart, and a row written without them
     * carries their default. Getting that wrong turns every comic in the library into an
     * audiobook at chapter zero.
     */
    @Test
    fun aPagePositionIsStillAPagePosition() = runTest {
        val store = store()
        val id = identity(path = "/books/one.cbz")
        store.save(
            ReadingProgress(id, ReadingPosition.Page(4, 20), false, updatedAtEpochMillis = 1_000),
        )

        assertEquals(ReadingPosition.Page(4, 20), store.progress(id)?.position)
    }
}
