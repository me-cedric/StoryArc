package app.storyarc.core.smb

import app.storyarc.core.format.RandomAccessSource
import app.storyarc.core.model.ShareKey
import app.storyarc.core.model.ShareSessions
import com.hierynomus.mserref.NtStatus
import com.hierynomus.mssmb.SMB1NotSupportedException
import com.hierynomus.mssmb2.SMB2Dialect
import com.hierynomus.mssmb2.SMBApiException
import com.hierynomus.smbj.SMBClient
import com.hierynomus.smbj.SmbConfig
import com.hierynomus.smbj.auth.AuthenticationContext
import com.hierynomus.smbj.connection.Connection
import com.hierynomus.smbj.session.Session
import com.hierynomus.smbj.share.DiskShare
import java.net.URI
import java.net.URISyntaxException
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * A share, as StoryArc talks to it.
 *
 * Thin on purpose: everything above this line -- the ZIP reader, the page decoder, the
 * reader -- works against [RandomAccessSource] and learns nothing about SMB. ADR-0010 keeps
 * the client behind this seam so that the choice of library stays a detail. ADR-0019 swapped
 * the library under it, from jcifs-ng to smbj, for SMB 3 encryption.
 */
class SmbClient(private val address: SmbAddress) : AutoCloseable {

    internal companion object {
        /**
         * How this client is configured, before any credentials are attached.
         *
         * Its own function so a test can read it back: what it holds is a set of decisions
         * that are invisible at every other layer.
         *
         * - SMB 1 is never offered. `network-share` requires the app to refuse it rather than
         *   fall back to it, and smbj sends no SMB 1 negotiate unless asked to.
         * - Signing is enabled and not required. smbj signs every request of a session that
         *   has a key and checks the signature of every response. Not required, because
         *   `network-share` requires a guest share to work, and a guest session is unsigned.
         * - Encryption is offered. smbj's `encryptData` advertises the capability and the
         *   ciphers, and then encrypts every message of a session that agreed SMB 3 with a
         *   cipher in common. It demands nothing: an SMB 2 server, or a guest session with no
         *   key, still connects, unencrypted, and says so.
         */
        internal fun clientConfig(): SmbConfig = SmbConfig.builder()
            .withDialects(
                SMB2Dialect.SMB_3_1_1,
                SMB2Dialect.SMB_3_0_2,
                SMB2Dialect.SMB_3_0,
                SMB2Dialect.SMB_2_1,
                SMB2Dialect.SMB_2_0_2,
            )
            .withMultiProtocolNegotiate(false)
            .withSigningEnabled(true)
            .withSigningRequired(false)
            .withEncryptData(true)
            .withTimeout(RESPONSE_TIMEOUT_SECONDS, TimeUnit.SECONDS)
            .withSoTimeout(RESPONSE_TIMEOUT_SECONDS, TimeUnit.SECONDS)
            .build()

        /** How a dialect is written in the sheet and on the detail screen. */
        internal fun nameOf(dialect: SMB2Dialect): String = when (dialect) {
            SMB2Dialect.SMB_2_0_2 -> "SMB 2.0.2"
            SMB2Dialect.SMB_2_1 -> "SMB 2.1"
            SMB2Dialect.SMB_3_0 -> "SMB 3.0"
            SMB2Dialect.SMB_3_0_2 -> "SMB 3.0.2"
            SMB2Dialect.SMB_3_1_1 -> "SMB 3.1.1"
            else -> "SMB 2"
        }

        private const val RESPONSE_TIMEOUT_SECONDS = 20L
    }

    /** One connection, one session and one tree, made on first use and kept until [close]. */
    private var tree: SmbTree? = null

    /**
     * Connects, and reports what the far end turned out to be.
     *
     * `network-share` wants the connection validated "before saving", with the specific
     * failure named. Reaching the share's root is the cheapest thing that exercises all four.
     */
    suspend fun connect(): SmbIdentity = withContext(Dispatchers.IO) {
        translating {
            val open = tree()
            val inside = address.path.trim('/')
            if (inside.isNotEmpty() && !open.share.folderExists(inside)) throw SmbError.ShareNotFound
            open.identity()
        }
    }

