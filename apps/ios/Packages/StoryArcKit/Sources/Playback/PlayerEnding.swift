public import Foundation

/// How the last session ended, kept past the teardown that clears ``PlayerCentre/book``.
///
/// The finished surface reads it: task 7.2's next-in-series offer needs the book, owner answer
/// O12 needs the count of parts that did not play, and `close-the-audited-gaps` 23.6 with owner
/// answer O21 needs to know whether the last part failed. A failed ending is not a finished
/// book: the position stays at the failed part, and the listener decides.
public struct PlayerEnding: Sendable, Equatable {
    public let book: SpokenBook

    /// How many of the book's parts could not be played.
    public let unreadableParts: Int

    /// What a listener's own "Mark as finished" writes. `nil` unless the last part failed.
    let failedAt: ReachedListening?

    /// The listener has marked a failed ending finished.
    var markedFinished = false

    init(book: SpokenBook, unreadableParts: Int, failedAt: ReachedListening?) {
        self.book = book
        self.unreadableParts = unreadableParts
        self.failedAt = failedAt
    }

    /// Whether the last part failed, so the book is not recorded as finished.
    public var endedOnFailure: Bool { failedAt != nil }
}

extension PlayerCentre {

    /// What the session just did, read before ``PlayerCentre/finish(with:)`` clears it.
    func endingNow(of book: SpokenBook) -> PlayerEnding {
        let failed = source?.endedOnFailure == true
        return PlayerEnding(
            book: book,
            unreadableParts: unreadablePartCount,
            failedAt: failed
                ? ReachedListening(book: book, position: position(at: place), isFinished: true)
                : nil
        )
    }
}

public extension PlayerCentre {

    /// The book that just ran out, or `nil` for a session that stopped any other way.
    var lastFinished: SpokenBook? { ending?.book }

    /// How many of that book's parts could not be played. Task 2.5, owner answer O12.
    var unreadableAtEnd: Int { ending?.unreadableParts ?? 0 }

    /// Whether the book ran out on a failed part, so it is not recorded as finished.
    var endedOnFailure: Bool { ending?.endedOnFailure == true }

    /// Whether the finished surface offers "Mark as finished". Owner answer O21.
    var canMarkFinished: Bool {
        guard let ending else { return false }
        return ending.endedOnFailure && !ending.markedFinished
    }

    /// Whether a failed ending has been marked finished by the listener.
    var markedFinishedByHand: Bool { ending?.markedFinished == true }

    /// The listener's decision that a failed ending counts as finished.
    ///
    /// Writes one record at the position the failed part left, with the finished flag set. A
    /// second call writes nothing.
    func markFinished() {
        guard canMarkFinished, let record = ending?.failedAt else { return }
        ending?.markedFinished = true
        onRecord?(record)
    }
}
