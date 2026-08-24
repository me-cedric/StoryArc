package app.storyarc.core.model

import java.util.UUID

/** Where publications come from. See `docs/openspec/specs/sources`. */
enum class SourceKind { LOCAL_FOLDER, NETWORK_SHARE, OPDS_CATALOG, KAVITA_SERVER }

/**
 * `sources` requires exactly these four states, and requires that none of them
 * prevents browsing what is already cached.
 */
sealed interface SourceConnectionState {
    data object Connected : SourceConnectionState
    data object Connecting : SourceConnectionState
    data class Unreachable(val sinceEpochMillis: Long) : SourceConnectionState
    data class Unauthorized(val reason: String) : SourceConnectionState

    /** Whether the source can serve content that is not already downloaded. */
    val canFetch: Boolean get() = this is Connected

    /**
     * Offline is a normal state, not a failure — only [Unauthorized] is
     * something the user has to act on.
     */
    val needsUserAction: Boolean get() = this is Unauthorized
}

data class Source(
    val id: UUID = UUID.randomUUID(),
    val displayName: String,
    val kind: SourceKind,
    val state: SourceConnectionState = SourceConnectionState.Connecting,
    val lastSuccessfulSyncEpochMillis: Long? = null,
    /**
     * Opaque handle into the platform secure store. Never the secret itself —
     * `sources` forbids a secret reaching preferences, logs or backups.
     */
    val credentialReference: String? = null,
)

/** Exponential backoff for an unreachable source: start at 5 s, cap at 5 min. */
object ReconnectBackoff {
    const val INITIAL_DELAY_MILLIS = 5_000L
    const val MAXIMUM_DELAY_MILLIS = 300_000L

    fun delayMillis(attempt: Int): Long {
        if (attempt <= 0) return INITIAL_DELAY_MILLIS
        val doubled = INITIAL_DELAY_MILLIS.toDouble() * Math.pow(2.0, (attempt - 1).toDouble())
        return minOf(doubled, MAXIMUM_DELAY_MILLIS.toDouble()).toLong()
    }
}
