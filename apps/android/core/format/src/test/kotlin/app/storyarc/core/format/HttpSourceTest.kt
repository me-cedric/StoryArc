package app.storyarc.core.format

import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * A server that answers ranges, and misbehaves on demand.
 *
 * The lies are named after the ones `scripts/opds-server.mjs` can be asked to tell, so a case
 * proved here can be watched over the wire against the mock and the two artefacts describe
 * one catalogue of misbehaviour rather than two. iOS's `FakeServer` is the same server.
 */
private class FakeServer(val body: ByteArray, val lie: Lie? = null) : RangeTransport {

    enum class Lie {
        /** Answers 200 with the whole resource, ignoring the range. */
        IGNORE,

        /** Answers 200 but sends only the requested slice. */
        STATUS,

        /** Answers 206 with the wrong total in `Content-Range`. */
        TOTAL,

        /** Answers 206 with the bytes of a different range. */
        OFFSET,

        /** Answers 206 with fewer bytes than it promised. */
        SHORT,

        /** Answers 206 with no `Content-Range` at all. */
        UNLABELLED,

        /** Answers from an address other than the one asked for. */
        MOVED,

        /** Answers 416, as a server whose file shrank would. */
        GONE,

        /** Answers unhappily. */
        REFUSED,
    }

    companion object {
        /**
         * Byte `n` is `n % 251`, the same pattern the mock's self-test corpus uses: a
         * window's contents are then arithmetic rather than a second read agreeing with the
         * first, and 251 keeps an off-by-a-block bug off identical bytes.
         */
        fun ofSize(count: Int, lie: Lie? = null) =
            FakeServer(ByteArray(count) { (it % 251).toByte() }, lie)
    }

    override suspend fun fetch(url: String, from: Long, through: Long): HttpAnswer {
        val count = (through - from).toInt() + 1
        val total = body.size
        return when (lie) {
            Lie.IGNORE -> HttpAnswer(200, body, url = url)
            Lie.STATUS -> HttpAnswer(200, slice(from.toInt(), count), url = url)
            Lie.GONE -> HttpAnswer(416, ByteArray(0), url = url)
            Lie.REFUSED -> HttpAnswer(503, ByteArray(0), url = url)
            Lie.MOVED -> HttpAnswer(
                206,
                slice(from.toInt(), count),
                "bytes $from-$through/$total",
                "$url/elsewhere",
            )
            Lie.UNLABELLED -> HttpAnswer(206, slice(from.toInt(), count), url = url)
            else -> {
                val start =
                    if (lie == Lie.OFFSET) minOf(from.toInt() + 64, maxOf(0, total - count))
                    else from.toInt()
                val sending = if (lie == Lie.SHORT) count - 1 else count
                HttpAnswer(
                    206,
                    slice(start, sending),
                    "bytes $from-$through/${if (lie == Lie.TOTAL) total + 1024 else total}",
                    url,
                )
            }
        }
    }

    private fun slice(start: Int, count: Int): ByteArray {
        val end = minOf(start + maxOf(count, 0), body.size)
        return if (start >= end) ByteArray(0) else body.copyOfRange(start, end)
    }
}

/** Counts what a reader actually touches, so ranged reads can be asserted rather than said. */
private class Counted(private val inner: RandomAccessSource) : RandomAccessSource {
    var reads = 0
        private set

    override val length: Long get() = inner.length

    override suspend fun read(offset: Long, count: Int): ByteArray {
        reads++
        return inner.read(offset, count)
    }

    override fun close() = inner.close()
}

/**
 * Reading over HTTP range requests.
 *
 * iOS's `HttpSourceTests` mirrors this file, case for case: a difference between the
 * platforms about what a server is allowed to answer is a failing test rather than a page
 * that opens on one phone and not the other.
 */
class HttpSourceTest {

    private val address = "https://library.example/files/comic.cbz"

    private suspend fun opened(server: FakeServer) = HttpSource.open(address, server)

    // Content-Range

    @Test
    fun aContentRangeIsReadIntoItsThreeNumbers() {
        assertEquals(ContentRange(0, 15, 4096), ContentRange.of("bytes 0-15/4096"))
    }

    /**
     * Every shape that is not a window of bytes that arrived. The 416 form and the
     * unknown-total form are both legal headers and neither describes a body, so a source
     * that accepted either would be checking a read against nothing.
     */
    @Test
    fun aMalformedContentRangeIsNoContentRange() {
        val headers = listOf(
            "bytes */4096", "bytes 0-15/*", "items 0-15/4096", "bytes 15-0/4096",
            "bytes 0-15/8", "bytes 0-15", "bytes -1-15/4096", "0-15/4096", "bytes", "",
        )
        for (header in headers) {
            assertNull("`$header` is not a range of arrived bytes", ContentRange.of(header))
        }
    }

    @Test
    fun anAbsentContentRangeIsNoContentRange() {
        assertNull(ContentRange.of(null))
    }

    // Opening

