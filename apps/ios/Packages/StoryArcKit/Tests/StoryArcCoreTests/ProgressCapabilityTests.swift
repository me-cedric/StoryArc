import Foundation
import Testing

@testable import StoryArcCore

/// Which sources can hold a reading position, and which three have to say they cannot.
///
/// `reading-progress`' *Source cannot store progress*: "progress is kept locally only, and
/// the source detail screen states that progress for it does not sync". The sentence was
/// never said on either platform, and this is the decision it turns on. Android's
/// `ProgressCapabilityTest` asserts the same four cases.
@Suite("A source states whether it can hold a reading position")
struct ProgressCapabilityTests {

    @Test("Kavita is the one source that keeps a position of its own")
    func onlyKavitaSyncs() {
        // Not a preference: Kavita is the only one of the four with somewhere to put a
        // position. `KavitaClient.report(_:)` posts one to `Reader/progress` and
        // `continuePoint(ofSeries:)` reads one back; no other source kind has either half.
        #expect(SourceKind.kavitaServer.syncsReadingProgress)
    }

    @Test("A folder, a share and an OPDS catalogue keep nothing")
    func theOtherThreeDoNot() {
        // A folder and a share are files on a disk with nowhere to write a position to, and
        // OPDS is a catalogue format that has no notion of one. All three are situations the
        // reader must be told about rather than left to assume from the word "sync".
        #expect(!SourceKind.localFolder.syncsReadingProgress)
        #expect(!SourceKind.networkShare.syncsReadingProgress)
        #expect(!SourceKind.opdsCatalog.syncsReadingProgress)
    }

    @Test("Exactly one of the four syncs, so the other three all state it")
    func oneOfFour() {
        // What keeps a *fifth* kind out of silence is not this assertion. The property is a
        // `switch` used as an expression, so a new case is a compile error rather than a
        // quiet `false` — a guarantee no test can fail on, which is why it is claimed here
        // and not in the name above. This pins the answer for the four kinds that exist,
        // and it is the assertion that breaks if a case is moved to the wrong arm.
        #expect(SourceKind.allCases.filter(\.syncsReadingProgress) == [.kavitaServer])
    }
}
