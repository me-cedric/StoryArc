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
    /// 4. The folded title, compared **code point by code point**, so two rows that are equal
    ///    by every other key still have one fixed order rather than whichever one the
    ///    answerer happened to send first — and the same fixed order on both platforms.
    ///    Swift's `<` on `String` orders by scalar and Kotlin's `compareTo` by UTF-16 unit,
    ///    which disagree the moment a title outside the basic plane meets one inside it:
    ///    a leading surrogate is `0xD800`-something and sorts under `U+E000` and above,
    ///    where the scalar it stands for sorts over both.
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
    ///
    /// The title is kept as its code points and never as a `String`, because both remaining
    /// keys are counts and comparisons over them. Swift counts a grapheme cluster as one
    /// character where Kotlin counts a UTF-16 unit, and the two order strings differently as
    /// well — a title with an astral character or a flag emoji would land in a different
    /// place on each platform. Code points are the one unit both agree on, and this is the
    /// kind of silent mirror drift this project has already been bitten by once, in natural
    /// sort.
    private struct Key {
        let strength: Strength
        let isHeld: Bool
        let title: [UInt32]
    }

    private static func key(for row: FoundRow, needle: String) -> Key {
        let title = fold(row.result.title)
        return Key(
            strength: strength(ofFolded: title, forFolded: needle),
            isHeld: row.result.publicationID != nil,
            title: title.unicodeScalars.map(\.value)
        )
    }

    private static func less(_ lhs: Key, _ rhs: Key) -> Bool {
        if lhs.strength != rhs.strength { return lhs.strength < rhs.strength }
        if lhs.isHeld != rhs.isHeld { return lhs.isHeld }
        if lhs.title.count != rhs.title.count { return lhs.title.count < rhs.title.count }
        return lhs.title.lexicographicallyPrecedes(rhs.title)
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

    /// Case and accents removed, and nothing else, so "Café" answers "cafe" and "CAFE".
    ///
    /// Three steps in this order, spelled out rather than delegated: decompose, drop the
    /// non-spacing marks, lower-case without a locale.
    ///
    /// **`String.folding(options:)` is deliberately not used, and this is the interesting
    /// part.** It performs a *full* case fold: it turns "Straße" into "strasse" and the "ﬁ"
    /// ligature into "fi". Kotlin has no equivalent — `lowercase` leaves both alone — so a
    /// fold written the obvious way on each platform would rank a German title one way on
    /// iOS and another on Android, silently, for the readers most likely to have such a
    /// title. The mirror is worth more than the extra match: this only decides *order*,
    /// because which rows arrive at all is the local index's job and the server's, so a
    /// "Straße" row is still on screen either way.
    ///
    /// No locale, on either side: this is a comparison key, not a sort the reader reads, and
    /// a locale-sensitive fold would make the same two rows compare differently on two
    /// devices. Alphabetical *display* order is `LibraryIndex.arrange`'s job and does use
    /// the reader's collation.
    ///
    /// Android's `SearchRank.fold` performs the same three steps, and the mirrored tests
    /// hold both to the same table — including the two cases above.
    static func fold(_ value: String) -> String {
        let decomposed = String(String.UnicodeScalarView(trimmed(value)))
            .decomposedStringWithCanonicalMapping
        let base = decomposed.unicodeScalars.filter {
            $0.properties.generalCategory != .nonspacingMark
        }
        return String(String.UnicodeScalarView(base)).lowercased()
    }

    /// The value with its surrounding blank space removed, by a rule both platforms spell
    /// out rather than inherit.
    ///
    /// `CharacterSet.whitespacesAndNewlines` and Kotlin's `String.trim` are *not* the same
    /// set: Java's `Character.isWhitespace` is false for the non-breaking spaces `U+00A0`,
    /// `U+2007` and `U+202F`, which Foundation trims. A term pasted with a leading
    /// non-breaking space — which is what a copy out of a web page or a PDF often is — would
    /// then land in a different strength tier on each platform.
    ///
    /// So the set is named here instead of borrowed: every separator, and the control
    /// characters that end a line. Android's `SearchRank.trimmed` names the same one.
    private static func trimmed(_ value: String) -> [Unicode.Scalar] {
        var scalars = Array(value.unicodeScalars)
        while let first = scalars.first, isBlank(first) { scalars.removeFirst() }
        while let last = scalars.last, isBlank(last) { scalars.removeLast() }
        return scalars
    }

    private static func isBlank(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .spaceSeparator, .lineSeparator, .paragraphSeparator: true
        default: (0x09...0x0D).contains(scalar.value) || scalar.value == 0x85
        }
    }
}
