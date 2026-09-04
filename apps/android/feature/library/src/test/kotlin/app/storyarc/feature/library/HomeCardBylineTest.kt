package app.storyarc.feature.library

import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * The line a Keep reading card sets under its title.
 *
 * `home-screen`, *The card shows how far through, not only how much is left*: "the
 * publication's author is named where the card has room for it, because a title alone is
 * not enough to recognise a book by". A folder library is full of `Vol 3` and
 * `Chapter 12`, and a shelf of those is a shelf of strangers.
 *
 * **This card has no kicker, and iOS's has one**, so the two platforms' rules are not the
 * same rule and this is not a mirror of `HomeCardIdentityTests`. iOS suppresses a byline
 * that repeats the kicker above the title; there is nothing here to repeat, so the Android
 * rule is the shorter one. Recorded rather than left to look like an omission.
 */
class HomeCardBylineTest {

    private fun publication(title: String, authors: List<String> = emptyList()) = Publication(
        identity = PublicationIdentity(normalizedPath = "/comics/$title.cbz"),
        format = PublicationFormat.CBZ,
        displayTitle = title,
        origin = MetadataOrigin.INFERRED,
        authors = authors,
    )

    @Test
    fun `the author is named`() {
        assertEquals("A. Vance", homeBylineText(publication("Ember Lines #2", listOf("A. Vance"))))
    }

    @Test
    fun `the first author, as every other cell in this app shows`() {
        val many = publication("Vol 3", listOf("A. Vance", "M. Okonjo", "T. Reyes"))

        assertEquals("A. Vance", homeBylineText(many))
    }

    @Test
    fun `a publication with no author gets no line rather than a blank one`() {
        // A row held open for the books that have no author is a gap a reader reads as a
        // bug, and a folder library is mostly books with no author.
        assertNull(homeBylineText(publication("Vol 3")))
        assertNull(homeBylineText(publication("Vol 3", listOf(""))))
        assertNull(homeBylineText(publication("Vol 3", listOf("   "))))
    }
}
