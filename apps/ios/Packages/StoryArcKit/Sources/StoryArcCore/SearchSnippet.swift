public import Foundation

/// One match inside a publication, as a line a reader can read.
///
/// `ebook-reader`: "matches are listed with surrounding context and tapping one jumps to
/// it". The renderer reports the words on each side of a hit and how much of each it felt
/// like giving; what a list needs is a bounded line with the match still visible in it, and
/// that is what this makes.
///
/// Its own type rather than three strings passed around, because the trimming has a rule
/// worth stating once and asserting on both platforms: the *match* is what must survive.
/// Trimming the context symmetrically would be the obvious thing and the wrong one — a hit
/// near the start of a paragraph has almost nothing before it and plenty after, and taking
/// the same number of characters from each side would waste the budget on one and cut the
/// other.
///
/// Android's `SearchSnippet` cuts the same strings.
public struct SearchSnippet: Sendable, Equatable {
    /// What comes before the match, already trimmed.
    public let before: String
    /// The matched words themselves. Never trimmed.
    public let match: String
    /// What comes after the match, already trimmed.
    public let after: String

    /// How much context a row can hold, either side of the match together.
    public static let budget = 90

    /// Builds a snippet, spending the budget on whichever side has text to spend it on.
    ///
    /// The match is kept whole even when it alone exceeds the budget: a row that elided the
    /// thing the reader searched for would be a row about nothing.
    public init(before: String, match: String, after: String, budget: Int = budget) {
        self.match = match

        let leading = before.trimmingCharacters(in: .whitespacesAndNewlines)
        let trailing = after.trimmingCharacters(in: .whitespacesAndNewlines)

        // Half each, then whatever the shorter side did not use goes to the longer one.
        let half = max(0, budget) / 2
        let leadingSpare = max(0, half - leading.count)
        let trailingSpare = max(0, half - trailing.count)

        self.before = SearchSnippet.tail(of: leading, limit: half + trailingSpare)
        self.after = SearchSnippet.head(of: trailing, limit: half + leadingSpare)
    }

    /// The whole line, for a reader and for a screen reader.
    ///
    /// One string rather than three, because VoiceOver reading "before, match, after" as
    /// three labels is three announcements of one sentence.
    public var line: String {
        [before, match, after].filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// The end of the leading context — the words nearest the match, not the first ones.
    private static func tail(of text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        let cut = String(text.suffix(limit))
        // Start at a word, so the line does not open mid-word.
        guard let space = cut.firstIndex(of: " ") else { return cut }
        return String(cut[cut.index(after: space)...])
    }

    /// The start of the trailing context — the words nearest the match.
    private static func head(of text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        let cut = String(text.prefix(limit))
        guard let space = cut.lastIndex(of: " ") else { return cut }
        return String(cut[cut.startIndex..<space])
    }
}