    /** What is in one folder of the share, folders first, in natural order. */
    suspend fun list(path: String = address.path): List<SmbEntry> = withContext(Dispatchers.IO) {
        translating {
            val inside = path.trim('/')
            tree().share.list(inside.replace('/', '\\'))
                .filter { it.fileName != "." && it.fileName != ".." }
                .map { each ->
                    val isDirectory = each.fileAttributes and FILE_ATTRIBUTE_DIRECTORY != 0L
                    SmbEntry(
                        name = each.fileName,
                        path = listOf(inside, each.fileName)
                            .filter { it.isNotEmpty() }
                            .joinToString("/"),
                        isDirectory = isDirectory,
                        length = if (isDirectory) 0L else each.endOfFile,
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
        // restarting, and `network-share` asks for all three to be invisible. Each handle
        // owns its own connection, so a reopen never reuses a connection a dead path left.
        translating {
            SmbSource { SmbFileHandle.open(address, path) }.also(SmbSourceRegistry::register)
        }
    }

    /** Closes only what was opened: an unused client never made a connection to close. */
    override fun close() {
        tree?.close()
        tree = null
    }

    private fun tree(): SmbTree = tree?.takeIf { it.isConnected } ?: SmbTree.open(address).also {
        tree?.close()
        tree = it
    }

    /**
     * Turns what smbj threw into the failures the spec names.
     *
     * A reader who typed the wrong password and a reader whose NAS is asleep need different
     * sentences, and one exception type does not tell them apart.
     */
    private inline fun <T> translating(body: () -> T): T = try {
        body()
    } catch (error: SmbError) {
        throw error
    } catch (error: Exception) {
        throw translate(error)
    }
}

/** `FILE_ATTRIBUTE_DIRECTORY`, from MS-FSCC 2.6. */
private const val FILE_ATTRIBUTE_DIRECTORY = 0x10L

/**
 * One connection, one authenticated session and one connected share.
 *
 * Kept together because none of the three is useful alone, and closing the connection is
 * what releases the other two.
 */
internal class SmbTree private constructor(
    private val client: SMBClient,
    private val connection: Connection,
    private val session: Session,
    val share: DiskShare,
) : AutoCloseable {

    val isConnected: Boolean get() = connection.isConnected

    /**
     * What this session negotiated, read off the session itself.
     *
     * The dialect is the one the two ends agreed. "Encrypted" is smbj's own decision for every
     * message it sends on this session, so it is the fact rather than a claim about it.
     * "Signed" is true for an encrypted session too: SMB 3 encryption authenticates every
     * message, and it replaces the signature.
     */
    fun identity(): SmbIdentity {
        val isEncrypted = session.shouldEncryptData()
        return SmbIdentity(
            dialect = SmbClient.nameOf(connection.negotiatedProtocol.dialect),
            isEncrypted = isEncrypted,
            isSigned = isEncrypted || (!session.isGuest && !session.isAnonymous),
        )
    }

    override fun close() {
        runCatching { share.close() }
        runCatching { session.close() }
        runCatching { connection.close() }
        runCatching { client.close() }
    }

    companion object {
        fun open(address: SmbAddress): SmbTree {
            validate(address)
            val client = SMBClient(SmbClient.clientConfig())
            try {
                val connection = client.connect(address.host, address.port)
                val session = connection.authenticate(credentials(address))
                val share = session.connectShare(address.share) as? DiskShare
                    ?: throw SmbError.ShareNotFound
                return SmbTree(client, connection, session, share).also {
                    // Kept here, in the one place every client connects through, so that the add
                    // sheet, the library scan, the reader and the health probe all leave the same
                    // record.
                    ShareSessions.record(
                        ShareKey.of(address.host, address.port, address.share),
                        it.identity().transport,
                    )
                }
            } catch (error: Throwable) {
                client.close()
                throw error
            }
        }

        private fun credentials(address: SmbAddress): AuthenticationContext =
            if (address.isGuest) {
                AuthenticationContext.guest()
            } else {
                AuthenticationContext(address.username, address.password.orEmpty().toCharArray(), "")
            }

        /** A host no URL can carry is a typing mistake, and it is named as one. */
        private fun validate(address: SmbAddress) {
            try {
                URI(address.url("")).host ?: throw SmbError.AddressInvalid
            } catch (error: URISyntaxException) {
                throw SmbError.AddressInvalid
            }
        }
    }
}

/**
 * Reads what smbj threw, for the failures `network-share` names.
 *
 * An NT status says the most, so it is read first. A failure before the server answered has
 * no status, so the cause chain is read next, and the message last.
 */
internal fun translate(error: Throwable): SmbError {
    findStatus(error)?.let { status -> meaning(status)?.let { return it } }
    return fromCauseChain(error) ?: fromMessage(error.message.orEmpty(), fallback = SmbError.HostUnreachable)
}

private fun findStatus(error: Throwable): Long? {
    var current: Throwable? = error
    var steps = 0
    while (current != null && steps < CAUSE_CHAIN_LIMIT) {
        if (current is SMBApiException) return current.statusCode
        current = current.cause.takeUnless { it === current }
        steps++
    }
    return null
}

/**
 * The NT statuses this app has a sentence for, or null for one it has not.
 *
 * Read as numbers: smbj's enum has no member for `STATUS_WRONG_PASSWORD`, and a status the
 * enum does not know would otherwise be read as no status at all.
 */
internal fun meaning(status: Long): SmbError? = when (status) {
    NtStatus.STATUS_LOGON_FAILURE.value,
    STATUS_WRONG_PASSWORD,
    NtStatus.STATUS_ACCESS_DENIED.value,
    -> SmbError.AuthenticationRejected
    NtStatus.STATUS_BAD_NETWORK_NAME.value,
    NtStatus.STATUS_OBJECT_PATH_NOT_FOUND.value,
    -> SmbError.ShareNotFound
    else -> null
}

/** `STATUS_WRONG_PASSWORD`, from MS-ERREF 2.3.1. */
private const val STATUS_WRONG_PASSWORD = 0xC000006AL

/**
 * smbj wraps a connect failure in its own exception, so the useful answer -- a host that
 * never answered, or a server that speaks only SMB 1 -- is in the cause chain rather than on
 * the exception the app catches.
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
            is SMB1NotSupportedException -> return SmbError.ProtocolUnsupported
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
 * What the client said, read for the two refusals it only expresses in prose.
 *
 * Neither carries an NT status: a dialect mismatch and a demand for encryption the session
 * cannot meet both fail before the server answers with one.
 */
internal fun fromMessage(
    message: String,
    fallback: SmbError = SmbError.Unexpected(message.ifEmpty { "unsuccessful" }),
): SmbError = when {
    message.contains("requires encryption", ignoreCase = true) -> SmbError.EncryptionRequired
    message.contains("encryption is required", ignoreCase = true) -> SmbError.EncryptionRequired
    message.contains("dialect", ignoreCase = true) -> SmbError.ProtocolUnsupported
    else -> fallback
}
