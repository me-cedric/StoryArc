package app.storyarc.core.smb

import app.storyarc.core.format.RandomAccessSource
import app.storyarc.core.model.ShareTransport
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
import jcifs.smb.SmbTreeHandleInternal
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

    internal companion object {
        const val SMB2_OR_LATER = "SMB 2 or later"
        const val SMB1 = "SMB 1"

        /**
         * How this client is configured, before any credentials are attached.
         *
         * Its own function so a test can read it back: what it holds is a set of decisions
         * that are invisible at every other layer, and the one that was missing --
         * `signingPreferred` -- cost nothing to leave out and could only be noticed by
         * asking a server.
         */
        internal fun clientProperties(): Properties {
            val properties = Properties()
            // SMB 1 is off at both ends. `network-share` requires the app to refuse it
            // rather than fall back to it, and a client that can still speak it would
            // refuse only by accident.
            properties["jcifs.smb.client.minVersion"] = "SMB202"
            properties["jcifs.smb.client.maxVersion"] = "SMB311"
            properties["jcifs.smb.client.encryptionEnabled"] = "true"
            // Sign wherever the server can, rather than only where it insists. jcifs signs
            // on demand by default, and a consumer NAS that merely *supports* signing --
            // the common default -- demands nothing, so the session was unsigned and an
            // attacker on the LAN could rewrite a directory listing or a read into the
            // format layer. Preferred, not enforced: `network-share` requires a guest share
            // to work, and a guest session is unsigned by definition.
            properties["jcifs.smb.client.signingPreferred"] = "true"
            properties["jcifs.smb.client.responseTimeout"] = "20000"
            properties["jcifs.smb.client.connTimeout"] = "10000"
            return properties
        }
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
        translating {
            val root = file(address.path)
            if (!root.exists()) throw SmbError.ShareNotFound
            // What the connection actually did, not what the client was configured to
            // allow. jcifs' public API says only whether the tree is SMB 2 or later --
            // the exact dialect lives on an internal handle -- so that is what is
            // reported. Claiming "SMB 3.1.1" from the configured maximum would be a
            // sentence about this app rather than about this server.
            root.treeHandle.use { handle ->
                SmbIdentity(
                    dialect = if (handle.isSMB2) SMB2_OR_LATER else SMB1,
                    // [ShareTransport] holds the answer and the evidence for it, so that
                    // the add-share sheet and the source detail screen read one value.
                    //
                    // The earlier comment here said that this client does not ask jcifs to
                    // encrypt. That was wrong: `clientProperties()` sets
                    // `encryptionEnabled` to true. Asking is not getting -- jcifs-ng 2.1.10
                    // carries the negotiate context and no cipher, and advertising the
                    // capability is what lets it name the refusal when a server demands
                    // encryption. ADR-0010 records that decision.
                    isEncrypted = ShareTransport.IS_ENCRYPTED,
                    // What the session negotiated, not what was asked for. The client now
                    // prefers signing on every session, but a guest share cannot sign, so
                    // the answer still has to come from the handle. `areSignaturesActive`
                    // is on jcifs' internal tree-handle interface -- public, but not on
                    // `SmbTreeHandle` -- so a handle that is not one answers "no" rather
                    // than claiming a guarantee nothing checked.
                    isSigned = (handle as? SmbTreeHandleInternal)?.areSignaturesActive() == true,
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
        // The opener rather than the handle, so the source can make a new one. A session
        // does not survive the device sleeping, the Wi-Fi changing, or the server
        // restarting, and `network-share` asks for all three to be invisible.
        translating {
            SmbSource { SmbRandomAccessFile(file(path), "r") }.also(SmbSourceRegistry::register)
        }
    }

    /** Closes only what was opened: an unused client never built a context to close. */
    override fun close() {
        if (lazyContext.isInitialized()) context.close()
    }

    private fun file(path: String) = SmbFile(address.url(path), context)

    private fun base(): CIFSContext = BaseContext(PropertyConfiguration(clientProperties()))

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
    } catch (error: java.net.MalformedURLException) {
        throw SmbError.AddressInvalid
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
                fromCauseChain(error) ?: fromMessage(error.message.orEmpty())
            else -> fromCauseChain(error) ?: SmbError.HostUnreachable
        }
    } catch (error: java.io.IOException) {
        throw fromCauseChain(error)
            ?: fromMessage(error.message.orEmpty(), fallback = SmbError.HostUnreachable)
    }
}

/**
 * jcifs wraps every connect failure in `SmbException`, so the useful answer -- a host that
 * never answered, or a server with no dialect in common -- is buried in the cause chain
 * rather than on the exception the app catches. `error.message` alone cannot tell "the host
 * refused the connection" from "the host does not speak SMB2", because both surface as the
 * same generic wrapper text; only a cause further down says which.
 */
