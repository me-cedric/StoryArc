internal import Foundation

internal import StoryArcCore

/// How well one row answers the question, and how two rows compare when both do.
///
/// `library-browsing`, *Mixed local and server search*: "server results and local results
/// are merged into one **ranked** list". A merge that only concatenated would satisfy the
/// word "merged" and not the word "ranked" — the device's index and somebody's server each
/// hand over rows in an order that means something to them and nothing to each other, and
/// laying one after the other is two lists drawn end to end.
///
/// **Why a local match and a remote match compare the way they do.** Rows are compared on
/// how well the title meets the term *first*, and on where the row lives only when that is
/// a tie. The reader asked for a book, not for a place: a server's exact title beating a
/// folder's loose substring is the right answer, and pushing every remote row under every
/// local one would turn the ranking into a statement about storage. Where two rows answer
/// the question equally well, the one already on the device wins — it opens now and the
/// other needs a network, and that is the only respect in which where it lives is news.
///
/// **What this deliberately does not do is re-rank the screen.** It orders one answer, as
/// that answer arrives. ``SearchListing`` appends the result and never sorts again, because
/// the same requirement's next clause is that "the arrival of remote results never reorders
/// or displaces a result the reader is already reaching for". Ranking within an answer is
/// as much ranking as a list that must not move can have.
///
/// Pure — no network, no clock, no store. Android's `SearchRank` mirrors it, and both
/// platforms hold the same table of cases against it.
enum SearchRank {

    /// How close a row's title comes to the term, best first.
    ///
    /// Five tiers over the title alone. The detail line is a series or an author the local
    /// index has already used to decide which heading the row sits under, and a sixth tier
    /// reading it again would be the grouping's opinion cast a second time as ranking.
    enum Strength: Int, Comparable, Sendable {
        /// The title *is* the term.
        case exact
        /// The title begins with the term.
        case start
        /// A word inside the title begins with the term.
        case word
        /// The term is in the title, mid-word.
        case within
        /// The title does not contain the term. Whoever answered matched something the row
        /// does not show — an author, a tag, a summary this app never saw.
        case elsewhere

        static func < (lhs: Strength, rhs: Strength) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// One answer, ordered. Ties broken so the order is total and cannot wobble.
    ///
    /// Four keys, in this order:
    ///
    /// 1. ``Strength`` — how well the title meets the term.
    /// 2. Held before away, per the note above.
    /// 3. The shorter title — "Bone" answers "bone" more completely than "Bone Companion".
    /// 4. The folded title, so two rows that are equal by every other key still have one
    ///    fixed order rather than whichever one the answerer happened to send first.
    static func ordered(_ rows: [FoundRow], for term: String) -> [FoundRow] {
        let needle = fold(term)
        // Scored once per row rather than inside the comparator: a sort asks the comparator
        // O(n log n) times, and folding a string is the expensive half of this.
        return rows
            .map { (row: $0, key: key(for: $0, needle: needle)) }
            .sorted { less($0.key, $1.key) }
            .map(\.row)
    }

    /// Everything the order depends on, computed once.
    private struct Key {
        let strength: Strength
        let isHeld: Bool
        let length: Int
        let title: String
    }

    private static func key(for row: FoundRow, needle: String) -> Key {
        let title = fold(row.result.title)
        return Key(
            strength: strength(ofFolded: title, forFolded: needle),
            isHeld: row.result.publicationID != nil,
            length: title.count,
            title: title
        )
    }

    private static func less(_ lhs: Key, _ rhs: Key) -> Bool {
        if lhs.strength != rhs.strength { return lhs.strength < rhs.strength }
        if lhs.isHeld != rhs.isHeld { return lhs.isHeld }
        if lhs.length != rhs.length { return lhs.length < rhs.length }
        return lhs.title < rhs.title
    }

    /// How well a title meets a term, both already folded.
    static func strength(ofFolded title: String, forFolded needle: String) -> Strength {
        // An empty term matches nothing in particular, so every row is equally far from it
        // and the remaining keys decide. Reachable only through a caller that asked before
        // trimming; the search itself never asks an empty question.
        guard !needle.isEmpty else { return .elsewhere }
        if title == needle { return .exact }
        if title.hasPrefix(needle) { return .start }
        guard title.contains(needle) else { return .elsewhere }
        return words(of: title).contains(where: { $0.hasPrefix(needle) }) ? .word : .within
    }

    /// The title's words, for the word-start tier.
    ///
    /// Split on everything that is not a letter or a digit, so "Vol.2" is two words and
    /// "d'Artagnan" is two — a reader who types "artagnan" has started a word as far as
    /// they are concerned.
    private static func words(of folded: String) -> [Substring] {
        folded.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
    }

    /// Case and accents removed, so "Café" answers "cafe" and "CAFE".
    ///
    /// `locale: nil` rather than the reader's: this is a comparison key, not a sort the
    /// reader reads, and a locale-sensitive fold would make the same two rows compare
    /// differently on two devices. Alphabetical *display* order is `LibraryIndex.arrange`'s
    /// job and does use the reader's collation.
    ///
    /// Android's `SearchRank.fold` strips the same two things with `Normalizer` and
    /// `lowercase(Locale.ROOT)`, and the mirrored tests hold both to the same table.
    static func fold(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
