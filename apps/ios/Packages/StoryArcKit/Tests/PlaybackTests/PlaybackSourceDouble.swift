import Foundation

@testable import Playback
import StoryArcCore

/// The two sources the player has, standing in for their engines.
///
/// `audio-playback` requires that "the surface, the controls and the lock-screen
/// presentation are the same" whichever produced the sound, and `design.md` makes that a
/// structural property rather than a promise: one session object, two implementations,
/// and the surfaces never learn which is behind them. A test can only assert that by
/// driving the *same* assertions over both, which is what ``SourceKind`` is for.
///
/// The difference between them is the one the design calls the thinnest part of the
/// abstraction, and it is the only difference these doubles carry: a narrated file knows
/// how long its parts are and a synthesised voice does not.
enum SourceKind: CaseIterable, Sendable {
    /// A narrated audiobook: three chapters, each of a known length.
    case narrated
    /// A synthesised voice: parts with no duration, skipping by sentence.
    case spoken

    var parts: [PlaybackPart] {
        switch self {
        case .narrated:
            [
                PlaybackPart(index: 0, title: "One", duration: 120),
                PlaybackPart(index: 1, title: "Two", duration: 90),
                PlaybackPart(index: 2, title: "Three", duration: 60),
            ]
        case .spoken:
            [
                PlaybackPart(index: 0, title: "One", duration: nil),
                PlaybackPart(index: 1, title: "Two", duration: nil),
                PlaybackPart(index: 2, title: "Three", duration: nil),
            ]
        }
    }

    var skipUnit: SkipUnit {
        switch self {
        case .narrated: .time
        case .spoken: .sentence
        }
    }
}

/// A source that records what was asked of it and moves when told to.
@MainActor
final class PlaybackSourceDouble: PlaybackSource {
    enum Call: Equatable {
        case play
        case pause
        case stop
        case speed(Double)
        case seek(part: Int, offset: TimeInterval)
        case skip(SkipDirection, TimeInterval)
    }

    private(set) var calls: [Call] = []

    var moved: (@MainActor () -> Void)?
    var ended: (@MainActor () -> Void)?

    let parts: [PlaybackPart]
    let skipUnit: SkipUnit
    var unreadablePartCount: Int
    private(set) var place: PlaybackPlace

    init(_ kind: SourceKind, unreadableParts: Int = 0) {
        parts = kind.parts
        skipUnit = kind.skipUnit
        unreadablePartCount = unreadableParts
        place = PlaybackPlace(partIndex: 0, offset: 0)
    }

    func play() { calls.append(.play) }
    func pause() { calls.append(.pause) }
    func stop() { calls.append(.stop) }
    func setSpeed(_ speed: PlaybackSpeed) { calls.append(.speed(speed.rate)) }

    func seek(toPart index: Int, offset: TimeInterval) {
        calls.append(.seek(part: index, offset: offset))
        place = PlaybackPlace(partIndex: index, offset: offset)
        moved?()
    }

    func skip(_ direction: SkipDirection, by interval: TimeInterval) {
        calls.append(.skip(direction, interval))
    }

    // MARK: - What the engine would do to it

    /// The audio moved, as an engine's own clock would report.
    func advance(toPart index: Int, offset: TimeInterval) {
        place = PlaybackPlace(partIndex: index, offset: offset)
        moved?()
    }

    /// The source ran out on its own — the book ended.
    func runOut() { ended?() }
}

extension Publication {
    /// A publication with nothing in it but a title, for a test that is about the player.
    static func stub(id: String, title: String) -> Publication {
        Publication(
            identity: PublicationIdentity(normalizedPath: "/\(id)"),
            format: .epub,
            displayTitle: title,
            origin: .embedded
        )
    }
}

extension SpokenBook {
    static func stub(id: String, title: String) -> SpokenBook {
        SpokenBook(
            publication: .stub(id: id, title: title),
            url: URL(fileURLWithPath: "/\(id)")
        )
    }
}
