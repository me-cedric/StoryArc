package app.storyarc.feature.library

import app.storyarc.core.model.Source
import app.storyarc.core.model.SourceKind
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * What a wide window's rail offers.
 *
 * `native-experience` asks a large screen for "a multi-column layout with a persistent
 * sidebar". What goes in it is the part that can be wrong without anyone noticing on a
 * screenshot — an order that shuffles when a source is added, a folder that appears as a
 * destination and leads back to the grid it came from, a collections item that goes
 * missing when the registry is empty.
 *
 * iOS's `LibrarySidebarTests` asserts the same list in the same order.
 */
class SidebarDestinationTest {

    private fun source(name: String, kind: SourceKind) = Source(displayName = name, kind = kind)

    @Test
    fun `An empty registry still offers the library and the collections`() {
        // A reader who has added nothing still has shelves, and still needs somewhere to
        // stand. A rail that was empty until a server was added would look broken on
        // first launch.
        assertEquals(
            listOf(SidebarDestination.Library, SidebarDestination.Shelves),
            sidebarDestinations(emptyList()),
        )
    }

    @Test
    fun `A local folder is not a destination`() {
        // Its publications were scanned into the grid, so an item for it would lead back
        // to the item above it.
        val folder = source("Comics", SourceKind.LOCAL_FOLDER)
        assertEquals(
            listOf(SidebarDestination.Library, SidebarDestination.Shelves),
            sidebarDestinations(listOf(folder)),
        )
    }

    @Test
    fun `Every browsable source gets an item, in registry order`() {
        val catalogue = source("Standard Ebooks", SourceKind.OPDS_CATALOG)
        val server = source("Kavita", SourceKind.KAVITA_SERVER)
        val share = source("NAS", SourceKind.NETWORK_SHARE)
        val folder = source("Comics", SourceKind.LOCAL_FOLDER)

        // The folder sits in the middle of the registry on purpose: filtering it out must
        // not disturb the order of the three that stay.
        assertEquals(
            listOf(
                SidebarDestination.Library,
                SidebarDestination.OneSource(catalogue.id),
                SidebarDestination.OneSource(server.id),
                SidebarDestination.OneSource(share.id),
                SidebarDestination.Shelves,
            ),
            sidebarDestinations(listOf(catalogue, folder, server, share)),
        )
    }

    @Test
    fun `The library is first and the collections last, whatever is between them`() {
        val sources = (1..5).map { source("Server $it", SourceKind.KAVITA_SERVER) }
        val destinations = sidebarDestinations(sources)
        assertEquals(SidebarDestination.Library, destinations.first())
        assertEquals(SidebarDestination.Shelves, destinations.last())
        assertEquals(sources.size + 2, destinations.size)
    }

    @Test
    fun `The rail lists exactly the sources the narrow window's strip does`() {
        // The two are the same set on purpose: the wide window shows the destinations a
        // narrow one keeps in a horizontal strip, and a reader who resizes should find the
        // same places, not a different set with the same name.
        val sources = SourceKind.entries.map { source("A ${it.name}", it) }
        val inStrip = sources.filter { it.kind.isBrowsable }
            .map { SidebarDestination.OneSource(it.id) }
        val inRail = sidebarDestinations(sources).filterIsInstance<SidebarDestination.OneSource>()
        assertEquals(inStrip, inRail)
    }
}

/** Which source kinds are a place to travel to. */
class BrowsableSourceTest {

    @Test
    fun `Only a local folder is not browsable`() {
        assertEquals(false, SourceKind.LOCAL_FOLDER.isBrowsable)
        assertEquals(true, SourceKind.OPDS_CATALOG.isBrowsable)
        assertEquals(true, SourceKind.KAVITA_SERVER.isBrowsable)
        assertEquals(true, SourceKind.NETWORK_SHARE.isBrowsable)
    }

    @Test
    fun `Every kind answers, so a fifth one cannot slip through unanswered`() {
        // `isBrowsable` is a `when` over every case rather than a comparison against one,
        // so adding a kind is a compile error rather than a silent "yes".
        assertEquals(4, SourceKind.entries.size)
        assertEquals(3, SourceKind.entries.count { it.isBrowsable })
    }
}
