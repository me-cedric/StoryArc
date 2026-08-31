package app.storyarc.core.model

import kotlinx.serialization.Serializable

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
@Serializable
data class PublicationIdentity(
    val serverIdentifier: ServerIdentifier? = null,
    val contentDigest: String? = null,
    val normalizedPath: String? = null,
) {
    @Serializable
    data class ServerIdentifier(
        @Serializable(with = UuidSerializer::class) val sourceId: UUID,
        val remoteId: String,
    )

    /**
     * A stable key for lists, diffing and anything stored against a publication.
     *
     * **The path outranks the digest here, and only here.** [matches] keeps ADR-0006's
     * order — server, then digest, then path — because that order answers *"are these
     * the same publication?"*, and a digest answers it better than a path does. This
     * answers a different question: *"what string is this publication filed under?"*
     * The only requirement of a filing key is that it does not move, and a key that
     * changes the moment a new component is learned moves for every publication at
     * once.
     *
     * What is filed under it: collection members, reading-list entries, a `Download`'s
     * id *and the folder its bytes live in*, the chapter-to-publication table
     * `KavitaProgressStore` keeps, and the library cache's location map. Re-keying
     * would empty every shelf and orphan every downloaded file on the first launch
     * after the digest started being computed — a far larger loss than the one the
     * digest exists to prevent.
     *
     * It costs nothing today, because no identity built in production carries both a
     * path and a digest: the scanners produced a path alone until the digest was wired
     * in, so ranking a component nothing had cannot re-key anything that exists. It is
     * a choice about the keys from here on, not a migration.
     *
     * A digest-only identity — a file handed over from outside the app, which has no
     * path this app is entitled to keep — still keys on `sha:`, unchanged.
     *
     * On the identity rather than on [Publication], because the identity is the only
     * thing that decides it — and a caller that holds an identity and not a whole
     * publication needs it just as much.
     */
    val stableId: String
        get() = serverIdentifier?.let { "srv:${it.sourceId}:${it.remoteId}" }
            ?: normalizedPath?.let { "path:$it" }
            ?: contentDigest?.let { "sha:$it" }
            ?: "path:"

    /**
     * The same identity with a content digest recorded against it.
     *
     * Components fill in as they become known rather than replacing each other —
     * ADR-0006 records a server id and a digest together when both are known, and this
     * is one half of that. A digest already present is kept: whoever supplied it knew
     * something this caller does not, and a `null` is the absence of an answer rather
     * than an answer of "none".
     */
    fun recordingDigest(digest: String?): PublicationIdentity =
        if (contentDigest != null || digest == null) this else copy(contentDigest = digest)

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
