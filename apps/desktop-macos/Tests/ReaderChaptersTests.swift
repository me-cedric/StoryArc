import Testing

@testable import StoryArc

/// `comic-reader`, *Chapter navigation*, *Chapters in the browser*, *No chapter markers* and
/// *Reaching the end*, over the Mac copies of the iOS rules.
@Suite("Reader chapters")
struct ReaderChaptersTests {
    private let markers = ReaderChapters.markers(starts: [8, 0, 4], titles: [4: "The Long Way", 8: "Saga #12"])

    @Test("Previous and next chapter move within the publication, and run out at its ends")
    func navigation() {
        #expect(ReaderChapters.nextStart(from: 0, markers: markers) == 4)
        #expect(ReaderChapters.nextStart(from: 5, markers: markers) == 8)
        #expect(ReaderChapters.nextStart(from: 8, markers: markers) == nil)
        #expect(ReaderChapters.previousStart(from: 6, markers: markers) == 4)
        #expect(ReaderChapters.previousStart(from: 0, markers: markers) == nil)
    }

    @Test("The browser names the chapter in force, by its title or its position, and nothing without markers")
    func labels() {
        #expect(ReaderChapters.label(at: 2, markers: markers) == .position(1))
        #expect(ReaderChapters.label(at: 5, markers: markers) == .named("The Long Way"))
        #expect(ReaderChapters.label(at: 3, markers: []) == nil)
        #expect(ReaderChapters.label(at: 3, markers: [ChapterMarker(index: 5, title: nil)]) == nil)
    }

    @Test("A chapter's first page has a badge with the issue number its title gives, else its position")
    func badges() {
        #expect(ReaderChapters.badge(at: 0, markers: markers) == "#1")
        #expect(ReaderChapters.badge(at: 4, markers: markers) == "#2")
        #expect(ReaderChapters.badge(at: 8, markers: markers) == "#12")
        #expect(ReaderChapters.badge(at: 5, markers: markers) == nil)
    }

    @Test("The slider has a tick at each chapter's start, and none with one page")
    func ticks() {
        #expect(ReaderChapters.tickFractions(markers: markers, pageCount: 9) == [0, 0.5, 1])
        #expect(ReaderChapters.tickFractions(markers: markers, pageCount: 1).isEmpty)
    }

    @Test("Only a forward turn from the last slot reaches the end")
    func end() {
        #expect(ReaderEnd.isPastEnd(slot: 4, step: 1, slotCount: 5))
        #expect(!ReaderEnd.isPastEnd(slot: 3, step: 1, slotCount: 5))
        #expect(!ReaderEnd.isPastEnd(slot: 4, step: -1, slotCount: 5))
        #expect(!ReaderEnd.isPastEnd(slot: 0, step: 1, slotCount: 0))
    }
}
