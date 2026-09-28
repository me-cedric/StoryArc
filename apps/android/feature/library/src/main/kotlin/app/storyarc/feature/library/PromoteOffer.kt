package app.storyarc.feature.library

import app.storyarc.core.model.ReadingList
import app.storyarc.core.model.ShelfOrigin

/**
 * The offer to copy a local reading list onto a server, and the state that offer is in.
 *
 * `collections-and-reading-lists` asks for two things this answers. A local list gets the
 * offer, and "only servers that are reachable and hold reading lists are offered". When
 * none of them is, the offer "is disabled and says why, rather than failing after the user
 * has confirmed it".
 *
 * A value beside the menu rather than three conditions inside it, because the menu cannot be
 * asked a question. iOS's `PromoteOffer` answers the same three.
 */
data class PromoteOffer(
    /** Whether the reader can act on the offer. False when no server could take the list. */
    val isEnabled: Boolean,
    /**
     * The one server the copy would go to, when there is exactly one.
     *
     * Named on the action itself, so a reader with a single server is told where the list is
     * going before they open anything. Null when there are none, and null when there are
     * several — several destinations are chosen between on the sheet, not in a label.
     */
    val namedServer: String?,
) {
    /**
     * Whether the offer has to carry its reason.
     *
     * The same condition as a disabled offer, stated once. A disabled action with no reason
     * beside it is the failure this scenario exists to prevent, moved one step earlier.
     */
    val statesWhyNot: Boolean get() = !isEnabled

    companion object {
        /**
         * The offer for a list, or null when there is nothing to offer.
         *
         * Null for a list a server already holds: copying it onto a server is what it is, so
         * the action would do nothing a reader could name. Null for no list at all, which is
         * the collection screen.
         */
        fun of(list: ReadingList?, servers: List<KavitaPage>): PromoteOffer? {
            if (list == null || list.origin != ShelfOrigin.Local) return null
            return PromoteOffer(
                isEnabled = servers.isNotEmpty(),
                namedServer = servers.singleOrNull()?.title,
            )
        }
    }
}
