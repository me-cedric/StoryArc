package app.storyarc.core.model

/**
 * One entry in the menu the launcher shows when the app icon is held down.
 *
 * `native-experience` names quick actions among the system affordances the app is required
 * to use rather than invent. What belongs in that menu is the short list of things a
 * reader opens the app *for*, which is why there are three of them and not seven: a menu
 * long enough to read is a menu, not a shortcut.
 *
 * The payload is on [ContinueReading] alone, because it is the only entry that is about a
 * particular book. The other two are places.
 *
 * iOS's `QuickAction` mirrors this case for case.
 */
sealed interface QuickAction {

    /**
     * The identifier the system stores this entry under.
     *
     * Reverse-DNS and written out rather than derived from the class name: these strings
     * outlive a launch — Android keeps them in the launcher's own shortcut store and iOS
     * in `UIApplication.shortcutItems` — so renaming a case must not silently orphan every
     * menu already on a reader's home screen. Both platforms store these three.
     */
    val id: String

    /** The publication the reader was in the middle of, named so the menu says which book. */
    data class ContinueReading(val publicationId: String, val title: String) : QuickAction {
        override val id: String get() = CONTINUE_ID
    }

    /** Everything on the device, whatever the app was showing when it was last left. */
    data object Library : QuickAction {
        override val id: String get() = LIBRARY_ID
    }

    /** What has been fetched, and what is still coming. */
    data object Downloads : QuickAction {
        override val id: String get() = DOWNLOADS_ID
    }

    companion object {
        const val CONTINUE_ID = "app.storyarc.quickaction.continue"
        const val LIBRARY_ID = "app.storyarc.quickaction.library"
        const val DOWNLOADS_ID = "app.storyarc.quickaction.downloads"
    }
}

/**
 * What a quick action asks the app to do, read back after the system has handed it over.
 *
 * A separate type from [QuickAction] because the two travel in opposite directions and
 * carry different things: the app publishes a title so the menu can be read, and the
 * system hands back an identifier so the app can act. Collapsing them would mean trusting
 * a title the system stored a week ago to still name the right book.
 */
sealed interface QuickActionRequest {
    data class ContinueReading(val publicationId: String) : QuickActionRequest
    data object Library : QuickActionRequest
    data object Downloads : QuickActionRequest

    companion object {
        /**
         * Reads a request back from the identifier the system stored, and the publication
         * the entry was carrying.
         *
         * `null` rather than a default for anything unrecognised. A menu on a reader's home
         * screen can be older than the app that is now handling it, and an unknown entry
         * that quietly fell back to the library would look like the app ignoring a tap. A
         * continue entry with no publication is refused for the stronger version of the
         * same reason: opening *something* would be opening the wrong book.
         */
        fun of(id: String?, publicationId: String? = null): QuickActionRequest? = when (id) {
            QuickAction.CONTINUE_ID ->
                publicationId?.takeIf { it.isNotEmpty() }?.let { ContinueReading(it) }
            QuickAction.LIBRARY_ID -> Library
            QuickAction.DOWNLOADS_ID -> Downloads
            else -> null
        }
    }
}

/**
 * What the menu holds, given what the reader has.
 *
 * Pure, and deliberately so: this is the half of the capability that has to be identical on
 * both platforms, and it is the half worth asserting against the same table in both suites
 * (ADR-0001). Everything else — a `ShortcutInfoCompat` here, a `UIApplicationShortcutItem`
 * there — is the platform's own vocabulary for the same list.
 */
object QuickActions {

    /**
     * The entries to publish, in the order the reader should meet them.
     *
     * Continue first, because it is the reason someone holds the icon down rather than
     * tapping it. Library always, because it is the one destination that exists on a fresh
     * install. Downloads only once there is something in it: a permanent entry that opens
     * onto an empty screen is a promise the app cannot keep, and downloads only ever arrive
     * from a catalogue, a server or a share.
     *
     * A publication with no usable title is not offered. The entry's whole job is to name
     * the book, and one headed by a blank line would be a menu row a reader cannot read —
     * `offline-downloads` has already met a whitespace-only title once.
     */
    fun offered(continuing: Publication?, hasDownloads: Boolean): List<QuickAction> = buildList {
        val title = continuing?.displayTitle?.trim()
        if (continuing != null && !title.isNullOrEmpty()) {
            add(QuickAction.ContinueReading(continuing.id, title))
        }
        add(QuickAction.Library)
        if (hasDownloads) add(QuickAction.Downloads)
    }
}
