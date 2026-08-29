public import Foundation

/// What the reader searched for lately, most recent first.
///
/// `library-browsing`: "when a user opens search, recent queries are offered, and
/// can be cleared". A value with its own rules rather than an array in the model,
/// because those rules — trim, fold duplicates, cap the list — have to come out the
/// same on both platforms, and that is only worth trusting when the same table is
/// put to both (ADR-0001). Android's `RecentSearches` mirrors it.
public struct RecentSearches: Sendable, Equatable {
    /// How many are kept.
    ///
    /// Enough to cover an evening of looking, short enough that the list under a
    /// search field stays something a reader reads rather than scrolls.
    public static let limit = 8

    public let terms: [String]

    public init(_ terms: [String] = []) {
        self.terms = terms
    }

    public var isEmpty: Bool { terms.isEmpty }

    /// The list with `term` at the front.
    ///
    /// Duplicates fold case-insensitively and the newest spelling wins: someone who
    /// searched "Bone" and then "bone" made one search, and two rows that read the
    /// same would look like a bug rather than like history.
    ///
    /// Called once per keystroke, which the folding above is what makes safe: a
    /// term that is only whitespace changes nothing, and a term that is the same
    /// search half-typed collapses into the one already there.
    public func recording(_ term: String) -> RecentSearches {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return self }

        var kept = terms
        // Typing and backspacing is one search, not one per keystroke. A term the
        // newest entry differs from only by how much of it had been typed is that
        // same search, and the longer spelling is the one the reader meant — which
        // is what stops a reader who deletes "manga" back to nothing from filing
        // an "m" they never searched for.
        if let newest = kept.first, newest.isPrefixOrExtension(of: trimmed) {
            if newest.count >= trimmed.count { return self }
            kept.removeFirst()
        }
        kept.removeAll { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
        return RecentSearches(Array(([trimmed] + kept).prefix(Self.limit)))
    }
}

extension String {
    /// Whether one of the two strings is the start of the other, ignoring case.
    ///
    /// The test for "these are two moments of the same typed search" rather than
    /// two searches. Case-insensitive because the keyboard's own capitalisation is
    /// not a decision the reader made.
    fileprivate func isPrefixOrExtension(of other: String) -> Bool {
        let mine = lowercased()
        let theirs = other.lowercased()
        return mine.hasPrefix(theirs) || theirs.hasPrefix(mine)
    }
}
