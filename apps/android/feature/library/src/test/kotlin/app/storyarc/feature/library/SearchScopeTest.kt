package app.storyarc.feature.library

import app.storyarc.core.catalogue.CertificatePins
import app.storyarc.core.model.MatchGroup
import app.storyarc.core.model.MatchKind
import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.model.Source
import app.storyarc.core.model.SourceConnectionState
import app.storyarc.core.model.SourceKind
import app.storyarc.core.model.SourceRegistry
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.UUID

/**
 * The scope chips narrow the search, rather than only being drawn.
 *
 * `library-browsing`'s *The scope is stated, and can be narrowed*: the screen "states whether
 * it is searching everything or only what is on the device", a reader can "narrow it to what
 * is on the device, and widen it again, without leaving the screen", and the choice "persists
 * until changed".
 *
 * The clause that decides the shape of the whole thing is in the next scenario down:
 * narrowing to the device "removes that notice, **because nothing is then being waited
 * for**". So the scope decides *who is asked*, not only which rows survive. A scope that
 * filtered rows alone would leave the fan-out running and the could-not-answer line up, and
 * the reader who narrowed precisely to stop waiting would still be waiting. iOS reached the
 * same conclusion in `ScopeMenu.sourcesToAsk`.
 */
class SearchScopeTest {

    private fun publication(title: String, sourceId: UUID?) = Publication(
        identity = PublicationIdentity(normalizedPath = "/comics/$title.cbz"),
        format = PublicationFormat.CBZ,
        displayTitle = title,
        origin = MetadataOrigin.INFERRED,
        sourceId = sourceId,
    )

    private fun source(kind: SourceKind, state: SourceConnectionState = SourceConnectionState.Connected) =
        Source(displayName = kind.name, kind = kind, state = state)

    @Test
    fun `everything asks every library that can answer a search`() {
        val kavita = source(SourceKind.KAVITA_SERVER)
        val folder = source(SourceKind.LOCAL_FOLDER)
        val registry = SourceRegistry(sources = listOf(kavita, folder))

        // A folder has no search endpoint at either scope, which is `RemoteSearch.answers`'
        // rule and not this one's: this decides who *is* asked, that decides who *can* be.
        assertEquals(
            listOf(kavita.id),
            LibraryAvailability.EVERYTHING.sourcesToAsk(registry).map { it.id },
        )
    }

    @Test
    fun `on this device asks nobody at all`() {
        val registry = SourceRegistry(
            sources = listOf(source(SourceKind.KAVITA_SERVER), source(SourceKind.OPDS_CATALOG)),
        )

        assertTrue(LibraryAvailability.ON_THIS_DEVICE.sourcesToAsk(registry).isEmpty())
    }

    @Test
    fun `narrowing drops what cannot be read with no network, and empties no heading over it`() {
        val revoked = source(
            SourceKind.LOCAL_FOLDER,
            SourceConnectionState.Unreachable(sinceEpochMillis = 0L),
        )
        val registry = SourceRegistry(sources = listOf(revoked))
        val groups = listOf(
            MatchGroup(
                MatchKind.PUBLICATION,
                listOf(publication("Here", sourceId = null), publication("Away", revoked.id)),
            ),
            MatchGroup(MatchKind.SERIES, listOf(publication("Gone", revoked.id))),
        )

        val narrowed = groups.narrowedTo(LibraryAvailability.ON_THIS_DEVICE, registry)

        // One group survives with one row. The other is dropped whole rather than kept
        // empty: a heading saying the term matched a series is a heading about a series the
        // reader cannot open on a plane.
        assertEquals(listOf(MatchKind.PUBLICATION), narrowed.map { it.kind })
        assertEquals(listOf("Here"), narrowed.single().publications.map { it.displayTitle })
    }

    @Test
    fun `widening gives every row back, in the order it was in`() {
        val revoked = source(
            SourceKind.LOCAL_FOLDER,
            SourceConnectionState.Unreachable(sinceEpochMillis = 0L),
        )
        val registry = SourceRegistry(sources = listOf(revoked))
        val groups = listOf(
            MatchGroup(
                MatchKind.PUBLICATION,
                listOf(publication("Away", revoked.id), publication("Here", sourceId = null)),
            ),
        )

        assertEquals(
            listOf("Away", "Here"),
            groups.narrowedTo(LibraryAvailability.EVERYTHING, registry)
                .single().publications.map { it.displayTitle },
        )
    }

    @Test
    fun `a search narrowed to the device waits on nothing and names nobody`() = runTest {
        val kavita = source(SourceKind.KAVITA_SERVER)
        val revoked = source(
            SourceKind.LOCAL_FOLDER,
            SourceConnectionState.Unreachable(sinceEpochMillis = 0L),
        )
        val registry = SourceRegistry(sources = listOf(kavita, revoked))
        val search = LibrarySearch(TestScope(testScheduler))
        val groups = listOf(
            MatchGroup(
                MatchKind.PUBLICATION,
                listOf(
                    publication("Here", sourceId = null),
                    publication("Downloaded", kavita.id),
                    publication("Revoked", revoked.id),
                ),
            ),
        )

        search.ask(
            raw = "here",
            groups = groups,
            registry = registry,
            credentials = null,
            pins = CertificatePins(emptyMap()),
            scope = LibraryAvailability.ON_THIS_DEVICE,
        )

        val listing = search.listing.value
        // Nothing is being waited for, so there is nothing that could go quiet. That is the
        // requirement's own reason for the notice disappearing, not a side effect.
        assertTrue(listing.waiting.isEmpty())
        assertTrue(listing.silent.isEmpty())
        // A download keeps its server's name and is still on the device, so it stays; the
        // publication behind a folder grant the system has taken back does not.
        assertEquals(
            listOf("Downloaded", "Here"),
            listing.rows.map { it.result.title }.sorted(),
        )
    }

    @Test
    fun `the same search at every source asks the server`() {
        val kavita = source(SourceKind.KAVITA_SERVER)
        val registry = SourceRegistry(sources = listOf(kavita))
        val search = LibrarySearch(TestScope())

        search.ask(
            raw = "here",
            groups = emptyList(),
            registry = registry,
            credentials = null,
            pins = CertificatePins(emptyMap()),
            scope = LibraryAvailability.EVERYTHING,
        )

        assertEquals(listOf(kavita.id.toString()), search.listing.value.waiting)
    }
}
