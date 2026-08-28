package app.storyarc.core.smb

import app.storyarc.core.format.RandomAccessSource
import java.util.Properties
import jcifs.CIFSContext
import jcifs.config.PropertyConfiguration
import jcifs.context.BaseContext
import jcifs.smb.NtStatus
import jcifs.smb.NtlmPasswordAuthenticator
import jcifs.smb.SmbAuthException
import jcifs.smb.SmbException
import jcifs.smb.SmbFile
import jcifs.smb.SmbRandomAccessFile
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * A share, as StoryArc talks to it.
 *
 * Thin on purpose: everything above this line -- the ZIP reader, the page decoder, the
 * reader -- works against [RandomAccessSource] and learns nothing about SMB. ADR-0010 keeps
 * the client behind this seam so that the choice of library stays a detail.
 */
class SmbClient(private val address: SmbAddress) : AutoCloseable {

    private companion object {
        const val SMB2_OR_LATER = "SMB 2 or later"
        const val SMB1 = "SMB 1"
    }


    /**
     * Built on first use, not on construction.
     *
     * jcifs' `BaseContext` sets up name resolution while it is created, which blocks. Doing
     * that from a composable's `remember` froze the main thread long enough for Android to
     * call it an ANR.
     */
    private val lazyContext = lazy { buildContext() }
    private val context: CIFSContext get() = lazyContext.value

    private fun buildContext(): CIFSContext {
        val root = base()
        return if (address.isGuest) {
            // jcifs-ng spells its own method this way. Kept verbatim rather than wrapped,
            // because a wrapper would only hide where the typo lives.
            @Suppress("SpellCheckingInspection")
            root.withGuestCrendentials()
        } else {
            root.withCredentials(
                NtlmPasswordAuthenticator("", address.username, address.password),
            )
        }
    }

    /**
     * Connects, and reports what the far end turned out to be.
     *
     * `network-share` wants the connection validated "before saving", with the specific
     * failure named. Listing the root is the cheapest thing that exercises all four.
     */
    suspend fun connect(): SmbIdentity = withContext(Dispatchers.IO) {
        val root = file(address.path)
        translating {
            if (!root.exists()) throw SmbError.ShareNotFound
            // What the connection actually did, not what the client was configured to
            // allow. jcifs' public API says only whether the tree is SMB 2 or later --
            // the exact dialect lives on an internal handle -- so that is what is
            // reported. Claiming "SMB 3.1.1" from the configured maximum would be a
            // sentence about this app rather than about this server.
            root.treeHandle.use { handle ->
                SmbIdentity(
                    dialect = if (handle.isSMB2) SMB2_OR_LATER else SMB1,
                    // False until a connection can prove otherwise. jcifs encrypts only
                    // when told to, this client does not tell it to, and a screen that
                    // claimed encryption the transport does not have would be worse than
                    // one that admits it.
                    isEncrypted = false,
                )
            }
        }
    }

    /** What is in one folder of the share, folders first, in natural order. */
    suspend fun list(path: String = address.path): List<SmbEntry> = withContext(Dispatchers.IO) {
        translating {
            file(path).listFiles().orEmpty()
                .map { each ->
                    val name = each.name.trimEnd('/')
                    SmbEntry(
                        name = name,
                        path = listOf(path.trim('/'), name)
                            .filter { it.isNotEmpty() }
                            .joinToString("/"),
                        isDirectory = each.isDirectory,
                        length = if (each.isDirectory) 0L else each.length(),
                    )
                }
                .sortedWith(compareByDescending<SmbEntry> { it.isDirectory }.thenBy { it.name })
        }
    }

    /**
     * One file on the share, read where the reader needs it rather than whole.
     *
     * Suspending, and on IO: opening a handle is a round trip to the server, and doing that
     * on the caller's thread threw `NetworkOnMainThreadException` into a `runCatching` that
     * swallowed it -- a tap that did nothing at all.
     */
    suspend fun open(path: String): RandomAccessSource = withContext(Dispatchers.IO) {
        translating { SmbSource(file(path)) }
    }

    /** Closes only what was opened: an unused client never built a context to close. */
    override fun close() {
        if (lazyContext.isInitialized()) context.close()
    }

    private fun file(path: String) = SmbFile(address.url(path), context)

    private fun base(): CIFSContext {
        val properties = Properties()
        // SMB 1 is off at both ends. `network-share` requires the app to refuse it rather
        // than fall back to it, and a client that can still speak it would refuse only by
        // accident.
        properties["jcifs.smb.client.minVersion"] = "SMB202"
        properties["jcifs.smb.client.maxVersion"] = "SMB311"
        properties["jcifs.smb.client.responseTimeout"] = "20000"
        properties["jcifs.smb.client.connTimeout"] = "10000"
        return BaseContext(PropertyConfiguration(properties))
    }

    /**
     * Turns jcifs' one exception type into the four failures the spec names.
     *
     * A reader who typed the wrong password and a reader whose NAS is asleep need different
     * sentences, and `SmbException` alone does not tell them apart.
     */
    private inline fun <T> translating(body: () -> T): T = try {
        body()
    } catch (error: SmbError) {
        throw error
    } catch (error: SmbAuthException) {
        throw SmbError.AuthenticationRejected
    } catch (error: SmbException) {
        throw when (error.ntStatus) {
            NtStatus.NT_STATUS_LOGON_FAILURE,
            NtStatus.NT_STATUS_ACCESS_DENIED,
            -> SmbError.AuthenticationRejected
            NtStatus.NT_STATUS_BAD_NETWORK_NAME,
            NtStatus.NT_STATUS_OBJECT_PATH_NOT_FOUND,
            -> SmbError.ShareNotFound
            NtStatus.NT_STATUS_UNSUCCESSFUL ->
                if (error.message.orEmpty().contains("dialect", ignoreCase = true)) {
                    SmbError.ProtocolUnsupported
                } else {
                    SmbError.Unexpected(error.message ?: "unsuccessful")
                }
            else -> SmbError.HostUnreachable
        }
    } catch (error: java.io.IOException) {
        throw SmbError.HostUnreachable
    }
}

/**
 * A file on a share, read at an offset.
 *
 * The third implementation ADR-0008 planned for. SMB2's `READ` takes an offset and a length
 * as a first-class operation, so this is the interface it was already shaped like.
 */
private class SmbSource(private val file: SmbFile) : RandomAccessSource {
    private val handle: SmbRandomAccessFile = SmbRandomAccessFile(file, "r")

    override val length: Long = handle.length()

    override suspend fun read(offset: Long, count: Int): ByteArray =
        withContext(Dispatchers.IO) {
            val available = (length - offset).coerceAtLeast(0L)
            val toRead = minOf(count.toLong(), available).toInt()
            if (toRead <= 0) return@withContext ByteArray(0)
            val buffer = ByteArray(toRead)
            synchronized(handle) {
                handle.seek(offset)
                handle.readFully(buffer)
            }
            buffer
        }

    override fun close() {
        handle.close()
        file.close()
    }
}
