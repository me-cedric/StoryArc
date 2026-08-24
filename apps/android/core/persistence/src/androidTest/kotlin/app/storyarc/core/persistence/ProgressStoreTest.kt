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
        store.save(ReadingProgress(id, ReadingPosition.Page(4, 20), false, 1_000))

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
        store.save(ReadingProgress(id, ReadingPosition.Page(1, 20), false, 1_000))
        store.save(ReadingProgress(id, ReadingPosition.Page(9, 20), false, 2_000))

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
                identity(path = "/books/one.cbz"), ReadingPosition.Page(3, 10), false, 1_000,
            ),
        )
        store.save(
            ReadingProgress(
                identity(digest = "abc123", path = "/books/one.cbz"),
                ReadingPosition.Page(5, 10), false, 2_000,
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
                ReadingPosition.Page(7, 30), false, 1_000,
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
        store.save(ReadingProgress(identity(path = "/a.cbz"), ReadingPosition.Page(1, 5), false, 1))
        store.save(ReadingProgress(identity(path = "/b.cbz"), ReadingPosition.Page(2, 5), false, 2))
        assertEquals(2, store.recent().size)
    }

    // Finished.

    @Test
    fun finishedIsSticky() = runTest {
        // ADR-0006: unmarking a finished publication is a deliberate act, and losing
        // it to a routine save is not something a user would ever want.
        val store = store()
        val id = identity(path = "/books/done.cbz")
        store.save(ReadingProgress(id, ReadingPosition.Page(19, 20), true, 1_000))
        store.save(ReadingProgress(id, ReadingPosition.Page(2, 20), false, 2_000))

        val found = store.progress(id)
        assertEquals(true, found?.isFinished)
        // The position still moves — re-reading a finished book is normal.
        assertEquals(ReadingPosition.Page(2, 20), found?.position)
    }

    @Test
    fun forgettingAPublicationRemovesIt() = runTest {
        val store = store()
        val id = identity(path = "/books/one.cbz")
        store.save(ReadingProgress(id, ReadingPosition.Page(1, 5), false, 1_000))
        store.forget(id)
        assertNull(store.progress(id))
    }

    // Continue reading.

    @Test
    fun recentIsOrderedByWhenItWasLastRead() = runTest {
        // What library-browsing's "Continue reading" row is built from, so the order
        // is the feature rather than an implementation detail.
        val store = store()
        store.save(ReadingProgress(identity(path = "/old.cbz"), ReadingPosition.Page(1, 5), false, 1_000))
        store.save(ReadingProgress(identity(path = "/new.cbz"), ReadingPosition.Page(1, 5), false, 2_000))
        assertEquals("/new.cbz", store.recent().first().identity.normalizedPath)
    }

    @Test
    fun recentRespectsItsLimit() = runTest {
        val store = store()
        repeat(5) { index ->
            store.save(
                ReadingProgress(
                    identity(path = "/$index.cbz"), ReadingPosition.Page(1, 5), false,
                    index.toLong(),
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
        store.save(ReadingProgress(id, position, false, 1_000))
        assertTrue(store.progress(id)?.position is ReadingPosition.Reflowable)
        assertEquals(position, store.progress(id)?.position)
    }
}
