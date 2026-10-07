package app.storyarc.core.smb

import app.storyarc.core.format.RandomAccessSource
import com.hierynomus.msdtyp.AccessMask
import com.hierynomus.msfscc.fileinformation.FileStandardInformation
import com.hierynomus.mssmb2.SMB2CreateDisposition
import com.hierynomus.mssmb2.SMB2ShareAccess
import com.hierynomus.smbj.share.File
import java.util.EnumSet
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * One open file, read at an offset.
 *
 * The seam [SmbSource] reads through, so its reopen rule does not depend on smbj's types.
 */
internal interface SmbHandle : AutoCloseable {
    val length: Long

    /** Fills [buffer] from [offset], or throws when the file ends before it is full. */
    fun readFully(offset: Long, buffer: ByteArray)
}

/** A file on a share, with the connection that serves it and nothing else. */
internal class SmbFileHandle private constructor(
    private val tree: SmbTree,
    private val file: File,
) : SmbHandle {

    override val length: Long =
        file.getFileInformation(FileStandardInformation::class.java).endOfFile

    override fun readFully(offset: Long, buffer: ByteArray) {
        var filled = 0
        while (filled < buffer.size) {
            val read = file.read(buffer, offset + filled, filled, buffer.size - filled)
            if (read <= 0) throw java.io.EOFException("the file ended at ${offset + filled}")
            filled += read
        }
    }

    override fun close() {
        runCatching { file.close() }
        tree.close()
    }

    companion object {
        fun open(address: SmbAddress, path: String): SmbFileHandle {
            val tree = SmbTree.open(address)
            try {
                val file = tree.share.openFile(
                    path.trim('/').replace('/', '\\'),
                    EnumSet.of(AccessMask.GENERIC_READ),
                    null,
                    EnumSet.of(SMB2ShareAccess.FILE_SHARE_READ),
                    SMB2CreateDisposition.FILE_OPEN,
                    null,
                )
                return SmbFileHandle(tree, file)
            } catch (error: Throwable) {
                tree.close()
                throw error
            }
        }
    }
}

/**
 * A file on a share, read at an offset.
 *
 * The third implementation ADR-0008 planned for. SMB2's `READ` takes an offset and a length
 * as a first-class operation, so this is the interface it was already shaped like.
 */
internal class SmbSource(private val opener: () -> SmbHandle) : RandomAccessSource {
    private var handle: SmbHandle = opener()

    /**
     * How many times [opener] has produced a handle for this source: once at construction,
     * once more per [reopen]. Internal, for a test to tell "read from the session that was
     * already open" apart from "read from a fresh one" -- the two are indistinguishable from
     * the bytes alone when the file has not changed underneath, which is every case a unit
     * test can set up.
     */
    internal var opens = 1
        private set

    /**
     * Set by a network-path change ([dropHandle]), and acted on at the top of the next
     * [read]. The reopen is unconditional rather than a hope that the old handle fails loudly
     * enough to be noticed.
     */
    @Volatile
    private var invalidated = false

    override val length: Long = handle.length

    /**
     * Reads, opening a new session first if a network change invalidated the old one, and
     * once more if the old one has otherwise gone.
     *
     * `network-share` requires the app to "re-establish the session transparently on the
     * next read" after the device sleeps, and to reconnect in the background when the
     * connection drops. Both are the same act from here: the handle is stale, so make
     * another and ask again. Once, not in a loop -- a share that is genuinely gone should
     * say so rather than hang.
     */
    override suspend fun read(offset: Long, count: Int): ByteArray =
        withContext(Dispatchers.IO) {
            val available = (length - offset).coerceAtLeast(0L)
            val toRead = minOf(count.toLong(), available).toInt()
            if (toRead <= 0) return@withContext ByteArray(0)

            if (invalidated) {
                synchronized(this@SmbSource) {
                    if (invalidated) {
                        // A new path that cannot reach the share is the same answer as a
                        // reopen that failed below: the share is gone, said as such.
                        try {
                            reopen()
                        } catch (gone: Exception) {
                            throw SmbError.HostUnreachable
                        }
                        invalidated = false
                    }
                }
            }

            try {
                readOnce(offset, toRead)
            } catch (first: Exception) {
                try {
                    reopen()
                    readOnce(offset, toRead)
                } catch (second: Exception) {
                    throw SmbError.HostUnreachable
                }
            }
        }

    private fun readOnce(offset: Long, count: Int): ByteArray {
        val buffer = ByteArray(count)
        synchronized(this) { handle.readFully(offset, buffer) }
        return buffer
    }

    private fun reopen() {
        synchronized(this) {
            runCatching { handle.close() }
            handle = opener()
            opens++
        }
    }

    /**
     * Marks the handle invalid, so the next [read] reopens unconditionally. Does not reopen
     * here itself: [dropHandle] is called from a network callback, off no particular
     * dispatcher, and opening a session is I/O nothing should pay for a source that may never
     * be read from again.
     */
    internal fun dropHandle() {
        invalidated = true
    }

    override fun close() {
        runCatching { handle.close() }
    }
}

/**
 * Every [SmbSource] currently open, so a network-path change can drop them at once rather
 * than each one waiting to find out from a read that times out against it.
 *
 * `network-share`'s *Network changes*: [SmbNetworkWatch] is the platform half that decides
 * when a change happened; this is the held-weakly half that acts on it.
 *
 * A [java.util.WeakHashMap]-backed set, not a plain list: a source this app has stopped
 * reading drops out of the app's memory, and should not stay reachable from here only
 * because nobody remembered to unregister it.
 */
object SmbSourceRegistry {
    private val sources = java.util.Collections.newSetFromMap(
        java.util.WeakHashMap<SmbSource, Boolean>(),
    )

    @Synchronized
    internal fun register(source: SmbSource) {
        sources.add(source)
    }

    /** Drops every open session's handle. See [SmbSource.dropHandle]. */
    @Synchronized
    fun dropAll() {
        sources.forEach { it.dropHandle() }
    }
}
