package app.storyarc.core.format

import java.io.File
import java.io.RandomAccessFile

/**
 * Bytes that can be read at an arbitrary offset.
 *
 * The abstraction ADR-0008 is built on. Everything above it — the ZIP reader,
 * the page decoder, the reader UI — is unaware of whether the bytes came from a
 * local file, an SMB share, or an HTTP range request. That is what makes
 * streaming stop being a special case.
 *
 * `suspend` on purpose: the local implementation does not need it, and every
 * remote one does. Retrofitting suspension through a parser is worse than
 * carrying it from the start.
 */
interface RandomAccessSource : AutoCloseable {
    /**
     * Total length in bytes. Known up front for every source StoryArc targets —
     * SMB reports it in a file-info response, HTTP in `Content-Length`.
     */
    val length: Long

    /**
     * Reads up to [count] bytes from [offset]. Returns fewer only at the end of
     * the source; never more.
     */
    suspend fun read(offset: Long, count: Int): ByteArray

    override fun close() {}
}

class SourceOutOfBoundsException(offset: Long, count: Int, length: Long) :
    Exception("read of $count bytes at $offset exceeds source length $length")

class SourceUnreadableException(message: String = "source unreadable") : Exception(message)

/**
 * Reads exactly [count] bytes, or throws. Parsers want this: a short read
 * mid-structure means the file is malformed, not that the caller should retry
 * with less.
 */
suspend fun RandomAccessSource.readExactly(offset: Long, count: Int): ByteArray {
    if (offset < 0 || count < 0 || offset + count > length) {
        throw SourceOutOfBoundsException(offset, count, length)
    }
    val data = read(offset, count)
    if (data.size != count) throw SourceUnreadableException("short read at $offset")
    return data
}

/** The last [count] bytes and the offset they start at, or the whole source when shorter. */
suspend fun RandomAccessSource.readTail(count: Int): Pair<ByteArray, Long> {
    val size = minOf(count.toLong(), length)
    val offset = length - size
    return readExactly(offset, size.toInt()) to offset
}

/** A local file, read through a seeking handle. */
class FileSource(file: File) : RandomAccessSource {
    private val handle = RandomAccessFile(file, "r")

    override val length: Long = handle.length()

    override suspend fun read(offset: Long, count: Int): ByteArray {
        val available = (length - offset).coerceAtLeast(0L)
        val toRead = minOf(count.toLong(), available).toInt()
        if (toRead <= 0) return ByteArray(0)
        val buffer = ByteArray(toRead)
        synchronized(handle) {
            handle.seek(offset)
            handle.readFully(buffer)
        }
        return buffer
    }

    override fun close() = handle.close()
}

/**
 * A source backed by bytes already in memory. Used by tests, and by the sparse
 * cache once a range has been fetched.
 */
class DataSource(private val data: ByteArray) : RandomAccessSource {
    override val length: Long = data.size.toLong()

    override suspend fun read(offset: Long, count: Int): ByteArray {
        if (offset < 0 || offset > data.size) {
            throw SourceOutOfBoundsException(offset, count, length)
        }
        val start = offset.toInt()
        val end = minOf(start + count, data.size)
        return data.copyOfRange(start, end)
    }
}
