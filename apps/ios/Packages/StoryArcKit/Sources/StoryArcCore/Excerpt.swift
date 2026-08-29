public import Foundation

/// A little of the text at a place in a publication.
///
/// `ebook-reader` requires a bookmark to be "saved with its chapter title and a text
/// excerpt". Readium reports text on a locator that came from a search or a selection, and
/// none at all on one that came from a page turn — which is every locator a bookmark is made
/// from. So the text is taken from the resource instead, at the fraction through it the
/// locator names.
///
/// A fraction rather than a character offset because that is what a reflowable locator
/// carries: ADR-0006 again, a page break is a function of the reader's type size and is not
/// a position in the document. The fraction is, and it is the same fraction on every device.
///
/// Android's `Excerpt` cuts the same strings.
public enum Excerpt {

    /// Long enough to recognise a passage, short enough for two lines in a list.
    public static let length = 120

    /// The words at `fraction` through `text`.
    ///
    /// Starts at a word boundary and ends at one, because an excerpt that opens mid-word
    /// reads as a bug rather than as a quotation. An empty or blank text gives an empty
    /// excerpt, and the row that would have shown it falls back to the chapter title.
    public static func at(_ text: String, fraction: Double, length: Int = length) -> String {
        let whole = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !whole.isEmpty else { return "" }

        let characters = Array(whole)
        let asked = Int(Double(characters.count) * min(1, max(0, fraction)))
        var start = min(max(0, asked), characters.count - 1)
        while start > 0, !characters[start - 1].isWhitespace { start -= 1 }

        let end = min(characters.count, start + length)
        let slice = String(characters[start..<end])
        // Only trim the tail back to a boundary when something was actually cut off: the
        // last words of a resource are the whole of what is left, and dropping them to
        // find a space would lose the end of the chapter.
        let cut = end >= characters.count
            ? slice
            : String(slice[slice.startIndex..<(slice.lastIndex(of: " ") ?? slice.endIndex)])
        return cut.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The readable text of an XHTML resource.
    ///
    /// Deliberately not a parser. This is used for one thing — a hundred and twenty
    /// characters shown in a list — and a resource that defeats it produces a worse excerpt
    /// rather than a wrong bookmark.
    ///
    /// The head goes first, with the scripts and the styles. All three are text to a
    /// tag-stripper and none of them is text to a reader: leaving the head in put the
    /// `<title>` at the front of every excerpt, so a bookmark in "Chapter Two" quoted the
    /// words "Chapter Two" back before reaching a sentence — seen on an emulator, which is
    /// how this rule got written.
    public static func plainText(_ markup: String) -> String {
        var text = markup
        for pattern in ["<head\\b[^>]*>[\\s\\S]*?</head>", "<script\\b[^>]*>[\\s\\S]*?</script>",
                        "<style\\b[^>]*>[\\s\\S]*?</style>", "<[^>]*>"] {
            text = text.replacingOccurrences(
                of: pattern,
                with: " ",
                options: [.regularExpression, .caseInsensitive]
            )
        }
        for (entity, character) in entities {
            text = text.replacingOccurrences(of: entity, with: character)
        }
        text = text.replacingOccurrences(of: "&#?\\w+;", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let entities: [(String, String)] = [
        ("&nbsp;", " "), ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
        ("&quot;", "\""), ("&apos;", "'"), ("&#39;", "'"),
        ("&mdash;", "—"), ("&ndash;", "–"), ("&hellip;", "…"),
    ]
}
