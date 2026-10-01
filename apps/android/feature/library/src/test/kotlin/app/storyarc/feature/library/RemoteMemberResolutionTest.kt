package app.storyarc.feature.library

import app.storyarc.core.catalogue.OpdsAcquisition
import app.storyarc.core.catalogue.OpdsEntry
import app.storyarc.core.catalogue.OpdsFeed
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * Finding, in a freshly read feed, the entry a catalogue-only row names.
 *
 * `collections-and-reading-lists`' bulk download "queues them per offline-downloads" for a
 * member with no local file -- a unified-shelf row [OpdsContributor] built with no
 * acquisition URL kept on it. This pins the matching [KeepOffline]'s remote enqueue does the
 * fetch around. iOS asserts the same cases in `RemoteMemberResolutionTests`.
 */
class RemoteMemberResolutionTest {

    private fun acquisition(href: String, mediaType: String = "application/epub+zip") =
        OpdsAcquisition(href = href, mediaType = mediaType, kind = OpdsAcquisition.Kind.OPEN)

    @Test
    fun `an OPDS remote id finds its entry and the best acquisition`() {
        val entry = OpdsEntry(
            id = "hl09", title = "Harbour Lights 09",
            acquisitions = listOf(acquisition("https://library.example/hl09.epub")),
        )
        val feed = OpdsFeed(title = "Library", publications = listOf(entry))

        val found = RemoteMemberResolution.opdsEntry("opds:hl09", feed)

        assertEquals("hl09", found?.first?.id)
        assertEquals("https://library.example/hl09.epub", found?.second?.href)
    }

    @Test
    fun `a remote id with no OPDS prefix is not matched, even if it names a real entry`() {
        // "removePrefix" is a no-op on a string that does not carry the prefix, so an
        // unprefixed id -- a Kavita chapter's `"chapter:9"`, or anything else -- reaches
        // the lookup below unchanged. Dropping the `startsWith` guard would let this one
        // match the entry it happens to equal, which is exactly the failure this pins.
        val entry = OpdsEntry(
            id = "entry9", title = "Chapter 9",
            acquisitions = listOf(acquisition("https://library.example/9.epub")),
        )
        val feed = OpdsFeed(title = "Library", publications = listOf(entry))

        assertNull(RemoteMemberResolution.opdsEntry("entry9", feed))
    }

    @Test
    fun `an entry a later feed no longer lists resolves to nothing`() {
        val feed = OpdsFeed(title = "Library", publications = emptyList())

        assertNull(RemoteMemberResolution.opdsEntry("opds:hl09", feed))
    }

    @Test
    fun `the id matched is the one named, not merely the first on the page`() {
        val wanted = OpdsEntry(
            id = "hl09", title = "Harbour Lights 09",
            acquisitions = listOf(acquisition("https://library.example/hl09.epub")),
        )
        val other = OpdsEntry(
            id = "hl08", title = "Harbour Lights 08",
            acquisitions = listOf(acquisition("https://library.example/hl08.epub")),
        )
        val feed = OpdsFeed(title = "Library", publications = listOf(other, wanted))

        val found = RemoteMemberResolution.opdsEntry("opds:hl09", feed)

        assertEquals("hl09", found?.first?.id)
    }

    @Test
    fun `an entry with nothing this app can open resolves to nothing`() {
        val entry = OpdsEntry(
            id = "hl09", title = "Harbour Lights 09",
            acquisitions = listOf(
                OpdsAcquisition(
                    href = "/hl09.cb7",
                    mediaType = "application/x-7z-compressed",
                    kind = OpdsAcquisition.Kind.OPEN,
                ),
            ),
        )
        val feed = OpdsFeed(title = "Library", publications = listOf(entry))

        assertNull(RemoteMemberResolution.opdsEntry("opds:hl09", feed))
    }

    @Test
    fun `the best acquisition is picked, the same way the catalogue page would`() {
        val entry = OpdsEntry(
            id = "hl09", title = "Harbour Lights 09",
            acquisitions = listOf(
                acquisition("https://library.example/hl09.cbz", mediaType = "application/vnd.comicbook+zip"),
                acquisition("https://library.example/hl09.epub", mediaType = "application/epub+zip"),
            ),
        )
        val feed = OpdsFeed(title = "Library", publications = listOf(entry))

        val found = RemoteMemberResolution.opdsEntry("opds:hl09", feed)

        assertEquals("https://library.example/hl09.epub", found?.second?.href)
    }
}
