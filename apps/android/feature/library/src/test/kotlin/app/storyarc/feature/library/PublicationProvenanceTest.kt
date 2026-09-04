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
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
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
        assertTrue(provenance.isAlsoElsewhere)
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
        // `isAlsoElsewhere` is the union of them rather than either one.
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
        assertTrue(provenance.isAlsoElsewhere)
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
    fun theSameBookFromTwoSourcesSaysSo() {
        // Identity is stable across sources, so the same volume from a folder and from a
        // server shares an id. Without this the reader cannot tell which copy they are
        // about to read — the exact failure taking origin off the shelf would cause.
        val source = server("Home NAS")
        val here = publication("Bone", source.id)
        val elsewhere = publication("Bone", UUID.randomUUID())

        val provenance = provenanceOf(
            here,
            SourceRegistry(sources = listOf(source)),
            isOnDevice = false,
            library = listOf(here, elsewhere),
        )

        assertTrue(provenance.isAlsoElsewhere)
        assertEquals("Home NAS", provenance.libraryName)
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

        assertFalse(provenance.isAlsoElsewhere)
    }
}
