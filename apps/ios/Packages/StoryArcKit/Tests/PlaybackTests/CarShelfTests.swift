import Testing

@testable import Playback

/// The car's list, as a value.
///
/// The counterpart of Android's `CarLibraryTest`, and the same trade: a car screen cannot
/// be driven from a test, so the rules a later change would break most easily are held
/// over the list itself. `audio-playback`'s four car scenarios name three of them — the
/// book in progress is first, each book is offered once, and nothing but audio is offered.
///
/// The fourth scenario, the car's own transport controls, is `NowPlaying`'s and is
/// asserted with the rest of the remote commands. Activating the CarPlay scene needs the
/// `com.apple.developer.carplay-audio` entitlement, which ADR-0011's missing development
/// team also blocks; §12.6 of the task list carries that.
struct CarShelfTests {

    private let seaRoom = SpokenBook.stub(id: "sea-room", title: "Sea Room", format: .m4b)
    private let theSeaWolf = SpokenBook.stub(id: "the-sea-wolf", title: "The Sea Wolf", format: .mp3)
    private let comic = SpokenBook.stub(id: "arc", title: "Arc", format: .cbz)

    /// **The empty case had to be paired with a non-empty one to mean anything.** On its own
    /// it passed against every mutation, an unconditional empty return included: a check that
    /// only ever asks for nothing cannot tell a correct answer from no answer at all.
    @Test("An empty device offers nothing, and a device with a book does not")
    func anEmptyDeviceOffersNothing() {
        #expect(CarShelf.rows(continuing: nil, onDevice: []).isEmpty)
        #expect(!CarShelf.rows(continuing: nil, onDevice: [seaRoom]).isEmpty)
    }

    @Test("The book in progress is the first row a car draws")
    func theBookInProgressIsFirst() {
        let rows = CarShelf.rows(continuing: seaRoom, onDevice: [theSeaWolf, seaRoom])

        #expect(rows.first?.id == seaRoom.id)
    }

    @Test("The book in progress is offered once, not twice")
    func theBookInProgressIsOfferedOnce() {
        let rows = CarShelf.rows(continuing: seaRoom, onDevice: [seaRoom, theSeaWolf])

        #expect(rows.map(\.id) == [seaRoom.id, theSeaWolf.id])
    }

    @Test("Each audiobook on the device appears once")
    func eachBookAppearsOnce() {
        let rows = CarShelf.rows(continuing: nil, onDevice: [seaRoom, theSeaWolf, seaRoom])

        #expect(rows.map(\.id) == [seaRoom.id, theSeaWolf.id])
    }

    /// `audio-playback`: the car surface "offers audiobooks and read-aloud sessions and
    /// nothing else, because a car screen is not a place to browse comics".
    @Test("A comic never reaches a car screen")
    func noComicIsOffered() {
        let rows = CarShelf.rows(continuing: nil, onDevice: [comic, seaRoom])

        #expect(rows.map(\.id) == [seaRoom.id])
    }

    /// The other half of that clause, and the reason the filter is not applied to the first
    /// row: a listener can be in the middle of a book the voice is reading.
    @Test("A book being read aloud is still the book in progress")
    func aSpokenEpubKeepsTheFirstRow() {
        let spoken = SpokenBook.stub(id: "epub", title: "Sea Room", format: .epub)
        let rows = CarShelf.rows(continuing: spoken, onDevice: [seaRoom])

        #expect(rows.map(\.id) == [spoken.id, seaRoom.id])
    }

    /// `audio-playback`: "the list is short and flat, because a car screen is read at a
    /// glance and deep browsing is a driving hazard". Flat means every publication offered
    /// is a row, so the count of rows is the count of books and never a count of nodes.
    @Test("The list is flat, so a row is a book")
    func theListIsFlat() {
        let rows = CarShelf.rows(continuing: seaRoom, onDevice: [theSeaWolf, comic])

        #expect(rows.count == 2)
    }

    @Test("A car row states the title, and the author beneath it")
    func aRowStatesTitleAndAuthor() {
        let rows = CarShelf.rows(continuing: nil, onDevice: [seaRoom])

        #expect(rows.first?.label.title == "Sea Room")
        #expect(rows.first?.label.detail == nil, "a stub carries no author, and no detail is invented")
    }
}
