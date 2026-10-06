package app.storyarc.core.model

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Where a cover may be written back, and -- the point of the suite -- where it may not.
 *
 * Task 5.2 of `cover-for-every-publication` asks for a test that no write action appears
 * anywhere else, "so the feature cannot drift into offering a 403". The subject hierarchy is
 * sealed, so a later row has to pick a case and this suite has to be told about it. iOS's
 * `CoverWriteBackTests` makes the same five claims.
 */
class CoverWriteBackTest {

    @Test
    fun `a reading list the reader owns is offered the write`() {
        assertEquals(
            CoverWriteOffer.KavitaReadingList(7),
            CoverWriteBack.offer(CoverWriteSubject.KavitaReadingList(7, promoted = false)),
        )
    }

    @Test
    fun `a promoted reading list is not, because it may belong to anybody`() {
        // `ReadingList/lists` answers with the reader's own lists plus the promoted ones, so
        // promoted is the only case where the answer does not prove ownership.
        assertEquals(
            CoverWriteOffer.None,
            CoverWriteBack.offer(CoverWriteSubject.KavitaReadingList(7, promoted = true)),
        )
    }

    @Test
    fun `no Kavita entity but a reading list is offered a write`() {
        // Five of Kavita's six cover routes need the administrator role. An action that
        // exists and answers 403 teaches a reader that the app is broken.
        val admin = listOf(
            CoverWriteSubject.KavitaSeries,
            CoverWriteSubject.KavitaChapter,
            CoverWriteSubject.KavitaCollection,
            CoverWriteSubject.KavitaLibrary,
        )
        for (subject in admin) {
            assertEquals(CoverWriteOffer.None, CoverWriteBack.offer(subject))
        }
    }

    @Test
    fun `no OPDS row is offered a write, in either version of the protocol`() {
        // OPDS has no write operation in 1.2 or 2.0. Not a missing feature: an absent
        // concept.
        assertEquals(CoverWriteOffer.None, CoverWriteBack.offer(CoverWriteSubject.Opds))
    }

    @Test
    fun `a file on this device has nowhere to write to`() {
        assertEquals(CoverWriteOffer.None, CoverWriteBack.offer(CoverWriteSubject.LocalFile))
    }
}
