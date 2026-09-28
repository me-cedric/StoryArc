internal import StoryArcCore

/// The offer to copy a local reading list onto a server, and the state that offer is in.
///
/// `collections-and-reading-lists` asks for two things this answers. A local list gets the
/// offer, and "only servers that are reachable and hold reading lists are offered". When none
/// of them is, the offer "is disabled and says why, rather than failing after the user has
/// confirmed it".
///
/// A value beside the menu rather than three conditions inside it, because the menu cannot be
/// asked a question. Android's `PromoteOffer` answers the same three.
struct PromoteOffer: Equatable {
    /// Whether the reader can act on the offer. False when no server could take the list.
    let isEnabled: Bool

    /// The one server the copy would go to, when there is exactly one.
    ///
    /// Named on the action itself, so a reader with a single server is told where the list is
    /// going before they open anything. Nil when there are none, and nil when there are
    /// several — several destinations are chosen between on the sheet, not in a label.
    let namedServer: String?

    /// Whether the offer has to carry its reason.
    ///
    /// The same condition as a disabled offer, stated once. A disabled action with no reason
    /// beside it is the failure this scenario exists to prevent, moved one step earlier.
    var statesWhyNot: Bool { !isEnabled }

    /// The offer for a list, or nil when there is nothing to offer.
    ///
    /// Nil for a list a server already holds: copying it onto a server is what it is, so the
    /// action would do nothing a reader could name. Nil for no list at all, which is the
    /// collection screen.
    static func of(_ list: ReadingList?, servers: [KavitaPage]) -> PromoteOffer? {
        guard let list, list.origin == .local else { return nil }
        return PromoteOffer(
            isEnabled: !servers.isEmpty,
            namedServer: servers.count == 1 ? servers.first?.title : nil
        )
    }
}
