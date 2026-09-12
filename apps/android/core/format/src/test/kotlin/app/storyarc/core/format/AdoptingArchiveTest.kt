package app.storyarc.core.format

import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * A server that answers ranges honestly, serving one fixture's bytes.
 *
 * The dishonest ones are `HttpSourceTest`'s business. This suite is about what happens
 * *above* a source that works, so the only thing asked of this one is that it behaves.
 */
private class HonestServer(private val body: ByteArray) : RangeTransport {
    /**
     * Set once the transfer has finished, so a later read proves where it came from.
     *
     * A switch that never happened is invisible from the outside -- the same pages, the same
     * bytes -- so the only way to see it is to take the network away and watch the reader
     * carry on.
     */
    var isUnplugged = false

    override suspend fun fetch(url: String, from: Long, through: Long): HttpAnswer {
        if (isUnplugged) throw IllegalStateException("the network is gone")
        val end = minOf(through, body.size - 1L)
        return HttpAnswer(
            status = 206,
            body = body.copyOfRange(from.toInt(), end.toInt() + 1),
            contentRange = "bytes $from-$end/${body.size}",
            url = url,
        )
    }
}

/**
 * `offline-downloads`' *Reading while downloading*, the half that is hard to get right.
 *
 * > **THEN** it opens immediately by streaming, and switches to the local copy when the
 * > download completes, **without interrupting reading**
 *
 * "Without interrupting" is the claim worth proving, so it is proved against the real corpus
 * rather than against a stub: a comic is opened over a ranged transport, the local copy that a
 * finished download would leave behind is handed over, and the page list and the page bytes
 * are asked whether anything moved.
 *
 * iOS's `AdoptingArchiveTests` asserts the same cases.
 */
class AdoptingArchiveTest {

    private val streamedName = "stored-entries.cbz"

    private val server = HonestServer(FixtureCorpus.file("comics/$streamedName").readBytes())

    private suspend fun streamed(): ComicArchiveReading = ComicArchiveOpener.open(
        HttpSource.open("https://books.example/$streamedName", server),
    )

    private suspend fun onDisk(name: String = streamedName): ComicArchiveReading =
        ComicArchiveOpener.open(FixtureCorpus.file("comics/$name"))

    @Test
    fun `the local copy takes over and the pages do not move`() = runTest {
        val reading = AdoptingArchive(streamed())
        val before = reading.pages

        assertTrue(reading.adopt(onDisk()))

        assertEquals(before, reading.pages)
        // The switch really happened: with the network gone, a page nobody had read yet
        // still reads. Without this the whole suite passes on an `adopt` that does nothing.
        server.isUnplugged = true
        assertTrue(reading.data(before.last()).isNotEmpty())
    }

    @Test
    fun `the page the reader is on still reads the same bytes afterwards`() = runTest {
        val reading = AdoptingArchive(streamed())
        // Page 14 is the reader in the scenario. This fixture is shorter, so the page in the
        // middle of it stands in for them -- what matters is that it is not page one.
        val page = reading.pages[reading.pages.size / 2]
        val overTheWire = reading.data(page)

        assertTrue(reading.adopt(onDisk()))
        server.isUnplugged = true

        assertArrayEquals(overTheWire, reading.data(page))
    }

    @Test
    fun `an archive holding different pages is refused, and nothing moves`() = runTest {
        val reading = AdoptingArchive(streamed())
        val before = reading.pages
        val other = onDisk("natural-sort.cbz")
        // The guard is only worth having if the two really do disagree.
        assertNotEquals(before, other.pages)

        assertFalse(reading.adopt(other))

        assertEquals(before, reading.pages)
        // And the archive still reads, over the transport it was opened on.
        assertTrue(reading.data(before.first()).isNotEmpty())
    }

    @Test
    fun `a declared spread is still a declared spread through the wrapper`() = runTest {
        // `doublePageIndices` and `skippedPageCount` both have a harmless-looking default --
        // no spreads, nothing skipped -- so a wrapper that answered for itself would tell the
        // reader a lie the reader cannot check. Both fixtures are chosen for a non-default
        // answer, or these two cases would pass on a wrapper that carried nothing.
        val direct = onDisk("manga-metadata.cbz")
        val wrapped = AdoptingArchive(onDisk("manga-metadata.cbz"))

        assertEquals(listOf(2), wrapped.doublePageIndices)
        assertEquals(direct.pages, wrapped.pages)
        assertEquals(direct.coverPage, wrapped.coverPage)
    }

    @Test
    fun `a skipped page is still counted through the wrapper`() = runTest {
        val wrapped = AdoptingArchive(onDisk("unsupported-codec.cbz"))

        assertEquals(1, wrapped.skippedPageCount)
    }
}
