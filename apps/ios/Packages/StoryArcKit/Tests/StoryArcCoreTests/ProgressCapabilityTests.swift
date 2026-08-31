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
        // Not a preference: `KavitaSync` is the only code in either app that pushes or
        // pulls a position, so this list is the list of sources that have a mechanism.
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

    @Test("Exactly one of the four syncs, so a fifth kind cannot default into silence")
    func oneOfFour() {
        // The same guard `isBrowsable` carries: the property is a `switch` over every case,
        // so a new kind fails to compile rather than being quietly assumed to sync — which
        // would drop the sentence for it and let a reader assume their place is safe.
        #expect(SourceKind.allCases.filter(\.syncsReadingProgress) == [.kavitaServer])
    }
}
