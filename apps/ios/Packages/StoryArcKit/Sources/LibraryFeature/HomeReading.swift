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
    /// The decision is ``HomeShelves/remainder(of:record:)``'s; this looks the sentence up.
    /// Split that way because the unit is the requirement and the sentence is not: `swift
    /// build` copies an `.xcstrings` without compiling it, so a host test asserting prose
    /// would be asserting a lookup that cannot work where it runs — the trade `PlayerLabels`
    /// documents at length.
    func remaining(of publication: Publication) -> String? {
        switch HomeShelves.remainder(of: publication, record: record(of: publication)) {
        case let .pages(count):
            String(localized: "home.pagesLeft \(count)", bundle: .module, locale: .storyArc)
        case let .percent(left):
            String(localized: "home.percentLeft \(left)", bundle: .module, locale: .storyArc)
        case .nothingToSay:
            nil
        }
    }
}

/// What Home can honestly say is left of a publication.
///
/// A decision rather than a string, for the reason ``LibraryModel/remaining(of:)`` gives.
/// ``HomeRemainderTests`` is where each case is pinned.
enum HomeRemainder: Equatable, Sendable {
    /// Pages, counted or estimated against a spine.
    case pages(Int)
    /// The last resort, and named as one: a percentage for a book whose length is unknown.
    case percent(Int)
    /// Nothing this surface can state truthfully — including a page or less of a comic,
    /// which is about to leave the shelf anyway.
    case nothingToSay
}

extension HomeShelves {

    /// What remains of a publication, in whichever unit the app actually knows.
    ///
    /// `home-screen` asks for what remains to be stated "as pages or time remaining, rather
    /// than as a percentage alone", and a paged comic answers exactly: the position is a
    /// page index out of a total, so the subtraction is the whole of it.
    ///
    /// A reflowable book has no such number — ADR-0006 is explicit that a reflowable page
    /// count is a function of the reader's own typography — so the estimate is made against
    /// the spine count when the app knows one, and only when it knows neither does the
    /// percentage appear.
    ///
    /// **A listening position is answered with silence, and that is a decision rather than a
    /// gap.** Home's hero read `2 pages left` for `Sea Room`, an M4B — the September sweep's
    /// `ios-home-top.png`. The number was real and the unit was not:
    /// `PublicationIndexer.audiobook` stores the *part* count in `pageCount`, on the
    /// reasoning that "a comic missing pages and an audiobook missing a part are the same
    /// question", so the fall-through below had a number and multiplied a fraction by it.
    ///
    /// The spec's other unit is not derivable here. `ReadingPosition.listening` carries the
    /// offset into the current part and that part's length, and nothing about the parts after
    /// it; `Publication` records no duration at all, because nothing has read one out of an
    /// audiobook yet. A percentage would be one over *parts* — an equal-length guess, where
    /// `reading-progress` asks for a percentage "derived from the total duration" and
    /// `ReadingPosition.fraction` refuses to refine itself with a guess for exactly this
    /// reason.
    ///
    /// So the line is absent rather than wrong. Android reached this first and wrote it down
    /// at `HomeShelves.pagesRemaining`: "Null, which is the surface saying nothing, rather
    /// than a page count invented from a chapter index." **One clause of `home-screen` goes
    /// unmet by it** — "its progress is visible as well as stated" — and the card still draws
    /// the fill, which is the visible half. Stating the wrong unit is not a way of meeting
    /// the other half.
    static func remainder(of publication: Publication, record: ReadingProgress?) -> HomeRemainder {
        guard let record, !record.isFinished else { return .nothingToSay }

        switch record.position {
        case let .page(index, total):
            return total > 0 ? pagesLeft(max(0, total - index - 1)) : .nothingToSay

        case .listening:
            return .nothingToSay

        case .reflowable:
            let left = max(0, 1 - record.position.fraction)
            if let pages = publication.pageCount, pages > 0 {
                return pagesLeft(Int((left * Double(pages)).rounded()))
            }
            return .percent(Int((left * 100).rounded()))
        }
    }

    /// Nought pages left is not a sentence anyone needs: the publication is on its last page
    /// and about to leave this shelf anyway.
    private static func pagesLeft(_ pages: Int) -> HomeRemainder {
        pages > 0 ? .pages(pages) : .nothingToSay
    }
}
