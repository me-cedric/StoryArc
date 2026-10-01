package app.storyarc.feature.library

import app.storyarc.core.kavita.KavitaAddress
import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.persistence.KavitaOrigin
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * Whether a Kavita library row the reader has only ever seen on a shelf -- never opened,
 * never kept -- can still become a download.
 *
 * `kavita-server` task 12.5: the publication page drew no control at all for exactly this
 * row. This proves the pure overload of [kavitaKeepRoute] -- a chapter row, a resolvable
 * origin, a reachable address, all three or none of the control -- with fake resolvers, so
 * the claim needs neither a `Context` nor a keystore. iOS's `KavitaKeepRouteTests` makes the
 * same claims.
 */
class KavitaKeepRouteTest {

    private val sourceId = UUID.randomUUID()
    private val address = KavitaAddress(base = "https://kavita.example", apiKey = "key")

    private fun publication(remoteId: String = "chapter:3103") = Publication(
        identity = PublicationIdentity(
            serverIdentifier = PublicationIdentity.ServerIdentifier(sourceId, remoteId)
        ),
        format = PublicationFormat.CBZ,
        displayTitle = "Issue #43",
        origin = MetadataOrigin.AUTHORITATIVE,
    )

    private fun origin() = KavitaOrigin(
        sourceId = sourceId.toString(),
        libraryId = 7,
        seriesId = 312,
        volumeId = 55,
        chapterId = 3103,
    )

    @Test
    fun `a chapter row with a resolvable origin and a reachable address has a route`() {
        val route = kavitaKeepRoute(publication(), resolvedOrigin = { origin() }, reachableAddress = { address })

        assertEquals(origin(), route?.first)
        assertEquals(address, route?.second)
    }

    @Test
    fun `no route without an origin, even with a reachable address`() {
        assertNull(kavitaKeepRoute(publication(), resolvedOrigin = { null }, reachableAddress = { address }))
    }

    @Test
    fun `no route without a reachable address, even with an origin`() {
        assertNull(kavitaKeepRoute(publication(), resolvedOrigin = { origin() }, reachableAddress = { null }))
    }

    @Test
    fun `a row that is not a Kavita chapter at all has no route`() {
        assertNull(
            kavitaKeepRoute(publication(remoteId = "opds:9"), resolvedOrigin = { origin() }, reachableAddress = { address })
        )
    }
}
