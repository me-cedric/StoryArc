package app.storyarc.feature.library

/**
 * Whether *Start from the beginning* belongs in a menu.
 *
 * `reading-progress`: the action is "available from the publication's own cover in the
 * library" and "clears progress only after confirmation".
 *
 * **Written down because iOS's menu drew a button nothing was wired to.** `CoverList`
 * opened its shelf menu with a trailing closure, which under Swift's forward-scan rule
 * binds to the first parameter with no default -- so the restart handler kept the empty
 * closure it defaulted to while the button rendered anyway. A reader in the list layout
 * long-pressed a cover, tapped the action, and nothing at all happened: no confirmation, no
 * clear, no message. Nothing failed, which is why no test caught it.
 *
 * Android was immune by construction, because [AddToShelfSheet] already gated its row on
 * `onRestart != null`. This is that guard lifted out of the sheet so both platforms assert
 * it rather than one of them merely happening to have it. iOS keeps the same rule in
 * `RestartFromBeginning.swift`, case for case.
 */
object RestartOffer {
    /**
     * Whether to draw the action.
     *
     * Three conditions, all of them refusals:
     *
     * - **One publication.** A set of them has no single beginning to go back to.
     * - **Something to clear.** On an unread publication the action would start it from the
     *   beginning it is already at.
     * - **Somewhere to send it.** The confirmation `reading-progress` requires cannot be
     *   presented from inside the sheet, so the action is always the caller's to perform. A
     *   sheet whose caller did not take it has nothing to offer.
     */
    fun isOffered(
        publicationCount: Int,
        hasSomethingToClear: Boolean,
        isWired: Boolean,
    ): Boolean = publicationCount == 1 && hasSomethingToClear && isWired
}
