package app.storyarc.feature.library

import app.storyarc.core.model.Source

/**
 * What removing a source takes with it, decided without a screen or a keystore.
 *
 * "Remove source" used to begin by looking for the folder behind the source and returning
 * when there was none, so removing a Kavita server or an SMB share did nothing at all: the
 * source stayed in the registry, the app kept using it, and its password stayed in the
 * secure store with nothing left in the app that would ever look it up again. Rank 8 of the
 * 30 August security review.
 *
 * A value rather than a sequence of statements inside the view model, so the order — the
 * secret is not conditional on the folder — can be asserted without an Android runtime.
 * iOS's `SourceRemoval` makes the same two answers.
 *
 * Folders arrive as strings rather than as `Uri`s, because a `Uri` cannot be built in a JVM
 * unit test; the view model matches the answer back to the tree it holds.
 */
internal data class SourceRemoval(
    /**
     * The secret to forget, or null when the source never had one.
     *
     * The reference the *registry* stored, never one re-derived from the source's id: a
     * source whose id and credential reference disagree would otherwise keep its key.
     */
    val credentialReference: String?,
    /** The folder whose permission goes back, or null when the source is not a folder. */
    val folder: String?,
) {
    companion object {
        fun of(source: Source, folders: List<String>): SourceRemoval = SourceRemoval(
            credentialReference = source.credentialReference,
            folder = folders.firstOrNull { it == source.locator },
        )
    }
}
