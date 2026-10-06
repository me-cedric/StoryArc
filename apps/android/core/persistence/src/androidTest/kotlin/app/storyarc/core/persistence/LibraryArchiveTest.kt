package app.storyarc.core.persistence

import android.content.Context
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import app.storyarc.core.model.AppSettings
import app.storyarc.core.model.AppearanceMode
import app.storyarc.core.model.LibraryDocumentCoder
import app.storyarc.core.model.LibraryExport
import app.storyarc.core.model.LibrarySnapshot
import app.storyarc.core.model.PinnedShelves
import app.storyarc.core.model.PublicationCollection
import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.model.ReadingList
import app.storyarc.core.model.ReadingPosition
import app.storyarc.core.model.ReadingProgress
import app.storyarc.core.model.ReadingTheme
import app.storyarc.core.model.ShelfMemory
import app.storyarc.core.model.ShelfPin
import app.storyarc.core.model.ShelfSettings
import app.storyarc.core.model.Shelves
import app.storyarc.core.model.Source
import app.storyarc.core.model.SourceKind
import app.storyarc.core.model.SourceRegistry
import app.storyarc.core.model.ThemePreset
import app.storyarc.core.model.ThemeScope
import java.util.UUID
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * The seven stores an export reads, written and read back as one.
 *
 * `LibraryExport` and `LibraryImport` are asserted without a disk in `:core:model`; this is
 * the half that says the right store holds each part. iOS's `LibraryArchiveTests` asserts the
 * same round trip against its own seven.
 *
 * Instrumented because the progress store is Room, which needs a real SQLite. iOS runs the
 * equivalent as a plain unit test because SwiftData has an in-memory store on the host — the
 * asymmetry is in the platforms, not the coverage.
 */
@RunWith(AndroidJUnit4::class)
class LibraryArchiveTest {

    private val context: Context
        get() = InstrumentationRegistry.getInstrumentation().context

    /** A suite of its own per test, so one test's library is not another's. */
    private fun archive(): LibraryArchive {
        val tag = UUID.randomUUID().toString()
        fun preferences(name: String) =
            context.getSharedPreferences("$name.$tag", Context.MODE_PRIVATE).also {
                it.edit().clear().commit()
            }
        return LibraryArchive(
            sources = SourceStore(preferences("sources")),
            certificatePins = CertificatePinStore(preferences("pins")),
            shelves = ShelvesStore(preferences("shelves")),
            library = LibraryPreferences(preferences("library")),
            settings = SettingsStore(preferences("settings")),
            reader = ReaderPreferences(preferences("reader")),
            progress = ProgressStore.inMemory(context),
        )
    }

    private val collectionId: UUID = UUID.fromString("33333333-3333-3333-3333-333333333333")

    private val library = LibrarySnapshot(
        sources = SourceRegistry(
            sources = listOf(
                Source(
                    displayName = "Comics NAS",
                    kind = SourceKind.NETWORK_SHARE,
                    locator = "smb://nas/comics",
                ),
            ),
        ),
        certificatePins = mapOf("nas.local" to setOf("AB:CD")),
        shelves = Shelves(
            collections = listOf(
                PublicationCollection(
                    id = collectionId,
                    name = "Image Comics",
                    members = setOf("path:/a.cbz"),
                    coverMemberId = "path:/a.cbz",
                ),
            ),
            lists = listOf(ReadingList(name = "Crossover", entries = listOf("path:/a.cbz"))),
        ),
        pinnedShelves = PinnedShelves(setOf(ShelfPin.Collection(collectionId))),
        settings = AppSettings(appearance = AppearanceMode.OLED_DARK, language = "de"),
        themes = ShelfMemory().settingDefault(
            ShelfSettings(theme = ReadingTheme(preset = ThemePreset.CALM)),
            ThemeScope.REFLOWABLE,
        ),
        progress = listOf(
            ReadingProgress(
                identity = PublicationIdentity(contentDigest = "d1"),
                position = ReadingPosition.Page(3, 20),
                updatedAtEpochMillis = 1_767_100_000_000L,
            ),
        ),
    )

    @Test
    fun everyStoreAnExportCarriesSurvivesBeingWrittenAndReadBack() = runTest {
        val archive = archive()

        archive.apply(library)
        val read = archive.snapshot()

        assertEquals(listOf("Comics NAS"), read.sources.sources.map { it.displayName })
        assertEquals(mapOf("nas.local" to setOf("AB:CD")), read.certificatePins)
        assertEquals("path:/a.cbz", read.shelves.collections.first().coverMemberId)
        assertEquals(listOf("path:/a.cbz"), read.shelves.lists.first().entries)
        assertEquals(library.pinnedShelves.tokens, read.pinnedShelves.tokens)
        assertEquals(library.settings, read.settings)
        assertEquals(ThemePreset.CALM, read.themes.default(ThemeScope.REFLOWABLE).theme.preset)
        assertEquals(ReadingPosition.Page(3, 20), read.progress.first().position)
    }

    @Test
    fun aLibraryWithNothingInItReadsBackAsOne() = runTest {
        val read = archive().snapshot()

        assertTrue(read.sources.sources.isEmpty())
        assertTrue(read.progress.isEmpty())
        assertTrue(read.pinnedShelves.isEmpty)
    }

    @Test
    fun aDocumentWrittenFromTheArchiveCarriesNoSecretOutOfTheSourceStore() = runTest {
        val archive = archive()
        archive.apply(
            library.copy(
                sources = SourceRegistry(
                    sources = listOf(
                        Source(
                            displayName = "NAS",
                            kind = SourceKind.NETWORK_SHARE,
                            credentialReference = "keystore:nas",
                            locator = "smb://reader:hunter2@nas.local/comics",
                        ),
                    ),
                ),
            ),
        )

        val bytes = LibraryDocumentCoder.encode(
            LibraryExport.document(archive.snapshot(), "10.14.0", 0L),
        )

        assertFalse(bytes.contains("hunter2"))
        assertFalse(bytes.contains("keystore:"))
        assertTrue(bytes.contains("smb://reader@nas.local/comics"))
    }

    @Test
    fun anImportedFinishedPublicationStaysFinishedAfterTheWrite() = runTest {
        val archive = archive()

        archive.apply(
            library.copy(
                progress = listOf(
                    ReadingProgress(
                        identity = PublicationIdentity(contentDigest = "d1"),
                        position = ReadingPosition.Page(19, 20),
                        isFinished = true,
                        finishedAtEpochMillis = 1_767_100_000_000L,
                        updatedAtEpochMillis = 1_767_100_000_000L,
                    ),
                ),
            ),
        )

        // `ProgressStore.save` is deliberately not allowed to set the flag, so an import that
        // only called it would quietly land every finished publication as unfinished.
        assertTrue(archive.snapshot().progress.first().isFinished)
    }
}
