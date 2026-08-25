package app.storyarc.core.model

import java.util.UUID

/**
 * How StoryArc decides two things are the same publication.
 *
 * ADR-0006: a server identifier wins when the publication came from a source
 * that has one; otherwise a content digest, which survives renames, moves and
 * re-downloads; a normalised path only as a last resort.
 *
 * Both a server id and a content digest are recorded when both are known —
 * that is what lets a file read from a folder and the same file read from a
 * Kavita server resolve to one progress record.
 */
data class PublicationIdentity(
    val serverIdentifier: ServerIdentifier? = null,
    val contentDigest: String? = null,
    val normalizedPath: String? = null,
) {
    data class ServerIdentifier(val sourceId: UUID, val remoteId: String)

    /**
     * A stable key for lists, diffing and anything stored against a publication.
     *
     * Built from whichever components exist, in the priority ADR-0006 gives them, so
     * a publication that later gains a server id keeps a usable key throughout
     * rather than changing identity mid-session.
     *
     * On the identity rather than on [Publication], because the identity is the only
     * thing that decides it — and a caller that holds an identity and not a whole
     * publication needs it just as much.
     */
    val stableId: String
        get() = serverIdentifier?.let { "srv:${it.sourceId}:${it.remoteId}" }
            ?: contentDigest?.let { "sha:$it" }
            ?: "path:${normalizedPath ?: ""}"

    /**
     * Two identities match when *any* recorded component matches. A file that
     * gains a server id later still resolves to the progress recorded against
     * its digest.
     */
    fun matches(other: PublicationIdentity): Boolean {
        serverIdentifier?.let { mine ->
            other.serverIdentifier?.let { theirs -> if (mine == theirs) return true }
        }
        contentDigest?.let { mine ->
            other.contentDigest?.let { theirs -> if (mine == theirs) return true }
        }
        normalizedPath?.let { mine ->
            other.normalizedPath?.let { theirs -> if (mine == theirs) return true }
        }
        return false
    }

    /** True when nothing at all was recorded — a bug at the call site. */
    val isEmpty: Boolean
        get() = serverIdentifier == null && contentDigest == null && normalizedPath == null
}
