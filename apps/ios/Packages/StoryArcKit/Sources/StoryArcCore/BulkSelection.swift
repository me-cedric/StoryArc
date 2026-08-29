public import Foundation

/// What a bulk action actually changes.
///
/// `collections-and-reading-lists` wants publications "selected in bulk from the library",
/// and wants a bulk mark-read to be "undoable for 10 seconds". Both halves need the same
/// answer: which of the selected publications this action moves. An undo built on the
/// *request* rather than on the change would unread a publication the reader had already
/// finished long before they made the selection — the set went one way and came back
/// smaller, which is the sort of loss nobody reports because nobody notices.
///
/// Every question here answers nothing for an empty selection. That is what makes a bulk
/// action on nothing do nothing, rather than something surprising.
public enum BulkSelection {
    /// The selected publications a collection does not already hold.
    public static func joining(
        _ selection: Set<String>,
        of collection: PublicationCollection
    ) -> Set<String> {
        selection.subtracting(collection.members)
    }

    /// The selected publications a reading list does not already hold, in library order.
    ///
    /// Ordered, because a list's order is its whole meaning: appended in the order the
    /// library was showing them is the only order the reader can predict from what they
    /// were looking at when they picked.
    public static func appending(
        _ selection: Set<String>,
        to list: ReadingList,
        inOrderOf order: [String]
    ) -> [String] {
        let held = Set(list.entries)
        return order.filter { selection.contains($0) && !held.contains($0) }
    }

    /// The selected publications whose read state the mark would change.
    public static func marking(
        _ selection: Set<String>,
        read: Bool,
        finished: Set<String>
    ) -> Set<String> {
        read ? selection.subtracting(finished) : selection.intersection(finished)
    }

    /// The selected publications that are not on the device yet.
    ///
    /// `offline-downloads`: a publication already downloaded gets "a state indicator and a
    /// remove-download action, and the app does not re-fetch it". In bulk that is the same
    /// rule, counted rather than shown.
    public static func downloading(
        _ selection: Set<String>,
        onDevice: Set<String>
    ) -> Set<String> {
        selection.subtracting(onDevice)
    }
}
