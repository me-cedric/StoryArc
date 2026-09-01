import Foundation
import Testing

@testable import StoryArcCore

/// Where a listener stopped, as a third kind of reading position.
///
/// `reading-progress` asks an audiobook's position to be "an offset in time within a named
/// part", and asks a publication that has been both read and listened to for **one** position
/// rather than two. So it is a `ReadingPosition` — the currency the merge, the finished rule
/// and every shelf already deal in — and not a second store beside it.
///
/// **The two rules this case must not break, and both are asserted below.** `fraction` is
/// what `matches` compares by and what ADR-0006's merge table is written in, so a listening
/// position has to land on the same 0…1 scale as a page and a progression. And the store keeps
/// the enum as JSON, so a record written before this case existed has to decode unchanged.
///
/// Android mirrors the case in `:core:model` and pins the same table in
/// `ListeningPositionTest`.
@Suite("Listening position")
struct ListeningPositionTests {

    // MARK: - The fraction

    /// The honest answer with no duration: the part index over the part count, and **not** an
    /// estimate refined by a guess. `design.md`: a read-aloud session has no true duration, so
    /// "`fraction` must answer without one, and the honest answer is the part index over the
    /// part count — never an estimate presented as a measurement".
    @Test("With no total, the fraction is the part over the part count")
    func withoutATotal() {
        let position = ReadingPosition.listening(part: 2, partCount: 8, offset: 41, of: nil)
        #expect(position.fraction == 0.25)
    }

    /// With a duration, the offset refines it inside the part — which is the same shape
    /// `TotalProgression.resolve` uses for a reflowable resource.
    @Test("With a total, the offset refines it inside the part")
    func withATotal() {
        let half = ReadingPosition.listening(part: 1, partCount: 4, offset: 30, of: 60)
        #expect(half.fraction == 0.375)
    }

    @Test("The start of the first part is nought")
    func theStart() {
        #expect(ReadingPosition.listening(part: 0, partCount: 3, offset: 0, of: 600).fraction == 0)
    }

    /// The end of the last part is the end of the book, which is what makes finishing by
    /// listening reachable by the same rule that finishes a comic on its last page.
    @Test("The end of the last part is one")
    func theEnd() {
        let ended = ReadingPosition.listening(part: 2, partCount: 3, offset: 600, of: 600)
        #expect(ended.fraction == 1)
    }

    /// Nothing outside 0…1 can leave here, whatever a store or a damaged file hands in — the
    /// merge compares fractions, and one above the end would win every conflict for ever.
    @Test(
        "Nonsense clamps rather than escaping",
        arguments: [
            ReadingPosition.listening(part: 9, partCount: 3, offset: 0, of: nil),
            ReadingPosition.listening(part: 0, partCount: 3, offset: 9_999, of: 60),
            ReadingPosition.listening(part: -4, partCount: 3, offset: -9, of: 60),
            ReadingPosition.listening(part: 0, partCount: 0, offset: 5, of: 60),
            ReadingPosition.listening(part: 1, partCount: 4, offset: 5, of: 0),
        ]
    )
    func clamped(_ position: ReadingPosition) {
        #expect(position.fraction >= 0 && position.fraction <= 1)
    }

    // MARK: - The two rules it must not break

    /// `matches` compares by fraction, so a listening position stored and read back has to
    /// equal itself — and has to be able to equal the page or progression it was stored from.
    /// Without that, ADR-0006's first row (remote ahead, local untouched, adopt quietly) is
    /// unreachable for an audiobook, exactly as it was unreachable on Android while `matches`
    /// compared by case.
    @Test("It matches on the same scale as the other two kinds")
    func matchesAcrossKinds() {
        let listening = ReadingPosition.listening(part: 1, partCount: 4, offset: 0, of: 60)
        #expect(listening.fraction == 0.25)
        #expect(listening.matches(.reflowable(progression: 0.25, locator: "{}")))
        #expect(listening.matches(.page(index: 1, of: 5)))
        #expect(!listening.matches(.listening(part: 2, partCount: 4, offset: 0, of: 60)))
    }

    /// **The store keeps `positionData` as JSON of the enum**, which is what lets
    /// `StoryArcCore` stay free of SwiftData. A record written before this case existed has to
    /// decode unchanged, because the new case never appears in it. The reverse is not true and
    /// does not need to be: there is no older build in anybody's hands.
    @Test("A record written before this case existed still decodes")
    func oldRecordsStillDecode() throws {
        for older in [
            ReadingPosition.page(index: 12, of: 40),
            ReadingPosition.reflowable(progression: 0.3, locator: #"{"href":"ch1.xhtml"}"#),
        ] {
            let written = try JSONEncoder().encode(older)
            #expect(try JSONDecoder().decode(ReadingPosition.self, from: written) == older)
        }
    }

    @Test("And a listening position survives the same round trip")
    func roundTrips() throws {
        let position = ReadingPosition.listening(part: 3, partCount: 9, offset: 61.5, of: 240)
        let written = try JSONEncoder().encode(position)
        #expect(try JSONDecoder().decode(ReadingPosition.self, from: written) == position)
    }
}
