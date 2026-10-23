package app.storyarc.core.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * `library-sync` task 5.9: a conflict a sync found is kept in the document's own spelling until
 * the reader answers it, so it survives the process that found it.
 */
class DocumentConflictTest {

    private val conflict = ProgressPull.Conflict(
        resolved = ReadingProgress(
            identity = PublicationIdentity(contentDigest = "d1", normalizedPath = "/a/Sea Room"),
            position = ReadingPosition.Listening(part = 1, partCount = 3, offsetMillis = 4_000, ofMillis = 90_000),
            updatedAtEpochMillis = 1_767_225_600_000L,
        ),
        discarded = ReadingPosition.Listening(part = 0, partCount = 3, offsetMillis = 1_000, ofMillis = 90_000),
    )

    @Test
    fun `a conflict reads back as it was written`() {
        assertEquals(listOf(conflict), DocumentConflict.decode(DocumentConflict.encode(listOf(conflict))))
    }

    @Test
    fun `text this build cannot read is no conflict at all`() {
        assertTrue(DocumentConflict.decode("not json").isEmpty())
        assertTrue(DocumentConflict.decode("").isEmpty())
    }

    @Test
    fun `a notice names a publication by the last segment of its path, without its extension`() {
        assertEquals("Sea Room", conflict.resolved.identity.leafTitle)
        assertEquals("Bone 01", PublicationIdentity(normalizedPath = "content://tree/primary%3AComics/document/primary%3AComics%2FBone%2001.cbz").leafTitle)
        assertEquals("", PublicationIdentity(contentDigest = "d1").leafTitle)
    }
}
