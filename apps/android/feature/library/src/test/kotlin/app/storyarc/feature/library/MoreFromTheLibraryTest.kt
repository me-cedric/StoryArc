package app.storyarc.feature.library

import app.storyarc.core.model.Source
import app.storyarc.core.model.SourceKind
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Which sources earn a way to the rest of what they hold.
 *
 * `library-browsing`: what a source holds beyond what the app has read is "reachable from
 * search and from an explicit *more from this library* affordance at the foot of the
 * shelf". Search is asserted in `SearchListingTest`; this is the affordance.
 *
 * **An affordance that is always there says nothing.** A shelf where every source gave
 * everything draws no footer, because a reader who meets the same line under every library
 * learns to skim past it — including on the day it means something.
 */
class MoreFromTheLibraryTest {

    private fun source(kind: SourceKind, id: UUID = UUID.randomUUID()) = Source(
        id = id,
        kind = kind,
        displayName = kind.name,
        locator = "https://x.invalid",
    )

    private fun more(sources: List<Source>, partial: Set<UUID>) =
        sourcesWithMore(sources) { it in partial }

    @Test
    fun `a server that held something back gets a way in`() {
        val server = source(SourceKind.KAVITA_SERVER)

        assertEquals(listOf(server), more(listOf(server), partial = setOf(server.id)))
    }

    @Test
    fun `a source that gave everything does not`() {
        val server = source(SourceKind.KAVITA_SERVER)

        assertTrue(more(listOf(server), partial = emptySet()).isEmpty())
    }

    @Test
    fun `a local folder never does, however much of it was read`() {
        // A folder is walked by this app, and a way into one leads back to the grid the
        // reader is already looking at. `SourceKind.hasItsOwnBrowser` is the same rule.
        val folder = source(SourceKind.LOCAL_FOLDER)

        assertTrue(more(listOf(folder), partial = setOf(folder.id)).isEmpty())
    }

    @Test
    fun `each kind with a browser of its own is offered`() {
        val kinds = listOf(SourceKind.KAVITA_SERVER, SourceKind.OPDS_CATALOG, SourceKind.NETWORK_SHARE)
        val sources = kinds.map { source(it) }

        assertEquals(sources, more(sources, partial = sources.map { it.id }.toSet()))
    }

    @Test
    fun `only the sources that held something back, in the order the registry has them`() {
        val first = source(SourceKind.KAVITA_SERVER)
        val second = source(SourceKind.OPDS_CATALOG)
        val third = source(SourceKind.NETWORK_SHARE)

        assertEquals(
            listOf(first, third),
            more(listOf(first, second, third), partial = setOf(first.id, third.id)),
        )
    }
}
