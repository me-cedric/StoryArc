package app.storyarc.feature.library

import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.model.ReadingPosition
import app.storyarc.core.model.ReadingProgress
import app.storyarc.core.persistence.ProgressStore
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

/**
 * A save with no synced position keeps the one already stored.
 *
 * The field report: a device synced with the server, read one more page, and the next pull
 * raised a "both changed" conflict where there was none. Every reader save sends
 * `syncedPosition = null` -- only a successful exchange with the server knows one -- so a
 * save that overwrote it unconditionally erased the fact of the sync on the very next page
 * turn. iOS mirrors this in `ProgressStoreTests.syncedPositionSurvivesAPlainSave`.
 *
 * In `feature:library` rather than `core:persistence`, which has no Robolectric of its own.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class SyncedPositionSurvivesTest {

    private fun store() = ProgressStore.inMemory(RuntimeEnvironment.getApplication())

    @Test
    fun `a plain save keeps the synced position already stored`() = runTest {
        val store = store()
        val identity = PublicationIdentity(normalizedPath = "/books/one.cbz")
        store.save(
            ReadingProgress(
                identity = identity,
                position = ReadingPosition.Page(4, 20),
                updatedAtEpochMillis = 0,
                syncedPosition = ReadingPosition.Page(4, 20),
            ),
        )

        // The ordinary reader save: a new position, and nothing said about sync.
        store.save(
            ReadingProgress(identity = identity, position = ReadingPosition.Page(5, 20), updatedAtEpochMillis = 0),
        )

        val found = store.progress(identity)
        assertEquals(ReadingPosition.Page(5, 20), found?.position)
        // A synced position is kept only as a fraction here (`ProgressStore.syncedProgression`
        // is a `Double?`), so it reads back as `Reflowable` regardless of what was stored --
        // the store's own merge rules already compare synced positions by fraction rather
        // than by exact case, for the same reason.
        assertEquals(ReadingPosition.Page(4, 20).fraction, found?.syncedPosition?.fraction)
    }
}
