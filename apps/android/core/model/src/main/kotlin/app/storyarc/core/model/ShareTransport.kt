package app.storyarc.core.model

import java.util.UUID
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
 * SMB 3 with a cipher in common, so two shares can give two answers. ADR-0018.
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
 * The last session each network-share source negotiated, since the app started.
 *
 * Kept in memory only. A transport describes a connection, and a value read from disk is a
 * claim about a connection that no longer exists -- the same argument that keeps a source's
 * connection state off disk. Every connection that knows its source records here, and the
 * source detail screen reads it through [SourceDiagnosis.transport].
 */
object ShareSessions {
    private val negotiated = MutableStateFlow<Map<UUID, ShareTransport>>(emptyMap())

    /** Every source's last session, keyed by the source's id. */
    val all: StateFlow<Map<UUID, ShareTransport>> = negotiated.asStateFlow()

    /** Records what the newest session with [sourceId] negotiated. */
    fun record(sourceId: UUID, transport: ShareTransport) {
        negotiated.update { it + (sourceId to transport) }
    }
}
