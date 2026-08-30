package app.storyarc.feature.library

import app.storyarc.core.catalogue.OpdsDocument
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * What "Add catalogue" does with what was pasted into it.
 *
 * Rank 7 of the 30 August security review: a Kavita OPDS URL pasted into the *generic*
 * catalogue sheet became an OPDS source. Kavita's OPDS URL carries the reader's
 * full-privilege API key in its path, the fetch therefore succeeded with no 401 and no
 * prompt, and the whole key-bearing URL was written to `SharedPreferences` in the clear --
 * where the secure store was never consulted at all.
 *
 * iOS's `CatalogueTargetTests` asserts the same cases in the same order.
 */
class CatalogueTargetTest {

    @Test
    fun aPastedKavitaOpdsUrlIsAKavitaServerNotAFeed() {
        val target = CatalogueTarget.of("https://kavita.example/api/opds/97b1f0e2c4")

        assertTrue("expected a Kavita server, got $target", target is CatalogueTarget.Kavita)
        val address = (target as CatalogueTarget.Kavita).address
        assertEquals("https://kavita.example", address.base)
        assertEquals("97b1f0e2c4", address.apiKey)
    }

    @Test
    fun theKeyNeverReachesTheFeedPath() {
        // The reason order matters: asked on its own, the catalogue's own address parser
        // completes that URL into a perfectly good feed URL, key and all. Anything that asks
        // it first has already lost the key into the catalogue flow.
        val typed = "https://kavita.example/api/opds/97b1f0e2c4"
        assertNotNull(OpdsDocument.address(typed))
        assertNotEquals(CatalogueTarget.Feed(OpdsDocument.address(typed)!!), CatalogueTarget.of(typed))
    }

    @Test
    fun aReverseProxySubpathIsRecognisedToo() {
        val target = CatalogueTarget.of("https://home.example/books/api/opds/key")

        assertTrue("expected a Kavita server, got $target", target is CatalogueTarget.Kavita)
        assertEquals("https://home.example/books", (target as CatalogueTarget.Kavita).address.base)
    }

    @Test
    fun anOrdinaryCatalogueUrlIsStillAFeed() {
        assertEquals(
            CatalogueTarget.Feed("https://calibre.example/opds"),
            CatalogueTarget.of("https://calibre.example/opds"),
        )
    }

    @Test
    fun somethingThatIsNotAnAddressAtAllIsNeither() {
        assertEquals(CatalogueTarget.Unusable, CatalogueTarget.of("   "))
    }

    @Test
    fun aLocatorNeverCarriesAPasswordTypedIntoTheAddress() {
        // `https://user:password@host/feed` is a working credential written as an address,
        // and `HttpURLConnection` authenticates from it -- so the fetch succeeds and, before
        // this, the password was written to preferences as part of the locator.
        assertEquals(
            "https://books.example/opds",
            CatalogueTarget.storableLocator("https://reader:hunter2@books.example/opds"),
        )
    }

    @Test
    fun anAddressWithNothingSecretInItIsStoredUnchanged() {
        assertEquals(
            "https://books.example/opds?shelf=comics",
            CatalogueTarget.storableLocator("https://books.example/opds?shelf=comics"),
        )
    }

    @Test
    fun anEmbeddedCredentialIsFoundSoItCanBeMovedToTheSecureStore() {
        assertEquals(
            "reader" to "hunter2",
            CatalogueTarget.embeddedCredential("https://reader:hunter2@books.example/opds"),
        )
        assertNull(CatalogueTarget.embeddedCredential("https://books.example/opds"))
    }
}
