package app.storyarc.core.format

import java.io.File
import java.io.RandomAccessFile
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Copies a [RandomAccessSource] to a local file in fixed-size chunks.
 *
 * A single `source.read(0, entry.length.toInt())` asks a remote source for the whole file in
 * one message, and every transport this app speaks refuses that past some size -- an SMB read
 * reply is capped by the wire format's own length, and `entry.length.toInt()` itself overflows
 * above 2 GiB before the request is even sent. Holding a multi-hundred-megabyte [ByteArray] in
 * memory to write it back out is its own way to lose to a large publication before either
 * limit is reached. This is the one place any of that happens -- the share browser's download
 * and the offline-copy action both call it rather than each carrying its own one-shot read.
 */
object ChunkedCopy {
    /** 4 MiB. Comfortably under what a server negotiates for a single SMB read. */
    const val DEFAULT_CHUNK_SIZE = 4 shl 20

    /**
     * Copies [source] into [destination], overwriting a stale file already there.
     *
     * Written to a sibling `.partial` file and moved into place only once every chunk has
     * landed, so a reader who looks at [destination] mid-copy -- or a copy the app is killed
     * during -- sees either the previous file or the finished one, never a truncated one
     * under the name the rest of the app already trusts.
     */
    suspend fun copy(
        source: RandomAccessSource,
        destination: File,
        chunkSize: Int = DEFAULT_CHUNK_SIZE,
    ) = withContext(Dispatchers.IO) {
        destination.parentFile?.mkdirs()
        val partial = File(destination.parentFile, "${destination.name}.partial")
        partial.delete()
        try {
            RandomAccessFile(partial, "rw").use { handle ->
                var offset = 0L
                while (offset < source.length) {
                    val count = minOf(chunkSize.toLong(), source.length - offset).toInt()
                    val bytes = source.read(offset, count)
                    // A source that stops short of the length it stated would otherwise land
                    // as a truncated file under the finished name, recorded as a whole download.
                    if (bytes.isEmpty()) throw SourceUnreadableException("short read at $offset")
                    handle.write(bytes)
                    offset += bytes.size
                }
            }
        } catch (error: Throwable) {
            partial.delete()
            throw error
        }
        destination.delete()
        if (!partial.renameTo(destination)) {
            // Cross-filesystem sibling (unusual for a directory this app made itself, but
            // renameTo's own failure mode is silent otherwise): fall back to an explicit copy
            // rather than leaving the finished bytes stranded under the ".partial" name.
            partial.copyTo(destination, overwrite = true)
            partial.delete()
        }
    }
}
