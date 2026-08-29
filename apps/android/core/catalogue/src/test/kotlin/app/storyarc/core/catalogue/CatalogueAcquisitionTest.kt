package app.storyarc.core.catalogue

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Which format an entry opens as, and what the reader is offered instead.
 *
 * `opds-catalog`: "the app selects EPUB for reflowable reading and lets the user choose
 * another format from the publication detail screen", and an entry with nothing readable is
 * "listed but marked unreadable, naming the formats offered". Both halves are decided here
 * rather than on the screen, so the screen has nothing to get wrong. iOS's
 * `CatalogueAcquisitionTests` asserts the same cases.
 */
class CatalogueAcquisitionTest {

    private fun entry(vararg offers: Pair<String, OpdsAcquisition.Kind>) = OpdsEntry(
        id = "urn:uuid:1",
        title = "The Long Field",
        acquisitions = offers.mapIndexed { position, offer ->
            OpdsAcquisition("https://library.example/get/$position", offer.first, offer.second)
        },
    )

    private fun offering(vararg types: String) =
        entry(*types.map { it to OpdsAcquisition.Kind.DIRECT }.toTypedArray())

    @Test
    fun epubIsChosenWhereverItSitsInTheFeed() {
        val offered = offering("application/pdf", "application/epub+zip")
        assertEquals("application/epub+zip", CatalogueAcquisition.best(offered)?.mediaType)
    }

    @Test
    fun aComicIsPreferredToThePdfCopyOfIt() {
        // A comic offered as both CBZ and PDF is a comic, and the PDF is a worse copy.
        val offered = offering("application/pdf", "application/vnd.comicbook+zip")
        assertEquals(
            "application/vnd.comicbook+zip",
            CatalogueAcquisition.best(offered)?.mediaType,
        )
    }

    @Test
    fun theChoiceIsOfferedBestFirst() {
        val offered = offering(
            "application/pdf",
            "application/vnd.comicbook+zip",
            "application/epub+zip",
        )
        assertEquals(
            listOf(
                "application/epub+zip",
                "application/vnd.comicbook+zip",
                "application/pdf",
            ),
            CatalogueAcquisition.readable(offered).map { it.mediaType },
        )
    }

    @Test
    fun twoOfOneFormatKeepTheOrderTheFeedListedThemIn() {
        // Which of two EPUBs opens by default must not change between runs.
        val offered = offering("application/epub+zip", "application/epub+zip")
        assertEquals(
            offered.acquisitions.first().href,
            CatalogueAcquisition.readable(offered).first().href,
        )
    }

    @Test
    fun aTypeWithParametersIsStillThatType() {
        // Several servers append `;charset=utf-8`, and an exact-match table called that
        // unreadable.
        val offered = offering("application/epub+zip;charset=utf-8")
        assertNotNull(CatalogueAcquisition.best(offered))
        assertTrue(CatalogueAcquisition.unreadable(offered).isEmpty())
    }

    @Test
    fun aFormatWithNoDecoderIsNamedRatherThanOffered() {
        // `publication-formats` leaves 7-Zip undecoded. The entry is listed, the refusal
        // names the format, and nothing pretends it can be opened.
        val offered = offering("application/vnd.comicbook+7z")
        assertNull(CatalogueAcquisition.best(offered))
        assertEquals(listOf("CB7"), CatalogueAcquisition.unreadable(offered))
    }

    @Test
    fun anUnknownMediaTypeIsNamedVerbatim() {
        val offered = offering("application/x-mobipocket-ebook")
        assertEquals(
            listOf("application/x-mobipocket-ebook"),
            CatalogueAcquisition.unreadable(offered),
        )
    }

    @Test
    fun oneFormatOfferedTwiceIsNamedOnce() {
        val offered = offering("application/x-mobi", "application/x-mobi")
        assertEquals(1, CatalogueAcquisition.unreadable(offered).size)
    }

    @Test
    fun aBorrowIsRefusedByName() {
        // `opds-catalog`: an indirect acquisition makes the app "state that the acquisition
        // type is not supported rather than failing silently". Neither readable nor
        // unreadable -- it is a flow this app does not have, which is a different sentence.
        val offered = entry("application/epub+zip" to OpdsAcquisition.Kind.BORROW)
        assertTrue(CatalogueAcquisition.readable(offered).isEmpty())
        assertTrue(CatalogueAcquisition.unreadable(offered).isEmpty())
        assertEquals(listOf(OpdsAcquisition.Kind.BORROW), CatalogueAcquisition.unsupported(offered))
    }

    @Test
    fun eachRefusedKindIsStatedOnceAndInFeedOrder() {
        val offered = entry(
            "application/epub+zip" to OpdsAcquisition.Kind.BUY,
            "application/pdf" to OpdsAcquisition.Kind.BUY,
            "application/epub+zip" to OpdsAcquisition.Kind.BORROW,
        )
        assertEquals(
            listOf(OpdsAcquisition.Kind.BUY, OpdsAcquisition.Kind.BORROW),
            CatalogueAcquisition.unsupported(offered),
        )
    }

    @Test
    fun anEntryOfferingNothingIsOfferedNothing() {
        val offered = OpdsEntry(id = "urn:uuid:2", title = "Nothing At All")
        assertNull(CatalogueAcquisition.best(offered))
        assertTrue(CatalogueAcquisition.readable(offered).isEmpty())
        assertTrue(CatalogueAcquisition.unreadable(offered).isEmpty())
        assertTrue(CatalogueAcquisition.unsupported(offered).isEmpty())
    }

    @Test
    fun aSampleIsSomethingToFetch() {
        val offered = entry("application/epub+zip" to OpdsAcquisition.Kind.SAMPLE)
        assertNotNull(CatalogueAcquisition.best(offered))
    }
}
