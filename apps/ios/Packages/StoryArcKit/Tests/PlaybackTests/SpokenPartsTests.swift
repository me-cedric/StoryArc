import Foundation
import Testing

@testable import Playback

/// What a publication being read aloud is divided into.
///
/// `design.md`'s table: a part is "a chapter marker, or a file" for a narrated audiobook and
/// "a resource in the publication's reading order" for read-aloud. The reading order is the
/// division; the publication's own navigation is the only thing that can *name* it.
///
/// This is the half that can be wrong without a simulator noticing, so it is a value here
/// rather than a loop inside the Readium adapter. The adapter — `SpokenSource` — reads
/// Readium's `readingOrder` and `tableOfContents` and hands them over as strings.
@Suite("Spoken parts")
struct SpokenPartsTests {

    private let order = ["ch1.xhtml", "ch2.xhtml", "ch3.xhtml"]

    @Test("Each resource of the reading order is one part, in order")
    func onePartPerResource() {
        let parts = SpokenParts.of(readingOrder: order, titledBy: [:])
        #expect(parts.map(\.index) == [0, 1, 2])
    }

    @Test("The navigation names the parts it points at")
    func namedByNavigation() {
        let parts = SpokenParts.of(
            readingOrder: order,
            titledBy: ["ch1.xhtml": "Beginnings", "ch3.xhtml": "Endings"]
        )
        #expect(parts.map(\.title) == ["Beginnings", nil, "Endings"])
    }

    /// An entry pointing at an anchor *inside* a resource is one of several and names none
    /// of them — the same rule `EpubReaderModel.currentEntry(in:)` already applies when it
    /// marks the reader's place, and for the same reason: a name that is wrong everywhere is
    /// worse than no name, because nobody can tell which it is. `PlayerCentre` numbers an
    /// unnamed part, so the listener sees "Part 2" rather than a chapter they are not in.
    @Test("An anchor inside a resource does not name the whole of it")
    func anchorsNameNothing() {
        let parts = SpokenParts.of(
            readingOrder: ["book.xhtml"],
            titledBy: ["book.xhtml#ch1": "One", "book.xhtml#ch2": "Two"]
        )
        #expect(parts.map(\.title) == [nil])
    }

    /// `audio-playback`: a publication with no chapter markers "lists its parts in playing
    /// order instead, rather than showing an empty list". A one-resource EPUB is that case,
    /// and it reports one part rather than none — the same rule `AudiobookReader` follows for
    /// an unchaptered file, so `ChapterListView` never has an empty case on either side.
    @Test("A publication of one resource is one part, never none")
    func neverEmpty() {
        #expect(SpokenParts.of(readingOrder: ["only.xhtml"], titledBy: [:]).count == 1)
    }

    /// **No duration, and that is the load-bearing part.** `design.md`: a synthesised voice
    /// does not know how long it will speak, and "shows position without a total rather than
    /// inventing one". A zero here would draw a scrub control pinned at the end of a bar the
    /// listener could then drag.
    @Test("A spoken part carries no duration at all")
    func noDuration() {
        let parts = SpokenParts.of(readingOrder: order, titledBy: ["ch1.xhtml": "Beginnings"])
        #expect(parts.allSatisfy { $0.duration == nil })
    }

    /// A publication that declares no reading order has nothing to speak, and the caller
    /// must not be handed a session with no parts in it.
    @Test("An empty reading order is an empty part list, not one blank part")
    func emptyStaysEmpty() {
        #expect(SpokenParts.of(readingOrder: [], titledBy: [:]).isEmpty)
    }
}
