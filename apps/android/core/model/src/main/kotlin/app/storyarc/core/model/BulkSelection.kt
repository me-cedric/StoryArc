package app.storyarc.core.model

/**
 * What a bulk action actually changes.
 *
 * `collections-and-reading-lists` wants publications "selected in bulk from the library",
 * and wants a bulk mark-read to be "undoable for 10 seconds". Both halves need the same
 * answer: which of the selected publications this action moves. An undo built on the
 * *request* rather than on the change would unread a publication the reader had already
 * finished long before they made the selection -- the set went one way and came back
 * smaller, which is the sort of loss nobody reports because nobody notices.
 *
 * Every question here answers nothing for an empty selection. That is what makes a bulk
 * action on nothing do nothing, rather than something surprising.
 *
 * iOS's `BulkSelection` answers the same four questions.
 */
object BulkSelection {

    /** The selected publications a collection does not already hold. */
    fun joining(selection: Set<String>, collection: PublicationCollection): Set<String> =
        selection - collection.members

    /**
     * The selected publications a reading list does not already hold, in library order.
     *
     * Ordered, because a list's order is its whole meaning: appended in the order the
     * library was showing them is the only order the reader can predict from what they were
     * looking at when they picked.
     */
    fun appending(selection: Set<String>, list: ReadingList, order: List<String>): List<String> {
        val held = list.entries.toSet()
        return order.filter { it in selection && it !in held }
    }

    /** The selected publications whose read state the mark would change. */
    fun marking(selection: Set<String>, read: Boolean, finished: Set<String>): Set<String> =
        if (read) selection - finished else selection intersect finished

    /**
     * The selected publications that are not on the device yet.
     *
     * `offline-downloads`: a publication already downloaded gets "a state indicator and a
     * remove-download action, and the app does not re-fetch it". In bulk that is the same
     * rule, counted rather than shown.
     */
    fun downloading(selection: Set<String>, onDevice: Set<String>): Set<String> =
        selection - onDevice
}
