package app.storyarc.core.format

import android.os.Handler
import android.os.HandlerThread
import android.os.ParcelFileDescriptor
import android.os.ProxyFileDescriptorCallback
import android.os.storage.StorageManager
import android.system.ErrnoException
import android.system.OsConstants
import kotlinx.coroutines.runBlocking

/**
 * A read-only file descriptor whose bytes come from a ranged source.
 *
 * `PdfRenderer` takes a descriptor and nothing else. A PDF on a share has no descriptor, so
 * `StorageManager.openProxyFileDescriptor` makes one: the kernel calls [SourceCallback] for
 * each range the renderer reads, and only those ranges cross the network
 * (`publication-formats`, *Streaming capability per format*: a PDF streams on Android).
 *
 * The callback is synchronous and the source suspends, so each read blocks on the source on
 * the callback's own handler thread. That thread exists for this descriptor alone, and it
 * ends when the descriptor is released.
 */
internal object SourceDescriptor {

    fun open(storage: StorageManager, source: RandomAccessSource): ParcelFileDescriptor {
        val thread = HandlerThread("storyarc-source-descriptor").apply { start() }
        return try {
            storage.openProxyFileDescriptor(
                ParcelFileDescriptor.MODE_READ_ONLY,
                SourceCallback(source) { thread.quitSafely() },
                Handler(thread.looper),
            )
        } catch (cause: Exception) {
            thread.quitSafely()
            source.close()
            throw PdfException.Unreadable(cause.message ?: "cannot open a descriptor over the source")
        }
    }
}

/** Answers the kernel's reads from [source], and lets go of it on release. */
internal class SourceCallback(
    private val source: RandomAccessSource,
    private val onReleased: () -> Unit,
) : ProxyFileDescriptorCallback() {

    override fun onGetSize(): Long = source.length

    override fun onRead(offset: Long, size: Int, data: ByteArray): Int =
        try {
            runBlocking { readInto(source, offset, size, data) }
        } catch (cause: Exception) {
            throw ErrnoException("onRead", OsConstants.EIO).apply { initCause(cause) }
        }

    override fun onRelease() {
        source.close()
        onReleased()
    }
}

/**
 * Copies up to [size] bytes at [offset] from [source] into [data], and returns how many.
 *
 * Zero at or past the end, which is how a descriptor reports the end of a file. Never more
 * than [data] holds, whatever the kernel asked for.
 */
internal suspend fun readInto(source: RandomAccessSource, offset: Long, size: Int, data: ByteArray): Int {
    if (offset < 0) throw SourceOutOfBoundsException(offset, size, source.length)
    val wanted = minOf(size.toLong(), data.size.toLong(), source.length - offset)
    if (wanted <= 0) return 0
    val bytes = source.read(offset, wanted.toInt())
    val count = minOf(bytes.size, wanted.toInt())
    bytes.copyInto(data, 0, 0, count)
    return count
}
