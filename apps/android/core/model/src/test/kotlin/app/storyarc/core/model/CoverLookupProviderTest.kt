package app.storyarc.core.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * What an identifier is, which provider owns it, and where it is asked about.
 *
 * The same claims iOS's `CoverLookupProviderTests` makes, in the same order.
 */
class CoverLookupProviderTest {

    @Test
    fun `an ISBN is read without the hyphens an OPF writes it with`() {
        assertEquals(
            CoverIdentifier.Isbn("9780141187761"),
            CoverIdentifier.isbn("978-0-14-118776-1"),
        )
        assertEquals(CoverIdentifier.Isbn("014118776X"), CoverIdentifier.isbn("0 14 118776 X"))
    }

    @Test
    fun `a malformed ISBN is refused rather than put in a URL`() {
        // One request per publication is all `cover-art` allows, so a request that can only
        // fail is the only request that publication would ever get.
        assertNull(CoverIdentifier.isbn("12345"))
        assertNull(CoverIdentifier.isbn("978014118776X"))
        assertNull(CoverIdentifier.isbn(""))
    }

    @Test
    fun `a release-group id is a UUID and nothing else`() {
        val value = "B1A9C0E9-D987-4042-AE91-78D6A3267D69"
        assertEquals(
            CoverIdentifier.MusicBrainzReleaseGroup(value.lowercase()),
            CoverIdentifier.musicBrainz(value),
        )
        assertNull(CoverIdentifier.musicBrainz("not-a-uuid"))
    }

    @Test
    fun `an ASIN is ten letters and digits`() {
        assertEquals(CoverIdentifier.AudibleAsin("B08G9PRS1K"), CoverIdentifier.asin("b08g9prs1k"))
        assertNull(CoverIdentifier.asin("B08G9PRS"))
    }

    @Test
    fun `each identifier belongs to exactly one provider`() {
        assertEquals(
            CoverLookupProvider.OPEN_LIBRARY,
            CoverIdentifier.Isbn("9780141187761").provider,
        )
        assertEquals(
            CoverLookupProvider.COVER_ART_ARCHIVE,
            CoverIdentifier.MusicBrainzReleaseGroup("x").provider,
        )
        assertEquals(
            CoverLookupProvider.AUDNEXUS,
            CoverIdentifier.AudibleAsin("B08G9PRS1K").provider,
        )
    }

    @Test
    fun `Open Library is asked not to answer with a placeholder`() {
        // Without `default=false` the service answers a blank grey image with status 200,
        // and the app would store that as the reader's cover and never ask again.
        val url = CoverLookupRequest.url(CoverIdentifier.Isbn("9780141187761"))
        assertTrue(url.contains("default=false"))
        assertTrue(url.contains(CoverLookupProvider.OPEN_LIBRARY.host))
    }

    @Test
    fun `a request carries the identifier and nothing else`() {
        // `cover-art`: "it sends the identifier and nothing else: no library listing, no
        // reading history, no device identifier".
        val identifier = CoverIdentifier.AudibleAsin("B08G9PRS1K")
        val url = CoverLookupRequest.url(identifier)
        assertEquals(identifier.value, url.removePrefix("https://api.audnex.us/books/"))
    }

    @Test
    fun `every provider states a name and a host for the setting to show`() {
        for (provider in CoverLookupProvider.entries) {
            assertTrue(provider.displayName.isNotEmpty())
            assertTrue(provider.host.contains("."))
        }
        assertEquals(3, CoverLookupProvider.entries.size)
    }

    @Test
    fun `only Audnexus answers with a document rather than a picture`() {
        assertTrue(CoverLookupProvider.OPEN_LIBRARY.answersWithImage)
        assertTrue(CoverLookupProvider.COVER_ART_ARCHIVE.answersWithImage)
        assertFalse(CoverLookupProvider.AUDNEXUS.answersWithImage)
    }

    @Test
    fun `a cover request reaches only a listed https host`() {
        assertTrue(CoverImageHosts.allows("https://covers.openlibrary.org/b/isbn/1-L.jpg"))
        assertTrue(CoverImageHosts.allows("https://ia800100.us.archive.org/view/c.jpg"))
        assertTrue(CoverImageHosts.allows("https://s4.anilist.co/file/c.jpg"))
        // Not https, not listed, or listed only as a suffix of a stranger's name.
        assertFalse(CoverImageHosts.allows("http://covers.openlibrary.org/b/id/1-L.jpg"))
        assertFalse(CoverImageHosts.allows("https://tracker.example/c.jpg"))
        assertFalse(CoverImageHosts.allows("https://evilanilist.co/c.jpg"))
        assertFalse(CoverImageHosts.allows("https://anilist.co.evil.example/c.jpg"))
        assertFalse(CoverImageHosts.allows("not an address"))
    }
}

