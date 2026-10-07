package app.storyarc.core.persistence

import app.storyarc.core.model.AppSettings
import app.storyarc.core.model.AppearanceMode
import app.storyarc.core.model.LibrarySnapshot
import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.model.ReadingPosition
import app.storyarc.core.model.ReadingProgress
import app.storyarc.core.model.Source
import app.storyarc.core.model.SourceKind
import app.storyarc.core.model.SourceRegistry
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

/**
 * `library-portability` / *Import merges*: an import is all or nothing. A write that fails
 * part-way leaves the device as it was. iOS's `LibraryArchiveTests` asserts the same row.
 *
 * Run on the host against a real in-memory Room store, so the sticky finished flag the undo has
 * to defeat is the store's own and not a fake's.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class LibraryArchiveRollbackTest {

    /** A progress store that fails on its [failingSave]th save, counting from one. */
    private class FailingLedger(
        private val inner: ProgressStore,
        private val failingSave: Int,
    ) : ProgressLedger {
        class Refused : Exception()

        private var saves = 0

        override suspend fun recent(limit: Int) = inner.recent(limit)

        override suspend fun save(progress: ReadingProgress) {
            saves += 1
            if (saves == failingSave) throw Refused()
            inner.save(progress)
        }

        override suspend fun mark(identity: PublicationIdentity, isFinished: Boolean, at: Long) =
            inner.mark(identity, isFinished, at)

        override suspend fun forget(identity: PublicationIdentity) = inner.forget(identity)
    }

    private fun archive(progress: ProgressLedger, preferences: Map<String, FakePreferences>) =
        LibraryArchive(
            sources = SourceStore(preferences.getValue("sources")),
            certificatePins = CertificatePinStore(preferences.getValue("pins")),
            shelves = ShelvesStore(preferences.getValue("shelves")),
            library = LibraryPreferences(preferences.getValue("library")),
            settings = SettingsStore(preferences.getValue("settings")),
            reader = ReaderPreferences(preferences.getValue("reader")),
            progress = progress,
        )

    private fun record(
        digest: String,
        page: Int,
        finished: Boolean = false,
        at: Long = 1_767_100_000_000L,
    ) = ReadingProgress(
        identity = PublicationIdentity(contentDigest = digest),
        position = ReadingPosition.Page(page, 20),
        isFinished = finished,
        finishedAtEpochMillis = at.takeIf { finished },
        updatedAtEpochMillis = at,
    )

    @Test
    fun `a write that fails part-way leaves the device exactly as it was`() = runTest {
        val preferences = listOf("sources", "pins", "shelves", "library", "settings", "reader")
            .associateWith { FakePreferences() }
        val store = ProgressStore.inMemory(RuntimeEnvironment.getApplication())
        val device = archive(store, preferences)

        // The device before: one source, one setting, one position that is not finished.
        device.apply(
            LibrarySnapshot(
                sources = SourceRegistry(
                    sources = listOf(
                        Source(
                            displayName = "Old NAS",
                            kind = SourceKind.NETWORK_SHARE,
                            locator = "smb://old/comics",
                        ),
                    ),
                ),
                settings = AppSettings(appearance = AppearanceMode.OLED_DARK, language = "de"),
                progress = listOf(record("d1", page = 3)),
            ),
        )
        val before = device.snapshot()

        // The import: every small store changes, d1 moves on and is finished, d2 and d3 are
        // new, and the third save is refused. Two saves have landed when it throws.
        val incoming = LibrarySnapshot(
            sources = SourceRegistry(
                sources = listOf(
                    Source(
                        displayName = "Comics NAS",
                        kind = SourceKind.NETWORK_SHARE,
                        locator = "smb://nas/comics",
                    ),
                ),
            ),
            settings = AppSettings(appearance = AppearanceMode.LIGHT, language = "fr"),
            progress = listOf(
                record("d1", page = 19, finished = true, at = 1_767_200_000_000L),
                record("d2", page = 4),
                record("d3", page = 5),
            ),
        )
        val failing = archive(FailingLedger(store, failingSave = 3), preferences)

        val refused = runCatching { failing.apply(incoming) }.exceptionOrNull()
        assertTrue(refused is FailingLedger.Refused)

        val after = device.snapshot()
        assertEquals(before, after)
        assertFalse(after.progress.first { it.identity.contentDigest == "d1" }.isFinished)
        assertEquals(1, after.progress.size)
    }
}
