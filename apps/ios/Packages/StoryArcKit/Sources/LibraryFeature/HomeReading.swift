internal import Foundation

internal import StoryArcCore

// What Home needs to say about one publication, asked of the model that already knows.
//
// A file of its own rather than three computed properties on a view: both the hero and the
// shelves ask the same three questions, and a screen where the carousel and the row
// disagree about whether a book can be opened is worse than one that never says.

extension LibraryModel {

    /// The reading record for a publication, if there is one.
    ///
    /// Home reads the record rather than ``readFraction(of:)`` because it needs more than
    /// a fraction: how much is *left* in pages, and when a publication was finished. Both
    /// are on the record and neither survives being reduced to a number between nought and
    /// one.
    func record(of publication: Publication) -> ReadingProgress? {
        progress[publication.id]
    }

    /// Whether the reader could open this right now, on this device, with no network.
    ///
    /// `home-screen`: a publication that cannot be opened "stays in Keep reading, dimmed,
    /// saying plainly that it cannot be opened right now" — it is never dropped, "because a
    /// row that shrinks with the Wi-Fi reads as lost reading".
    ///
    /// The question is answered from what the app holds — a location it recorded, and a
    /// format it can decode — and never by asking a server. Asking would be the one thing
    /// this screen must not do, and the answer would arrive after the shelf had drawn
    /// anyway.
    func isReadableNow(_ publication: Publication) -> Bool {
        publication.isOpenable && location(of: publication) != nil
    }

    /// How much of a publication is left, in the reader's own terms.
    ///
    /// `home-screen` asks for what remains to be stated "as pages or time remaining, rather
    /// than as a percentage alone", and a paged comic answers exactly: the position is a
    /// page index out of a total, so the subtraction is the whole of it.
    ///
    /// A reflowable book has no such number — ADR-0006 is explicit that a reflowable page
    /// count is a function of the reader's own typography — so the estimate is made against
    /// the spine count when the app knows one, and only when it knows neither does the
    /// percentage appear. Last resort, and named as one.
    func remaining(of publication: Publication) -> String? {
        guard let record = record(of: publication), !record.isFinished else { return nil }

        if case let .page(index, total) = record.position, total > 0 {
            return Self.pagesLeft(max(0, total - index - 1))
        }

        let left = max(0, 1 - record.position.fraction)
        if let pages = publication.pageCount, pages > 0 {
            return Self.pagesLeft(Int((left * Double(pages)).rounded()))
        }

        return String(
            localized: "home.percentLeft \(Int((left * 100).rounded()))",
            bundle: .module,
            locale: .storyArc
        )
    }

    private static func pagesLeft(_ pages: Int) -> String? {
        // Nought pages left is not a sentence anyone needs: the publication is on its last
        // page and about to leave this shelf anyway.
        guard pages > 0 else { return nil }
        return String(localized: "home.pagesLeft \(pages)", bundle: .module, locale: .storyArc)
    }
}
