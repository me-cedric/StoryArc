import Foundation
import Testing

@testable import LibraryFeature
import StoryArcCore

/// That a count taken from a slice is not stated as a total.
///
/// `library-browsing`: a source that holds more than was read states that it is partial,
/// and "the number shown is never presented as the whole".
///
/// **The number was a lie of omission.** Every source is read in a bounded first helping —
/// sixty series from a Kavita server, one feed page from a catalogue, two hundred files or
/// forty listings from a share — because a library that walked a whole server before
/// drawing anything would leave a reader looking at nothing. The source screen then stated
/// the count as "137 titles", and a reader whose server holds five thousand had no way to
/// tell that from a server that holds 137.
///
/// Android's `SourceSliceTest` asserts the same.
@Suite("A count from a slice")
struct SourceSliceTests {

    private func rows(_ count: Int) -> [Publication] {
        (0..<count).map { index in
            Publication(
                identity: PublicationIdentity(contentDigest: "\(index)"),
                format: .cbz,
                displayTitle: "Row \(index)",
                origin: .inferred
            )
        }
    }

    private var source: Source {
        Source(displayName: "A server", kind: .kavitaServer, locator: "https://x.invalid")
    }

    @Test("A read that reached the end holds nothing back")
    func whole() {
        let slice = SourceSlice.whole(rows(3))

        #expect(!slice.holdsMore)
        #expect(slice.publications.count == 3)
    }

    @Test("A source that gave nothing held nothing back either")
    func nothing() {
        // A server that refused, or one never configured. "Nothing, and there may be more"
        // would put *At least 0 titles* on the screen, which says less than nothing.
        #expect(!SourceSlice.none.holdsMore)
        #expect(SourceSlice.none.publications.isEmpty)
    }

    @Test("The diagnosis says at least when the read stopped at its own limit")
    func partial() {
        let diagnosis = SourceDiagnosis.of(source, itemCount: 137, downloads: [], isPartial: true)

        #expect(diagnosis.isPartial)
        #expect(diagnosis.itemCount == 137)
    }

    @Test("A source read to its end says the plain number")
    func notPartial() {
        // A count that is the whole of a source must not be hedged. *At least 12* for a
        // source that holds 12 teaches a reader to distrust the number.
        #expect(!SourceDiagnosis.of(source, itemCount: 12, downloads: []).isPartial)
    }
}
