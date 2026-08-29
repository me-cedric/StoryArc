public import Foundation

/// Which member covers stand in for a collection that has no cover of its own.
///
/// `collections-and-reading-lists`: a collection's cover "is a composite of its first four
/// member covers unless the user sets a specific one". Two words in that sentence have to
/// be decided before anything can be drawn, and decided the same way twice — a rule each
/// platform guessed at separately is how one reader's shelf ends up looking like a
/// different app's.
///
/// *First* is by identity, ascending. A collection is a set and a set has no first; the
/// library's own order is the tempting alternative, and it moves the moment the reader
/// touches the sort control — a cover that rearranged itself because someone sorted their
/// shelf by date would read as a fault rather than as a rule.
///
/// *Composite* is four or it is one. A quadrant with two empty cells does not read as a
/// design, it reads as artwork that failed to load, so a collection holding fewer than four
/// shows its first cover across the whole frame instead.
public enum CompositeCover {
    /// How many covers a composite is made of.
    public static let tileCount = 4

    /// The member identities to draw, in the order they are drawn.
    ///
    /// Empty for a collection holding nothing — there is no artwork to composite from and
    /// the caller draws its own placeholder. One identity means one cover filling the
    /// frame; ``tileCount`` of them means the quadrants, left to right and top to bottom.
    public static func tiles(of collection: PublicationCollection) -> [String] {
        // The reader's own choice wins outright, which is what "unless the user sets a
        // specific one" means. Checked against the membership as well, because a cover that
        // has left the collection is not the collection's cover any more.
        if let chosen = collection.coverMemberID, collection.members.contains(chosen) {
            return [chosen]
        }
        let ordered = collection.members.sorted()
        guard ordered.count >= tileCount else { return Array(ordered.prefix(1)) }
        return Array(ordered.prefix(tileCount))
    }
}
