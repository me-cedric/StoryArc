package app.storyarc.feature.library

import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.model.Source
import app.storyarc.core.model.SourceConnectionState
import app.storyarc.core.model.SourceKind
import app.storyarc.core.model.SourceRegistry
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * The one line that lets every other browse surface stay quiet about origin.
 *
 * `publication-detail` puts more weight on this sentence than on any other on the page:
 * "if it is wrong the seam leaks". So the decision is a value with a test rather than a
 * chain of conditionals inside a composable, where none of these five cases could be
 * asserted at all.
 */
class PublicationProvenanceTest {

    private fun publication(id: String, source: UUID? = null) = Publication(
        identity = PublicationIdentity(contentDigest = id),
        format = PublicationFormat.CBZ,
        displayTitle = id,
        origin = MetadataOrigin.INFERRED,
        sourceId = source,
    )

    private fun server(
        name: String,
        state: SourceConnectionState = SourceConnectionState.Connected,
    ) = Source(displayName = name, kind = SourceKind.KAVITA_SERVER, state = state)

    @Test
    fun aPublicationFromNoSourceIsOnThisDevice() {
        // A file the system handed over belongs to no source the reader configured.
        val book = publication("Bone")

        val provenance = provenanceOf(book, SourceRegistry(), isOnDevice = true, library = listOf(book))

        assertEquals(Provenance.Place.DEVICE, provenance.place)
        assertNull(provenance.libraryName)
        assertEquals(Provenance.Readiness.READY, provenance.readiness)
    }

    @Test
    fun aFolderOnTheDeviceIsNeverNamedAsALibrary() {
        // A scanned folder's publications are already in the grid. Naming the folder would
        // put origin back on a page whose whole job is to make it invisible everywhere else.
        val folder = Source(displayName = "Comics", kind = SourceKind.LOCAL_FOLDER)
        val book = publication("Bone", folder.id)

        val provenance = provenanceOf(
            book,
            SourceRegistry(sources = listOf(folder)),
            isOnDevice = true,
            library = listOf(book),
        )

        assertEquals(Provenance.Place.DEVICE, provenance.place)
        assertNull(provenance.libraryName)
    }

    @Test
    fun aServerIsNamedByTheNameTheReaderGaveIt() {
        val source = server("Home NAS")
        val book = publication("Bone", source.id)

        val provenance = provenanceOf(
            book,
            SourceRegistry(sources = listOf(source)),
            isOnDevice = false,
            library = listOf(book),
        )

        assertEquals(Provenance.Place.LIBRARY, provenance.place)
        assertEquals("Home NAS", provenance.libraryName)
        assertEquals(Provenance.Readiness.NOT_DOWNLOADED, provenance.readiness)
    }

    @Test
    fun aDownloadedCopyReadsAsReadyWhateverTheNetworkIsDoing() {
        // `offline-downloads` promises a downloaded publication stays readable. A line that
        // said "not answering" over a copy already on the device would contradict it.
        //
        // **The place this asserts changed on 2026-09-05, and the old assertion was the
        // defect.** It required `libraryName == "Home NAS"` — the line naming the copy this
        // page will *not* open, over bytes sitting on the phone and readable on a train. The
        // delta says the line "names the one this page will open"; iOS had always answered
        // `.thisDevice` here (`PublicationProvenance.swift`, "the download store's copy wins
        // the question of *where*, whatever else is true"). The library is not lost: it
        // becomes the second place, which is the assertion below it.
        val source = server("Home NAS", SourceConnectionState.Unreachable(sinceEpochMillis = 0))
        val book = publication("Bone", source.id)

        val provenance = provenanceOf(
            book,
            SourceRegistry(sources = listOf(source)),
            isOnDevice = true,
            library = listOf(book),
        )

        assertEquals(Provenance.Readiness.READY, provenance.readiness)
        assertEquals(Provenance.Place.DEVICE, provenance.place)
        assertNull(provenance.libraryName)
        assertEquals("Home NAS", provenance.alsoIn)
    }

    @Test
    fun aBookHeldHereAndOnAServerSaysItIsHereAndAlsoSomewhereElse() {
        // Task 3.2's own case, and the one no Android test covered: "one publication present
        // locally and on a server". The literal reading of the delta's WHEN — the library
        // holds two rows for it, one from a picked folder and one from a server — and the
        // copy this page opens is the local one.
        //
        // Distinct from the test above, which is one row that is *both*: a download of the
        // server's own copy. Both are "the same publication in two places", which is why
        // `alsoIn` names the other place whichever of the two it is.
        val nas = server("Home NAS")
        val here = publication("Bone")
        val there = publication("Bone", nas.id)

        val provenance = provenanceOf(
            here,
            SourceRegistry(sources = listOf(nas)),
            isOnDevice = true,
            library = listOf(here, there),
        )

        assertEquals(Provenance.Place.DEVICE, provenance.place)
        assertNull(provenance.libraryName)
        assertEquals("Home NAS", provenance.alsoIn)
    }

    @Test
    fun anUnreachableServerSaysSoRatherThanOfferingToOpen() {
        val source = server("Comics", SourceConnectionState.Unreachable(sinceEpochMillis = 0))
        val book = publication("Bone", source.id)

        val provenance = provenanceOf(
            book,
            SourceRegistry(sources = listOf(source)),
            isOnDevice = false,
            library = listOf(book),
        )

        assertEquals(Provenance.Readiness.SOURCE_AWAY, provenance.readiness)
    }

