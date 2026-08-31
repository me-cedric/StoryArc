public import StoryArcCore

/// One position a Kavita server has not been told about, and the record that position
/// becomes once it has.
public struct KavitaOwed: Sendable, Equatable {
    /// The chapter Kavita keys its progress row on.
    public let chapterId: Int

    /// Kavita's `pageNum` — the page the reader is on, counted from zero.
    public let pageNum: Int

    /// What to write locally once the server has taken the position, carrying the stamp
    /// that says it is no longer only this device's opinion.
    ///
    /// Held back rather than written with the rest: a position the server never received is
    /// not synchronised, and calling it so would make the next merge treat an untouched
    /// local record as agreed with a server that has never heard of it.
    public let settled: ReadingProgress

    public init(chapterId: Int, pageNum: Int, settled: ReadingProgress) {
        self.chapterId = chapterId
        self.pageNum = pageNum
        self.settled = settled
    }
}

/// Sorting a merge into the two halves only a server can settle: what it must be told, and
/// what a local record may then call synchronised.
///
/// The merge table itself is ``ProgressMerge``'s and the sorting into piles is
/// ``ProgressPull``'s. What is added here is the part that is specific to Kavita and still
/// pure — a chapter's `pagesRead` is a position, a position is a `pageNum`, and an exchange
/// that actually happened is a stamp on the record. Pure so that both platforms can assert
/// the same cases without a server, which is the whole reason the table lives outside a view
/// model. Android's `KavitaExchange` is the same three answers.
public struct KavitaExchange: Sendable, Equatable {
    /// Records to write now. Every one the server already holds carries the stamp.
    public let toSave: [ReadingProgress]

    /// Positions the server is behind on, in the order the merge produced them.
    public let owed: [KavitaOwed]

    public init(toSave: [ReadingProgress] = [], owed: [KavitaOwed] = []) {
        self.toSave = toSave
        self.owed = owed
    }
}

public extension KavitaExchange {

    /// The position a chapter's `pagesRead` describes.
    ///
    /// Kavita counts pages *read*; a position names the page the reader is *on*, so the two
    /// differ by one. Clamped at both ends rather than trusted: the count arrives over the
    /// network from a server that may be mid-scan, and a page index past the end of a
    /// chapter is a resume point that opens nothing.
    static func position(readingTo pagesRead: Int, of pages: Int) -> ReadingPosition {
        guard pages > 0 else { return .page(index: 0, of: 0) }
        return .page(index: min(max(0, pagesRead - 1), pages - 1), of: pages)
    }

    /// The `pageNum` a server is told, from a stored position and the chapter's length.
    ///
    /// A reflowable position is carried across by its fraction, because that is the only
    /// part of it that means anything to a server counting pages — ADR-0006. A one-page
    /// chapter has one answer and no arithmetic to do.
    static func pageNumber(of position: ReadingPosition, in pages: Int) -> Int {
        guard pages > 1 else { return 0 }
        switch position {
        case let .page(index, _):
            return min(max(0, index), pages - 1)
        case let .reflowable(progression, _):
            let page = (min(1, max(0, progression)) * Double(pages - 1)).rounded()
            return min(max(0, Int(page)), pages - 1)
        }
    }

    /// The record a source has just taken this position from, or agreed it with.
    ///
    /// The stamp is the whole point: ``ProgressMerge`` tells "changed since the last sync"
    /// from "untouched" by comparing against it, and nothing wrote it, so every record
    /// looked changed and the quiet adopt could never happen.
    static func settled(_ record: ReadingProgress) -> ReadingProgress {
        var stamped = record
        stamped.syncedPosition = record.position
        return stamped
    }

    /// Sorts one merge against the chapters it came from.
    ///
    /// A record with no chapter behind it is left out of what is owed rather than guessed
    /// at: the position is real, but without a chapter there is no row on the server to put
    /// it in.
    static func of(
        _ pull: ProgressPull,
        against chapters: [String: KavitaChapter]
    ) -> KavitaExchange {
        let owed = pull.toPush.compactMap { record -> KavitaOwed? in
            guard let chapter = chapters[record.identity.stableID], chapter.pages > 0 else {
                return nil
            }
            return KavitaOwed(
                chapterId: chapter.id,
                pageNum: pageNumber(of: record.position, in: chapter.pages),
                settled: settled(record)
            )
        }

        // A record that is still owed is written as it stands and stamped later, when the
        // server has actually taken it. Everything else in `toSave` came from the server, so
        // the server holds it by definition.
        let owing = Set(owed.map(\.settled.identity.stableID))
        let toSave = pull.toSave.map { record in
            owing.contains(record.identity.stableID) ? record : settled(record)
        }

        return KavitaExchange(toSave: toSave, owed: owed)
    }
}