    @Test
    fun openingLearnsTheLengthFromOneByte() = runTest {
        assertEquals(4096L, opened(FakeServer.ofSize(4096)).length)
    }

    /**
     * The whole point of probing: a server that will not serve ranges has to be found out
     * before a reader is waiting on a page, not after. `offline-downloads` then falls back to
     * downloading first, which is what the app already does.
     */
    @Test
    fun aServerThatIgnoresRangesIsRefusedRatherThanStreamedBadly() = runTest {
        val thrown = runCatching { opened(FakeServer.ofSize(4096, FakeServer.Lie.IGNORE)) }
        assertEquals(HttpSourceException.NotRanged, thrown.exceptionOrNull())
    }

    @Test
    fun a206WithNothingSayingHowLongItIsCannotBeOpened() = runTest {
        val thrown = runCatching { opened(FakeServer.ofSize(4096, FakeServer.Lie.UNLABELLED)) }
        assertEquals(HttpSourceException.UnknownLength, thrown.exceptionOrNull())
    }

    @Test
    fun aRefusalIsNamedWithItsStatus() = runTest {
        val thrown = runCatching { opened(FakeServer.ofSize(4096, FakeServer.Lie.REFUSED)) }
        assertEquals(HttpSourceException.Refused(503), thrown.exceptionOrNull())
    }

    @Test
    fun aRedirectedProbeIsNotTheResourceThatWasAskedFor() = runTest {
        val thrown = runCatching { opened(FakeServer.ofSize(4096, FakeServer.Lie.MOVED)) }
        assertTrue(thrown.exceptionOrNull() is HttpSourceException.Moved)
    }

    // Reading

    @Test
    fun aRangeIsTheBytesAskedFor() = runTest {
        val server = FakeServer.ofSize(4096)
        val read = opened(server).read(1000, 16)
        assertArrayEquals(server.body.copyOfRange(1000, 1016), read)
    }

    /**
     * The read ADR-0008 makes first: a ZIP keeps its central directory at the end, so the
     * tail is where every archive is opened from.
     */
    @Test
    fun theTailIsReadableWithoutTheRest() = runTest {
        val server = FakeServer.ofSize(4096)
        val (tail, offset) = opened(server).readTail(64)
        assertEquals(4032L, offset)
        assertArrayEquals(server.body.copyOfRange(4032, 4096), tail)
    }

    /**
     * The contract every source keeps: fewer bytes only at the end, never more. A parser that
     * wants a short read to be an error asks through `readExactly`.
     */
    @Test
    fun aReadPastTheEndIsShortRatherThanRefused() = runTest {
        val source = opened(FakeServer.ofSize(4096))
        assertEquals(16, source.read(4080, 64).size)
        assertEquals(0, source.read(4096, 64).size)
        assertEquals(0, source.read(0, 0).size)
    }

    @Test
    fun aReadBeforeTheStartIsOutOfBounds() = runTest {
        val source = opened(FakeServer.ofSize(4096))
        val thrown = runCatching { source.read(-1, 16) }
        assertTrue(thrown.exceptionOrNull() is SourceOutOfBoundsException)
    }

    @Test
    fun readExactlyRefusesWhatReadWouldClamp() = runTest {
        val source = opened(FakeServer.ofSize(4096))
        val thrown = runCatching { source.readExactly(4080, 64) }
        assertTrue(thrown.exceptionOrNull() is SourceOutOfBoundsException)
    }

    // Servers that answer wrongly

    /**
     * A correct status, correct headers, and the bytes of some other window.
     *
     * **This layer cannot catch it, and pretending otherwise would be the more dangerous
     * mistake.** HTTP carries no identity for the bytes it delivers: a body that fills its
     * `Content-Range` is indistinguishable from the right one. What catches it is the
     * container -- a ZIP is signatures, offsets that have to agree with each other, and a CRC
     * per entry -- which is a second reason ADR-0008 was right to make the reader ours. The
     * test below is the one that matters; this one records what the transport does *not*
     * promise, so nobody builds on a guarantee that was never made.
     */
    @Test
    fun aWellFormed206WithTheWrongBytesPassesTheTransportUnnoticed() = runTest {
        val server = FakeServer.ofSize(4096, FakeServer.Lie.OFFSET)
        val read = HttpSource(address, 4096, server).read(1000, 16)
        assertEquals(16, read.size)
        assertNotEquals(server.body.copyOfRange(1000, 1016).toList(), read.toList())
    }

    /**
     * And the container is where it stops. A server shifting every answer by 64 bytes yields
     * an archive that does not parse, rather than pages of noise.
     */
    @Test
    fun aServerThatShiftsEveryAnswerYieldsNoArchive() = runTest {
        val bytes = FixtureCorpus.file("comics/natural-sort.cbz").readBytes()
        val shifted = HttpSource(
            address,
            bytes.size.toLong(),
            FakeServer(bytes, FakeServer.Lie.OFFSET),
        )
        val thrown = runCatching {
            val archive = ComicArchiveOpener.open(shifted)
            // A container that survived the shift must at least not claim pages that are not
            // there, so reading one is part of the assertion rather than after it.
            archive.pages.firstOrNull()?.let { archive.data(it) }
        }
        assertTrue("a shifted server must not yield readable pages", thrown.isFailure)
    }