    @Test
    fun aRemovedSourceIsNotNamedAndTheCopyIsStillHere() {
        // The delta's own scenario: "the line says it is on this device, and does not name a
        // library that no longer exists". Asking the registry rather than the publication is
        // what makes that fall out, because a removed source is a source the registry has not
        // got.
        val gone = UUID.randomUUID()
        val book = publication("Bone", gone)

        val provenance = provenanceOf(book, SourceRegistry(), isOnDevice = true, library = listOf(book))

        assertEquals(Provenance.Place.DEVICE, provenance.place)
        assertNull(provenance.libraryName)
        assertEquals(Provenance.Readiness.READY, provenance.readiness)
    }

    @Test
    fun theSameBookFromTwoSourcesNamesTheOtherOne() {
        // Identity is stable across sources, so the same volume from a folder and from a
        // server shares an id. Without this the reader cannot tell which copy they are
        // about to read — the exact failure taking origin off the shelf would cause. The
        // other place is *named* (one-vocabulary 4.6, O19), as iOS names it.
        val source = server("Home NAS")
        val cellar = server("Cellar")
        val here = publication("Bone", source.id)
        val elsewhere = publication("Bone", cellar.id)

        val provenance = provenanceOf(
            here,
            SourceRegistry(sources = listOf(source, cellar)),
            isOnDevice = false,
            library = listOf(here, elsewhere),
        )

        assertEquals("Cellar", provenance.alsoIn)
        assertEquals("Home NAS", provenance.libraryName)
    }

    @Test
    fun aSecondCopyWhoseLibraryIsGoneIsNotClaimed() {
        // A removed library has no name to give, and a line that said *also in* nothing would
        // be the stale-name defect the other way round. iOS's `alsoHolding` stays silent too.
        val source = server("Home NAS")
        val here = publication("Bone", source.id)
        val elsewhere = publication("Bone", UUID.randomUUID())

        val provenance = provenanceOf(
            here,
            SourceRegistry(sources = listOf(source)),
            isOnDevice = false,
            library = listOf(here, elsewhere),
        )

        assertNull(provenance.alsoIn)
    }

    @Test
    fun theLibraryADownloadCameFromWinsOverAnotherCopysLibrary() {
        // The place the reader chose is the second place, not a coincidence of identity.
        val nas = server("Home NAS")
        val cellar = server("Cellar")
        val downloaded = publication("Bone", nas.id)
        val other = publication("Bone", cellar.id)

        val provenance = provenanceOf(
            downloaded,
            SourceRegistry(sources = listOf(nas, cellar)),
            isOnDevice = true,
            library = listOf(downloaded, other),
        )

        assertEquals("Home NAS", provenance.alsoIn)
    }

    @Test
    fun aPublicationWithNoLibraryAndNoCopyBelongsToNowhere() {
        // Not "on this device": the source is gone and the bytes are not here. iOS says the
        // same, in the same four languages.
        val book = publication("Bone", UUID.randomUUID())

        val provenance = provenanceOf(book, SourceRegistry(), isOnDevice = false, library = listOf(book))

        assertEquals(Provenance.Place.UNATTRIBUTED, provenance.place)
        assertNull(provenance.libraryName)
    }

    @Test
    fun oneCopyIsNotAlsoElsewhere() {
        val source = server("Home NAS")
        val book = publication("Bone", source.id)

        val provenance = provenanceOf(
            book,
            SourceRegistry(sources = listOf(source)),
            isOnDevice = false,
            library = listOf(book),
        )

        assertNull(provenance.alsoIn)
    }

    /**
     * **A source still being checked does not say it is not answering.**
     *
     * Only *unreachable* means not answering. Connection state is never persisted, so every
     * source is *connecting* on every launch, and the line read `canFetch` — `Connected`
     * alone — so it claimed a failed probe for all of that time. Seen on an emulator on
     * 2026-09-11: *From Attic Catalogue — not answering right now* about a catalogue the
     * shelf had just read nine titles from, while *Your libraries* read *Available* for that
     * same source on that same device. iOS asks `if case .unreachable` and never had it.
     */
    @Test
    fun aSourceStillConnectingIsNotSaidToBeNotAnswering() {
        val source = server("Attic Catalogue", SourceConnectionState.Connecting)
        val book = publication("Slow Transfer", source.id)

        val provenance = provenanceOf(
            book,
            SourceRegistry(sources = listOf(source)),
            isOnDevice = false,
            library = listOf(book),
        )

        assertEquals(Provenance.Place.LIBRARY, provenance.place)
        assertEquals("Attic Catalogue", provenance.libraryName)
        assertEquals(Provenance.Readiness.NOT_DOWNLOADED, provenance.readiness)
    }

    /** And an unreachable one still says so, which is the half worth keeping. */
    @Test
    fun anUnreachableSourceStillSaysItIsNotAnswering() {
        val source = server("Cellar Catalogue", SourceConnectionState.Unreachable(sinceEpochMillis = 0))
        val book = publication("Slow Transfer", source.id)

        val provenance = provenanceOf(
            book,
            SourceRegistry(sources = listOf(source)),
            isOnDevice = false,
            library = listOf(book),
        )

        assertEquals(Provenance.Readiness.SOURCE_AWAY, provenance.readiness)
    }

}
