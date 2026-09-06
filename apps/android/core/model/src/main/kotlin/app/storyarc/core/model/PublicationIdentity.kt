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
     * **The path outranks both the digest and the server here, and only here.** [matches]
     * keeps ADR-0006's order — server, then digest, then path — because that order answers
     * *"are these the same publication?"*, and a server owns its own content better than a
     * path does. This answers a different question: *"what string is this publication filed
     * under?"* The only requirement of a filing key is that it does not move, and a key
     * that changes the moment a new component is learned moves for every publication at
     * once.
     *
     * The path is the component the app learns *first*: a server chapter is read from a
     * file this app has already written, so the path exists before the chapter id is
     * attached to it. Ranking the path first is therefore the same rule as "the key does
     * not move", stated in terms of what is known when.
     *
     * What is filed under it: collection members, reading-list entries, a `Download`'s
     * id *and the folder its bytes live in*, the chapter-to-publication table
     * `KavitaProgressStore` keeps, and the library cache's location map. Re-keying
     * would empty every shelf and orphan every downloaded file on the first launch
     * after the digest started being computed — a far larger loss than the one the
     * digest exists to prevent.
     *
     * It costs nothing, because no identity built in production carries a path together
     * with either of the other two until each is wired in: the scanners produced a path
     * alone until the digest arrived, and nothing built a server identifier at all until
     * the Kavita browser did. Ranking a component nothing had cannot re-key anything that
     * exists. It is a choice about the keys from here on, not a migration.
     *
     * A digest-only identity — a file handed over from outside the app, which has no
     * path this app is entitled to keep — still keys on `sha:`, unchanged. So does a
     * server identity with no local file, which keys on `srv:`.
     *
     * On the identity rather than on [Publication], because the identity is the only
     * thing that decides it — and a caller that holds an identity and not a whole
     * publication needs it just as much.
     */
    val stableId: String
        get() = normalizedPath?.let { "path:$it" }
            ?: serverIdentifier?.let { "srv:${it.sourceId}:${it.remoteId}" }
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
     * The same identity with a server's own identifier recorded against it.
     *
     * ADR-0006's other half of "recorded together when both are known", and the one the
     * app never built. A server chapter is read from a file this app wrote, so this is
     * applied to an identity that already carries that file's path and digest — and
     * [stableId] keeps the path, so nothing is re-filed.
     *
     * One already present is kept, and a `null` changes nothing: `null` is what a source
     * whose id is not an identifier yields, which is the absence of an answer rather than
     * an answer of "none".
     */
    fun recordingServer(server: ServerIdentifier?): PublicationIdentity =
        if (serverIdentifier != null || server == null) this else copy(serverIdentifier = server)

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