    @Test
    fun aBodyShorterThanItPromisedIsRefused() = runTest {
        val source = HttpSource(address, 4096, FakeServer.ofSize(4096, FakeServer.Lie.SHORT))
        val thrown = runCatching { source.read(1000, 16) }
        assertEquals(HttpSourceException.ShortBody(16, 15), thrown.exceptionOrNull())
    }

    /**
     * A total that moved means the file was replaced while a reader was in it. Continuing
     * would read the new file with the old file's central directory.
     */
    @Test
    fun aTotalThatChangedIsADifferentPublication() = runTest {
        val source = HttpSource(address, 4096, FakeServer.ofSize(4096, FakeServer.Lie.TOTAL))
        val thrown = runCatching { source.read(1000, 16) }
        assertEquals(HttpSourceException.LengthChanged(4096), thrown.exceptionOrNull())
    }

    @Test
    fun a416AfterOpeningMeansTheFileShrank() = runTest {
        val source = HttpSource(address, 4096, FakeServer.ofSize(4096, FakeServer.Lie.GONE))
        val thrown = runCatching { source.read(1000, 16) }
        assertEquals(HttpSourceException.LengthChanged(4096), thrown.exceptionOrNull())
    }

    /**
     * The dangerous shape: the status says "all of it" and the body is a fragment. A reader
     * that trusted the status would treat sixteen bytes as the whole archive.
     */
    @Test
    fun a200CarryingOnlyASliceIsRefused() = runTest {
        val source = HttpSource(address, 4096, FakeServer.ofSize(4096, FakeServer.Lie.STATUS))
        val thrown = runCatching { source.read(1000, 16) }
        assertTrue(thrown.exceptionOrNull() is HttpSourceException.ShortBody)
    }

    /**
     * A proxy that woke up mid-publication and started sending everything. Wasteful, not
     * wrong: the bytes are all there, so the window is cut out of them.
     */
    @Test
    fun a200CarryingTheWholeResourceIsStillReadable() = runTest {
        val server = FakeServer.ofSize(4096, FakeServer.Lie.IGNORE)
        val read = HttpSource(address, 4096, server).read(1000, 16)
        assertArrayEquals(server.body.copyOfRange(1000, 1016), read)
    }

    @Test
    fun aRedirectMidReadIsRefusedRatherThanFollowedBlindly() = runTest {
        val source = HttpSource(address, 4096, FakeServer.ofSize(4096, FakeServer.Lie.MOVED))
        val thrown = runCatching { source.read(0, 16) }
        assertTrue(thrown.exceptionOrNull() is HttpSourceException.Moved)
    }

    @Test
    fun aServerErrorMidReadIsNamedWithItsStatus() = runTest {
        val source = HttpSource(address, 4096, FakeServer.ofSize(4096, FakeServer.Lie.REFUSED))
        val thrown = runCatching { source.read(0, 16) }
        assertEquals(HttpSourceException.Refused(503), thrown.exceptionOrNull())
    }

    // The whole point

    /**
     * A real archive from the shared corpus, read over ranges and never downloaded.
     *
     * This is ADR-0008's claim, measured: the pages a reader sees are the pages the local
     * file has, and getting to the first one is a handful of requests. The fixture is the
     * data-descriptor one on purpose -- its local headers carry zeros, so a reader that
     * trusted them over the central directory would fail here and nowhere else.
     */
    @Test
    fun aCorpusArchiveOpensOverRangesAndReadsTheSamePages() = runTest {
        val file = FixtureCorpus.file("comics/data-descriptor.cbz")
        val bytes = file.readBytes()
        val counted = Counted(HttpSource.open(address, FakeServer(bytes)))

        val streamed = ComicArchiveOpener.open(counted)
        val local = ComicArchiveOpener.open(file)
        assertEquals(local.pages.map { it.path }, streamed.pages.map { it.path })
        assertTrue(streamed.pages.isNotEmpty())

        val cover = requireNotNull(streamed.coverPage)
        assertArrayEquals(local.data(requireNotNull(local.coverPage)), streamed.data(cover))

        // ADR-0008's structural claim, which is about the *number* of requests rather than
        // the bytes: opening an archive and reading one page is a handful of ranged reads
        // whatever the archive weighs. The byte saving cannot be asserted here and it is
        // worth saying why -- every ZIP in the corpus is under two kilobytes, so a single
        // 64 KB tail read already covers the whole file and "less than all of it" is
        // arithmetically impossible. The saving is real at 400 MB and unmeasurable at 538
        // bytes; the request count is the part that holds at both sizes.
        assertTrue("opened in ${counted.reads} reads", counted.reads in 1..8)
    }
}
