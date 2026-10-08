package app.storyarc.core.model

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update

/**
 * What one session with a network share negotiated.
 *
 * `network-share`'s *Encrypted transport* requires the source detail screen to state whether
 * the connection is encrypted. That sentence must follow a measured value, and the value
 * belongs to a session, not to the app: smbj encrypts a session only when the server agreed
 * SMB 3 with a cipher in common, so two shares can give two answers. ADR-0019.
 *
 * iOS's `ShareTransport` is the mirror of this type.
 */
data class ShareTransport(
    /** The dialect the two ends agreed, such as `SMB 3.1.1`. */
    val dialect: String,
    /** Whether every message of the session is encrypted. */
    val isEncrypted: Boolean,
)

/**
 * Which share a session was with: the host, the port and the share, and nothing else.
 *
 * The session belongs to the server, not to the source row. An add sheet that is still choosing
 * a folder has no source yet, and the library scan and the reader connect from places that never
 * held the source's id. A key every client can build from the address it connects to lets each
 * of them record, and lets the detail screen of any source on that share read the answer. Host
 * and share are compared without regard to case, as SMB does.
 *
 * iOS's `ShareKey` is the mirror of this type.
 */
@JvmInline
value class ShareKey private constructor(private val value: String) {
    companion object {
        fun of(host: String, port: Int, share: String): ShareKey =
            ShareKey("${host.lowercase()}:$port/${share.lowercase()}")

        /**
         * The key of a saved share's locator, `smb://[user@]host[:port]/share[/path]`, or null
         * when the text is not one.
         */
        fun ofLocator(locator: String): ShareKey? {
            if (!locator.startsWith("smb://")) return null
            val body = locator.removePrefix("smb://")
            val slash = body.indexOf('/')
            if (slash < 0) return null
            val share = body.substring(slash + 1).substringBefore('/')
            if (share.isEmpty()) return null
            val hostAndPort = body.substring(0, slash).substringAfterLast('@').split(':')
            val host = hostAndPort.first().takeIf { it.isNotEmpty() } ?: return null
            val port = if (hostAndPort.size > 1) hostAndPort[1].toIntOrNull() ?: return null else DEFAULT_PORT
            return of(host, port, share)
        }

        private const val DEFAULT_PORT = 445
    }
}

/**
 * The last session each network share negotiated, since the app started.
 *
 * Kept in memory only. A transport describes a connection, and a value read from disk is a
 * claim about a connection that no longer exists -- the same argument that keeps a source's
 * connection state off disk. Every client that connects records here, whichever screen it
 * serves, and the source detail screen reads it through [SourceDiagnosis.transport].
 */
object ShareSessions {
    private val negotiated = MutableStateFlow<Map<ShareKey, ShareTransport>>(emptyMap())

    /** Every share's last session. */
    val all: StateFlow<Map<ShareKey, ShareTransport>> = negotiated.asStateFlow()

    /** Records what the newest session with [share] negotiated. */
    fun record(share: ShareKey, transport: ShareTransport) {
        negotiated.update { it + (share to transport) }
    }

    /** Drops what is known of [share], so the next connection is the one that answers. */
    fun forget(share: ShareKey) {
        negotiated.update { it - share }
    }

    /**
     * What the last session with the share a source's [locator] names negotiated, if any. A
     * screen passes the [sessions] it collected, so it redraws when a new session is recorded.
     */
    fun transportOf(locator: String?, sessions: Map<ShareKey, ShareTransport> = all.value): ShareTransport? =
        locator?.let(ShareKey::ofLocator)?.let { sessions[it] }
}
