import Testing

@testable import Playback

/// Task 16.3: a car or a lock screen's next-track and previous-track buttons move a narrated
/// book by a chapter, not by the fixed-interval seconds the skip-by-time buttons already send.
///
/// `NowPlaying.addTargets()` reaches ``PlayerCentre/moveToAdjacentPart(_:)`` for exactly this
/// reason, and this is the part of that wiring a host test can drive without the
/// `MPRemoteCommandCenter` singleton — see `TransportCommandsTests` for the sibling half, which
/// of the two commands wires enable at all.
///
/// **Proved able to fail**, per AGENTS.md §5: changing `partIndex + (direction == .forward ? 1
/// : -1)` to always add 1 failed *Previous moves to the part before* by name. Reverted.
@MainActor
@Suite("Moving to the next or previous part")
struct MoveToAdjacentPartTests {

    private func narratedBook() -> (PlayerCentre, PlaybackSourceDouble) {
        let centre = PlayerCentre()
        let source = PlaybackSourceDouble(.narrated)
        centre.begin(.stub(id: "sea-room", title: "Sea Room", format: .m4b), source: source)
        return (centre, source)
    }

    @Test("Next moves to the part after")
    func nextMovesForward() {
        let (centre, source) = narratedBook()

        centre.moveToAdjacentPart(.forward)

        #expect(source.place.partIndex == 1)
    }

    @Test("Previous moves to the part before")
    func previousMovesBack() {
        let (centre, source) = narratedBook()
        centre.play(part: 2)

        centre.moveToAdjacentPart(.back)

        #expect(source.place.partIndex == 1)
    }

    @Test("Previous on the first part does nothing: there is nowhere before it")
    func previousOnTheFirstPartIsIgnored() {
        let (centre, source) = narratedBook()

        centre.moveToAdjacentPart(.back)

        #expect(source.place.partIndex == 0)
    }

    @Test("Next on the last part does nothing: there is nowhere after it")
    func nextOnTheLastPartIsIgnored() {
        let (centre, source) = narratedBook()
        centre.play(part: 2)

        centre.moveToAdjacentPart(.forward)

        #expect(source.place.partIndex == 2)
    }
}