internal fun fromCauseChain(error: Throwable): SmbError? {
    var current: Throwable? = error
    var steps = 0
    while (current != null && steps < CAUSE_CHAIN_LIMIT) {
        when (current) {
            is java.net.UnknownHostException,
            is java.net.ConnectException,
            is java.net.NoRouteToHostException,
            is java.net.SocketTimeoutException,
            -> return SmbError.HostUnreachable
        }
        val message = current.message.orEmpty()
        if (PROTOCOL_REFUSAL_PHRASES.any { message.contains(it, ignoreCase = true) }) {
            return SmbError.ProtocolUnsupported
        }
        val next = current.cause
        current = next.takeUnless { it === current }
        steps++
    }
    return null
}

private const val CAUSE_CHAIN_LIMIT = 20
private val PROTOCOL_REFUSAL_PHRASES = listOf("does not support SMB2", "not compatible", "dialect")

/**
 * What jcifs said, read for the two refusals it only expresses in prose.
 *
 * Neither carries an NT status: a dialect mismatch and a demand for encryption both fail
 * before the server ever answers with one.
 */
internal fun fromMessage(
    message: String,
    fallback: SmbError = SmbError.Unexpected(message.ifEmpty { "unsuccessful" }),
): SmbError = when {
    message.contains("requires encryption", ignoreCase = true) -> SmbError.EncryptionRequired
    message.contains("dialect", ignoreCase = true) -> SmbError.ProtocolUnsupported
    else -> fallback
}

/**
 * A file on a share, read at an offset.
 *
 * The third implementation ADR-0008 planned for. SMB2's `READ` takes an offset and a length
 * as a first-class operation, so this is the interface it was already shaped like.
 */
internal class SmbSource(private val opener: () -> SmbRandomAccessFile) : RandomAccessSource {
    private var handle: SmbRandomAccessFile = opener()

    /**
     * How many times [opener] has produced a handle for this source: once at construction,
     * once more per [reopen]. Internal, for a test to tell "read from the session that was
     * already open" apart from "read from a fresh one" — the two are indistinguishable from
     * the bytes alone when the file has not changed underneath, which is every case a unit
     * test can set up.
     */
    internal var opens = 1
        private set

    /**
     * Set by a network-path change ([dropHandle]), and acted on at the top of the next
     * [read]. Closing [handle] and waiting for `readFully` to throw is not enough on its own:
     * jcifs's own file handle can reopen its transport quietly on the very same object, so a
     * read that merely follows a `close()` can carry on over whatever the path change already
     * left behind instead of the fresh session [opener] builds. This flag makes the reopen
     * unconditional rather than hoping the old handle fails loudly enough to be noticed —
     * measured against the fixture server, where it does not.
     */
    @Volatile
    private var invalidated = false

    override val length: Long = handle.length()

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
                        } catch (gone: java.io.IOException) {
                            throw SmbError.HostUnreachable
                        }
                        invalidated = false
                    }
                }
            }

            try {
                readOnce(offset, toRead)
            } catch (first: java.io.IOException) {
                try {
                    reopen()
                    readOnce(offset, toRead)
                } catch (second: java.io.IOException) {
                    throw SmbError.HostUnreachable
                }
            }
        }

    private fun readOnce(offset: Long, count: Int): ByteArray {
        val buffer = ByteArray(count)
        synchronized(this) {
            handle.seek(offset)
            handle.readFully(buffer)
        }
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
     * Marks the handle invalid, so the next [read] reopens unconditionally rather than
     * risking jcifs's own quiet reconnect on the object a dead path already left behind. Does
     * not reopen here itself: [dropHandle] is called from a network callback, off no
     * particular dispatcher, and opening a session is I/O nothing should pay for a source
     * that may never be read from again.
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
 * `network-share`'s *Network changes*: nothing used to watch for one at all — a stale session
 * was dropped only after a read against it failed, which on Android waits out
 * `responseTimeout` (20 s) and then `connTimeout` (10 s) before the retry even starts.
 * [SmbNetworkWatch] is the platform half that decides when a change happened; this is the
 * held-weakly half that acts on it, kept apart for the reason [SourceReachability] keeps
 * deciding apart from observing: a device and a real network are what the watching needs, and
 * a test needs neither for this.
 *
 * A [java.util.WeakHashMap]-backed set, not a plain list: a source this app has stopped
 * reading closes on its own path and drops out of the app's memory, and should not stay
 * reachable from here only because nobody remembered to unregister it.
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
