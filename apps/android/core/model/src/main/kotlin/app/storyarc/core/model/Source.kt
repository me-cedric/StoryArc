package app.storyarc.core.model

import java.util.UUID

/** Where publications come from. See `docs/openspec/specs/sources`. */
enum class SourceKind {
    LOCAL_FOLDER,
    NETWORK_SHARE,
    OPDS_CATALOG,
    KAVITA_SERVER,
    ;

    /**
     * Whether this is a place a reader travels *to*, rather than a shelf already folded
     * into the library.
     *
     * A local folder's publications are scanned and land in the grid, so a way in to it
     * would lead back to where the reader already is. The other three hold content that
     * is not on the device and each needs its own browser.
     *
     * One property rather than the same three-way comparison in the catalogue strip, the
     * navigation rail and iOS's screen: three copies is how one of them ends up wrong. A
     * `when` rather than `!= LOCAL_FOLDER` so a fifth kind cannot be quietly assumed to
     * be browsable — it has to be answered here.
     *
     * iOS's `SourceKind.isBrowsable` answers the same four the same way.
     */
    val isBrowsable: Boolean
        get() = when (this) {
            LOCAL_FOLDER -> false
            NETWORK_SHARE, OPDS_CATALOG, KAVITA_SERVER -> true
        }
}

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
    /**
     * Where this source points, as the platform names it.
     *
     * A folder's tree URI; a server's URL when one exists. The *stable* key:
     * [displayName] is the reader's and moves when they rename it, so matching a folder to
     * its source by name means a renamed source is not recognised on the next launch and
     * gets added a second time. That is the bug this field exists to prevent.
     *
     * A tree URI is stable across installs here, so it is the locator directly. iOS cannot
     * use a path for this: its app container carries a UUID that changes on reinstall, so
     * the bookmark's key is used there instead.
     */
    val locator: String? = null,
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
