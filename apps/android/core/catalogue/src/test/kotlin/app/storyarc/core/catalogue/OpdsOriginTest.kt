package app.storyarc.core.catalogue

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Where a credential is allowed to travel.
 *
 * A catalogue names every address the app then fetches -- covers, next pages, acquisition
 * links. A feed that names an attacker's host and is handed the reader's Basic password has
 * collected it, and the cover path fires unattended as the grid scrolls. So the configured
 * source's origin travels beside the credential and decides.
 *
 * iOS's `OpdsOriginTests` asserts the same cases in the same order.
 */
class OpdsOriginTest {

    @Test
    fun anOriginIsSchemeHostAndPort() {
        val books = requireNotNull(OpdsOrigin.of("https://books.example/opds/"))
        assertEquals("https", books.scheme)
        assertEquals("books.example", books.host)
        // The scheme's own default, so `https://a` and `https://a:443` are one origin.
        assertEquals(443, books.port)
    }

    @Test
    fun anOriginAdmitsOnlyItself() {
        val books = requireNotNull(OpdsOrigin.of("https://books.example/opds/"))
        assertTrue(books.admits("https://books.example/covers/1.jpg"))
        assertTrue(books.admits("https://books.example:443/x"))
        assertFalse(books.admits("https://collect.attacker.example/x"))
        assertFalse(books.admits("http://books.example/x"))
        assertFalse(books.admits("https://books.example:8443/x"))
    }

    @Test
    fun nothingButHttpIsAnOrigin() {
        assertNull(OpdsOrigin.of("file:///etc/hosts"))
        assertNull(OpdsOrigin.of("ftp://books.example/x"))
        assertNotNull(OpdsOrigin.of("http://nas.local:8080/opds"))
    }

    @Test
    fun onlyHttpAndHttpsAreFetchable() {
        assertTrue(OpdsOrigin.isFetchable("https://books.example/x"))
        assertTrue(OpdsOrigin.isFetchable("http://nas.local/x"))
        assertFalse(OpdsOrigin.isFetchable("file:///etc/hosts"))
        assertFalse(OpdsOrigin.isFetchable("ftp://books.example/x"))
        assertFalse(OpdsOrigin.isFetchable("jar:file:///x!/y"))
    }

    @Test
    fun anHttpsSourceRefusesToBeTalkedDownToHttp() {
        val secure = requireNotNull(OpdsOrigin.of("https://books.example/opds/"))
        assertTrue(secure.downgrades("http://books.example/covers/1.jpg"))
        assertFalse(secure.downgrades("https://books.example/covers/1.jpg"))

        // A reader who typed `http://nas.local` meant it. Nothing is downgraded from there.
        val plain = requireNotNull(OpdsOrigin.of("http://nas.local:8080/opds"))
        assertFalse(plain.downgrades("http://nas.local:8080/1.jpg"))
    }
}

/**
 * What a feed's own hrefs are allowed to become.
 *
 * The scheme is judged where the href is *resolved*, not where it is fetched: an absolute
 * `file:` or `ftp:` href replaces the base entirely, and everything downstream -- the cover
 * load, the download, the next page -- then works from an address nothing checked. On this
 * platform it is also what kills the process: `URL.openConnection()` accepts `file:` and
 * hands back something that is not an `HttpURLConnection`.
 *
 * iOS's `OpdsResolutionTests` asserts the same cases in the same order.
 */
class OpdsResolutionTest {

    private val base = "https://library.example/opds/"

    @Test
    fun aRelativeHrefResolvesAgainstTheFeed() {
        assertEquals("https://library.example/opds/unread", OpdsDocument.resolve("unread", base))
    }

    @Test
    fun anAbsoluteHttpHrefIsKept() {
        assertEquals("http://nas.local/1.jpg", OpdsDocument.resolve("http://nas.local/1.jpg", base))
    }

    @Test
    fun anHrefWithAnyOtherSchemeResolvesToNothing() {
        assertNull(OpdsDocument.resolve("file:///etc/hosts", base))
        assertNull(OpdsDocument.resolve("ftp://library.example/x", base))
        assertNull(OpdsDocument.resolve("jar:file:///x!/y", base))
        assertNull(OpdsDocument.resolve("javascript:alert(1)", base))
    }

    @Test
    fun aSearchTemplateIsHeldToTheSameSchemes() {
        assertNull(OpdsDocument.resolve("file:///x?q={searchTerms}", base))
        assertEquals(
            "https://library.example/opds/search?q={searchTerms}",
            OpdsDocument.resolve("search?q={searchTerms}", base),
        )
    }
}
