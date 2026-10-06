package app.storyarc.core.format

import app.storyarc.core.model.PublicationIdentity
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Test

/**
 * `cover-for-every-publication` task 1.1: where an audio file's extracted artwork is filed.
 *
 * A provider's document is read through `/proc/self/fd/N`, and the scan closes that
 * descriptor before it opens the next document, so the next one gets the same number. Keyed
 * by that path, every audiobook in a picked folder wrote its cover over the one before and
 * every row showed the last book's picture.
 */
class AudiobookCoverKeyTest {

    private val first = PublicationIdentity(contentDigest = "sha-first", normalizedPath = "content://a")
    private val second = PublicationIdentity(contentDigest = "sha-second", normalizedPath = "content://b")

    @Test
    fun `two documents read through one descriptor number get two covers`() {
        val reused = "/proc/self/fd/87"

        assertNotEquals(
            PublicationIndexer.audiobookCoverKey(reused, first),
            PublicationIndexer.audiobookCoverKey(reused, second),
        )
    }

    @Test
    fun `a document is filed under what it is, not under how it was opened`() {
        assertEquals(
            PublicationIndexer.audiobookCoverKey("/proc/self/fd/87", first),
            PublicationIndexer.audiobookCoverKey("/proc/self/fd/12", first),
        )
    }

    @Test
    fun `a file with a path of its own keeps the key it always had`() {
        // Unchanged, so every cover already extracted on a device is still found.
        val path = "/storage/emulated/0/Audiobooks/Sea Room.m4b"

        assertEquals(path, PublicationIndexer.audiobookCoverKey(path, first))
    }
}
