package app.storyarc.core.format

import android.content.ContentResolver
import android.net.Uri
import android.os.ParcelFileDescriptor
import java.io.FileInputStream
import java.nio.ByteBuffer

/**
 * Bytes behind a content `Uri`, read at arbitrary offsets.
 *
 * The Storage Access Framework hands back a `Uri`, not a path, so nothing in this
 * layer can open a user-picked folder with `java.io.File`. This is the adapter
 * that makes the rest of it work unchanged: every reader already takes a
 * [RandomAccessSource] (ADR-0008), so a CBZ on a Google Drive provider is indexed
 * with the same ranged reads as one on internal storage.
 *
 * Backed by a [ParcelFileDescriptor] and a channel rather than an `InputStream`,
 * because a stream cannot seek and ADR-0008's whole premise is that it does not
 * have to read a 400 MB archive to show page one.
 */
class UriSource(
    private val resolver: ContentResolver,
    private val uri: Uri,
) : RandomAccessSource {

    private val descriptor: ParcelFileDescriptor =
        resolver.openFileDescriptor(uri, "r")
            ?: throw SourceUnreadableException("no file descriptor for $uri")

    private val stream = FileInputStream(descriptor.fileDescriptor)
    private val channel = stream.channel

    override val length: Long = descriptor.statSize.let { if (it >= 0) it else channel.size() }

    /**
     * The descriptor's path in this process.
     *
     * The one thing a `Uri` cannot give a C library. libarchive wants a path, and
     * `/proc/self/fd/N` is a real one that resolves to the same open file — which
     * is how a compressed CBR from a content provider is decoded without copying it
     * anywhere first.
     *
     * ponytail: valid only while this source is open, which is why it is a property
     * of the source rather than something a caller can hold on to.
     */
    val descriptorPath: String get() = "/proc/self/fd/${descriptor.fd}"

    override suspend fun read(offset: Long, count: Int): ByteArray {
        if (offset < 0 || count < 0) {
            throw SourceOutOfBoundsException(offset, count, length)
        }
        val available = (length - offset).coerceAtLeast(0L)
        val toRead = minOf(count.toLong(), available).toInt()
        if (toRead <= 0) return ByteArray(0)

        val buffer = ByteBuffer.allocate(toRead)
        var position = offset
        // `read(buffer, position)` is positional and does not move the channel's own
        // pointer, so concurrent reads from one source cannot interleave into each
        // other's results. It may still return short, hence the loop.
        while (buffer.hasRemaining()) {
            val got = channel.read(buffer, position)
            if (got <= 0) break
            position += got
        }
        return if (buffer.position() == toRead) {
            buffer.array()
        } else {
            buffer.array().copyOf(buffer.position())
        }
    }

    override fun close() {
        runCatching { channel.close() }
        runCatching { stream.close() }
        runCatching { descriptor.close() }
    }
}
