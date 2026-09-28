package app.storyarc.feature.library

import app.storyarc.core.kavita.KavitaAddress
import app.storyarc.core.model.ReadingList
import app.storyarc.core.model.ShelfOrigin
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.UUID

/**
 * The offer to copy a local reading list onto a server, in each state it can be in.
 *
 * `collections-and-reading-lists`: "only servers that are reachable and hold reading lists are
 * offered", and when there are none "the offer to copy is disabled and says why, rather than
 * failing after the user has confirmed it".
 *
 * The failure this guards is a quiet one. Hiding the action when no server answered would also
 * stop the copy failing, and it would leave a reader who has a server, and cannot reach it,
 * with no way to tell that from an app that cannot copy lists at all.
 *
 * iOS's `PromoteOfferTests` asserts these cases one for one.
 */
class PromoteOfferTest {

    private fun page(name: String) = KavitaPage(
        id = name,
        title = name,
        address = KavitaAddress(base = "https://$name.example", apiKey = "k"),
    )

    private val local = ReadingList(name = "Crossover", entries = listOf("a", "b"))

    // MARK: - Whether the offer is there at all

    @Test
    fun `a list a server already holds is offered no copy onto a server`() {
        val onAServer = ReadingList(
            name = "Crossover",
            entries = listOf("a"),
            origin = ShelfOrigin.Server(UUID.randomUUID()),
        )

        assertNull(PromoteOffer.of(onAServer, listOf(page("attic"))))
    }

    @Test
    fun `a collection screen, which has no list, is offered nothing`() {
        assertNull(PromoteOffer.of(null, listOf(page("attic"))))
    }

    // MARK: - The state the offer is in

    @Test
    fun `with no reachable server the offer stands, disabled, and carries its reason`() {
        val offer = requireNotNull(PromoteOffer.of(local, emptyList()))

        assertFalse(offer.isEnabled)
        assertTrue(offer.statesWhyNot)
        assertNull(offer.namedServer)
    }

    @Test
    fun `one reachable server enables the offer and names it`() {
        val offer = requireNotNull(PromoteOffer.of(local, listOf(page("attic"))))

        assertTrue(offer.isEnabled)
        assertFalse(offer.statesWhyNot)
        assertEquals("attic", offer.namedServer)
    }

    @Test
    fun `two reachable servers enable the offer and name neither`() {
        val offer = requireNotNull(PromoteOffer.of(local, listOf(page("attic"), page("loft"))))

        assertTrue(offer.isEnabled)
        assertNull(offer.namedServer)
    }

    @Test
    fun `a reason is stated exactly when the offer cannot be acted on`() {
        // The two halves of the scenario's one sentence. A disabled offer with no reason is the
        // failure it exists to prevent, moved one step earlier; a reason beside a live offer
        // would tell a reader the copy cannot happen while they are starting it.
        val away = requireNotNull(PromoteOffer.of(local, emptyList()))
        val there = requireNotNull(PromoteOffer.of(local, listOf(page("attic"))))

        assertEquals(!away.isEnabled, away.statesWhyNot)
        assertEquals(!there.isEnabled, there.statesWhyNot)
        assertNotEquals(there.statesWhyNot, away.statesWhyNot)
    }
}
