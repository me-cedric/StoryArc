import Foundation
import Testing

@testable import LibraryFeature
import StoryArcCore

/// What *more from this library* puts on the screen.
///
/// `library-browsing`, *More from a source than the library holds*: the publications a
/// source holds beyond the first slice "are rendered by the same grid, the same cells and
/// the same publication page as everything else". The footer used to open the source's own
/// browser, which draws a catalogue with cells of its own, so these rows are the half of
/// that clause a host test can hold: one source's publications, in the library's own
/// arrangement, collapsed into the library's own rows.
///
/// Android's `SourceShelfTest` asserts the same four cases.
@Suite("The shelf of one source")
struct SourceShelfTests {

    private func issue(_ title: String, from sourceID: UUID?, series: String? = nil) -> Publication {
        Publication(
            identity: PublicationIdentity(normalizedPath: "/\(title)"),
            format: .cbz,
            displayTitle: title,
            series: series,
            origin: .embedded,
            sourceID: sourceID
        )
    }

    @Test("Only the library that was asked for")
    func oneSourceOnly() {
        let asked = UUID()
        let other = UUID()
        let shelf = sourceShelfMembers(
            of: asked,
            in: [issue("mine", from: asked), issue("theirs", from: other)]
        )

        #expect(shelf.map(\.displayTitle) == ["mine"])
    }

    @Test("A publication no source claims belongs to no library's shelf")
    func unattributed() {
        // ``LibraryScope/contains(_:)`` is the rule, and it is the library's own: a file
        // another app handed over came from somewhere the reader never configured, and
        // attributing it to whichever source is open would be a guess.
        let asked = UUID()

        #expect(sourceShelfMembers(of: asked, in: [issue("dropped in", from: nil)]).isEmpty)
    }

    @Test("In the library's own arrangement, not the order the pages arrived in")
    func arranged() {
        // The later pages are adopted as they come back from the server, so adoption order
        // is the order one server answered in. The shelf's default is title, ascending.
        let asked = UUID()
        let shelf = sourceShelfMembers(
            of: asked,
            in: [issue("Zephyr", from: asked), issue("Ashfall", from: asked)]
        )

        #expect(shelf.map(\.displayTitle) == ["Ashfall", "Zephyr"])
    }

    @Test("A series is one cell here too, because it is the library's own grid")
    func seriesCollapses() {
        let asked = UUID()
        let rows = LibraryRows.of(
            sourceShelfMembers(
                of: asked,
                in: [
                    issue("Lantern 1", from: asked, series: "Lantern"),
                    issue("Lantern 2", from: asked, series: "Lantern"),
                    issue("Solo", from: asked)
                ]
            )
        )

        #expect(rows.count == 2)
        #expect(rows.first { $0.count == 2 } != nil)
    }
}
