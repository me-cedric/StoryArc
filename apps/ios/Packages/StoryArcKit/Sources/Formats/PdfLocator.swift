internal import Foundation

/// Where in a PDF a mark or a hit is.
///
/// `ebook-reader` stores a highlight against "the renderer's own locator", and for a
/// reflowable publication that is Readium's JSON. A PDF has no such renderer: its text is a
/// run of characters per page, and the only thing that finds the same words again is the page
/// plus the offsets into it. So this is that locator, and it is carried in the same
/// ``Annotation/locator`` field the EPUB reader uses — which is what lets one
/// ``AnnotationExport`` write both without knowing the difference.
///
/// Written and read by hand rather than through `Codable`. Three integers do not need a
/// coder, and hand-writing them is what guarantees the two platforms produce the *same*
/// string rather than two encoders' idea of the same record — key order included.
///
/// Offsets are UTF-16 code units into the page's text, which is what both platforms' text
/// APIs count in: `NSRange` on one side, `String` indices on the other.
///
/// Android's `PdfLocator` reads and writes the same string.
public struct PdfLocator: Sendable, Equatable {
    /// Zero-based, the way every page index in the reader is.
    public let page: Int
    /// First code unit of the run, inclusive.
    public let start: Int
    /// One past the last code unit of the run.
    public let end: Int

    public init(page: Int, start: Int, end: Int) {
        self.page = page
        self.start = start
        self.end = end
    }

    /// The locator as it is stored. Compact, ordered, and the same on both platforms.
    public var json: String {
        #"{"page":\#(page),"start":\#(start),"end":\#(end)}"#
    }

    /// Reads one back, or `nil` when the string is not one.
    ///
    /// `nil` rather than a throw, and lenient about what surrounds the numbers: a locator
    /// that cannot be read means a mark that cannot be drawn, which the reader already
    /// handles by leaving it out of the page rather than by failing to open the book.
    public init?(json: String) {
        guard let page = PdfLocator.number("page", in: json),
              let start = PdfLocator.number("start", in: json),
              let end = PdfLocator.number("end", in: json),
              page >= 0, start >= 0, end >= start
        else { return nil }
        self.init(page: page, start: start, end: end)
    }

    private static func number(_ key: String, in json: String) -> Int? {
        guard let keyRange = json.range(of: "\"\(key)\"") else { return nil }
        let rest = json[keyRange.upperBound...]
        guard let colon = rest.firstIndex(of: ":") else { return nil }
        let digits = rest[rest.index(after: colon)...].prefix { $0 == " " || $0 == "-" || $0.isNumber }
        return Int(digits.trimmingCharacters(in: .whitespaces))
    }
}
