internal import Foundation

public import StoryArcCore

/// One hit inside a PDF's text layer.
public struct PdfTextMatch: Sendable, Equatable {
    public let locator: PdfLocator
    public let snippet: SearchSnippet

    public init(locator: PdfLocator, snippet: SearchSnippet) {
        self.locator = locator
        self.snippet = snippet
    }
}

/// Finding a word in a page of PDF text.
///
/// `ebook-reader`: a PDF that "contains a text layer" gets in-publication search, and
/// `Navigation and annotation` says matches are "listed with surrounding context". Both
/// platforms have a native PDF search — `PDFDocument.findString` on one, `Page.searchText` on
/// the other — and neither of them reports the words around a hit, which is the half a list
/// row needs. So the page's text is read once and searched here instead, and the context
/// comes out of the same string the offsets point into.
///
/// That is also what keeps the two readers honest about ``SearchSnippet``: there is one
/// snippet rule in this app, the one the EPUB reader already uses, and a PDF hit is trimmed
/// by it rather than by a second rule that would drift from it.
///
/// Android's `PdfTextSearch` cuts the same matches.
public enum PdfTextSearch {

    /// How many characters either side of a hit are handed to ``SearchSnippet``.
    ///
    /// The snippet's own budget: it spends what it is given and no more, so handing it
    /// exactly that much makes the trimming deterministic everywhere except at the edges of
    /// a page, which is where the spare-budget rule is supposed to show.
    public static let context = SearchSnippet.budget

    /// How many hits one search reports.
    ///
    /// A search for "the" in a four-hundred-page manual has tens of thousands of answers and
    /// no reader scrolls them. The cap is stated in the list rather than applied quietly —
    /// `ebook-reader` forbids a control that promises what it does not deliver, and a
    /// truncated list that says it is truncated keeps that promise.
    public static let matchLimit = 200

    /// Every occurrence of `query` in one page's text, in reading order.
    ///
    /// Case-insensitive, because a reader searching for a name does not capitalise it.
    /// Not diacritic-insensitive: the two platforms fold accents differently, and a search
    /// that found different things on each would be a divergence nothing could assert.
    public static func matches(
        in text: String,
        page: Int,
        query: String,
        limit: Int = matchLimit
    ) -> [PdfTextMatch] {
        guard !query.isEmpty, limit > 0, !text.isEmpty else { return [] }

        var found: [PdfTextMatch] = []
        var cursor = text.startIndex

        while found.count < limit,
              cursor < text.endIndex,
              let hit = text.range(
                  of: query,
                  options: [.caseInsensitive],
                  range: cursor..<text.endIndex
              ) {
            let leading = text.index(
                hit.lowerBound, offsetBy: -context, limitedBy: text.startIndex
            ) ?? text.startIndex
            let trailing = text.index(
                hit.upperBound, offsetBy: context, limitedBy: text.endIndex
            ) ?? text.endIndex

            found.append(
                PdfTextMatch(
                    locator: PdfLocator(
                        page: page,
                        start: hit.lowerBound.utf16Offset(in: text),
                        end: hit.upperBound.utf16Offset(in: text)
                    ),
                    snippet: SearchSnippet(
                        before: condensed(text[leading..<hit.lowerBound]),
                        match: condensed(text[hit]),
                        after: condensed(text[hit.upperBound..<trailing])
                    )
                )
            )

            // Past the hit, so an overlapping second match of the same run is not reported
            // twice. An empty query cannot reach here, so this always advances.
            cursor = hit.upperBound
        }
        return found
    }

    /// The words a locator names, or `nil` when it does not name any of this text.
    ///
    /// What the reader shows in a mark's row, and what goes into the export.
    public static func text(_ locator: PdfLocator, in text: String) -> String? {
        let units = text.utf16.count
        guard locator.start < units, locator.end <= units, locator.start < locator.end
        else { return nil }
        let start = String.Index(utf16Offset: locator.start, in: text)
        let end = String.Index(utf16Offset: locator.end, in: text)
        guard start < end else { return nil }
        let run = condensed(text[start..<end])
        return run.isEmpty ? nil : run
    }

    /// One line out of text that was laid out in columns.
    ///
    /// A PDF's text layer carries the line breaks of the *page*, not of the sentence, so a
    /// snippet taken straight out of it arrives with newlines through the middle of it and
    /// reads as three rows in one. The offsets are untouched by this — they point into the
    /// original — so what a mark selects is still exactly what the reader selected.
    private static func condensed(_ text: Substring) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
