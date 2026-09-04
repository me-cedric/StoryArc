package app.storyarc.feature.library

import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.model.Source
import app.storyarc.core.model.SourceConnectionState
import app.storyarc.core.model.SourceKind
import app.storyarc.core.model.SourceRegistry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.UUID

/**
 * The library's primary axis, asserted on the rule rather than on the control.
 *
 * `library-browsing`: narrowing to what can be read with no network "shows only
 * publications readable with no network, regardless of source state", and widening it
 * again "restores the full library without re-scanning anything".
 */
class LibraryAvailabilityTest {

    private fun publication(title: String, sourceId: UUID?) = Publication(
        identity = PublicationIdentity(normalizedPath = "/comics/$title.cbz"),
        format = PublicationFormat.CBZ,
        displayTitle = title,
        origin = MetadataOrigin.INFERRED,
        sourceId = sourceId,
    )

    private fun source(kind: SourceKind, state: SourceConnectionState) = Source(
        displayName = kind.name,
        kind = kind,
        state = state,
    )

    @Test
    fun `a publication with no source at all is readable with no network`() {
        val registry = SourceRegistry()

        assertTrue(publication("Orphan", sourceId = null).isReadableOffline(registry))
    }

    @Test
    fun `a publication in a folder the app can still read is readable with no network`() {
        val folder = source(SourceKind.LOCAL_FOLDER, SourceConnectionState.Connected)
        val registry = SourceRegistry(sources = listOf(folder))

        assertTrue(publication("Kept", folder.id).isReadableOffline(registry))
    }

    @Test
    fun `a publication in a folder the system no longer grants is not`() {
        val folder = source(
            SourceKind.LOCAL_FOLDER,
            SourceConnectionState.Unreachable(sinceEpochMillis = 0L),
        )
        val registry = SourceRegistry(sources = listOf(folder))

        assertFalse(publication("Revoked", folder.id).isReadableOffline(registry))
    }

    @Test
    fun `a download keeps its server's name and is still on the device`() {
        // A chapter downloaded from a server is attributed to that server so the reader can
        // still see where it came from. Its bytes are here, so an unreachable server must
        // not hide it — that is the publication this axis exists to find.
        val server = source(
            SourceKind.KAVITA_SERVER,
            SourceConnectionState.Unreachable(sinceEpochMillis = 0L),
        )
        val registry = SourceRegistry(sources = listOf(server))

        assertTrue(publication("Downloaded", server.id).isReadableOffline(registry))
    }

    @Test
    fun `every source kind is answered from the shelf alone, none of them asked`() {
        // Task 0.3's deliverable: one publication of each of the four kinds, decided with
        // no network. NETWORK_SHARE and OPDS_CATALOG were the two kinds this suite never
        // named, and `isReadableOffline` branches on kind, so nothing else covered them.
        //
        // The rule under test: on Android every row is already a file, so only the one
        // kind whose bytes the app can lose access to -- a picked folder whose persisted
        // permission the system withdrew -- can answer no. A share, a catalogue and a
        // server all reached the shelf by being downloaded, so a downed one changes
        // nothing. The registry is in memory and no branch here can reach a source.
        SourceKind.entries.forEach { kind ->
            val down = source(kind, SourceConnectionState.Unreachable(sinceEpochMillis = 0L))
            val up = source(kind, SourceConnectionState.Connected)
            val registry = SourceRegistry(sources = listOf(down, up))

            assertTrue(
                "$kind: a reachable library's rows are on the device",
                publication("Up", up.id).isReadableOffline(registry),
            )
            assertEquals(
                "$kind: only a withdrawn folder permission can take a row off the device",
                kind != SourceKind.LOCAL_FOLDER,
                publication("Down", down.id).isReadableOffline(registry),
            )
        }
    }

    @Test
    fun `widening restores the whole shelf in the order it was in`() {
        val folder = source(
            SourceKind.LOCAL_FOLDER,
            SourceConnectionState.Unreachable(sinceEpochMillis = 0L),
        )
        val registry = SourceRegistry(sources = listOf(folder))
        val shelf = listOf(
            publication("Away", folder.id),
            publication("Here", sourceId = null),
        )

        assertEquals(
            listOf("Here"),
            shelf.narrowedTo(LibraryAvailability.ON_THIS_DEVICE, registry).map { it.displayTitle },
        )
        assertEquals(
            listOf("Away", "Here"),
            shelf.narrowedTo(LibraryAvailability.EVERYTHING, registry).map { it.displayTitle },
        )
    }

    @Test
    fun `the axis survives being written down and read back`() {
        // `library-browsing`: the scope "persists until changed", and a launch is not a
        // change. The name, not the ordinal -- an ordinal is a position in a source file.
        LibraryAvailability.entries.forEach { axis ->
            assertEquals(axis, LibraryAvailability.named(axis.name))
        }
    }

    @Test
    fun `a stored name this version does not have widens rather than narrows`() {
        // The direction matters. Widening shows a reader more of their library than they
        // asked for; the other mistake hides publications behind a narrowing nobody set,
        // which is the empty-looking library *Scoping to one source* is written against.
        assertEquals(LibraryAvailability.EVERYTHING, LibraryAvailability.named(null))
        assertEquals(LibraryAvailability.EVERYTHING, LibraryAvailability.named("ON_THIS_SHELF"))
        assertEquals(LibraryAvailability.EVERYTHING, LibraryAvailability.named(""))
    }
}
