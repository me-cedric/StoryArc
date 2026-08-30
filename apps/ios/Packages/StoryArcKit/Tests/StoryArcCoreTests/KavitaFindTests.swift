import Testing

@testable import StoryArcCore

/// Searching a Kavita source with the server away.
///
/// `kavita-server`: with the server unreachable "the search falls back to the local cache
/// and states that results are limited to cached content". These are the cases the fallback
/// has to get right, in the order Android's `KavitaFindTest` asserts them.
struct KavitaFindTests {
    private func card(
        _ publication: String,
        series: String,
        seriesId: Int = 1,
        chapter: String = "1",
        people: [String] = [],
        subjects: [String] = []
    ) -> KavitaCard {
        KavitaCard(
            publicationId: publication,
            downloadId: "download-\(publication)",
            sourceId: "s",
            seriesId: seriesId,
            chapterId: 1,
            seriesName: series,
            chapterName: chapter,
            people: people,
            subjects: subjects
        )
    }

    /// A publication indexed from the file, with the values a `ComicInfo.xml` would carry.
    private func fromFile() -> Publication {
        Publication(
            identity: PublicationIdentity(normalizedPath: "/downloads/p1/file.cbz"),
            format: .cbz,
            displayTitle: "File title",
            series: "File series",
            authors: ["File author"],
            year: 1970,
            summary: "What the file says.",
            tags: ["file-tag"],
            origin: .embedded,
            pageCount: 24
        )
    }

    @Test("The server's values replace the file's")
    func serverWins() {
        // `kavita-server`: "the app displays Kavita's values, because the server is the
        // curated source" — and the same values again when the server is unreachable and
        // this card is all that is left of it.
        let described = card("p1", series: "Tidal Reach").applied(to: fromFile())
        #expect(described.series == "Tidal Reach")
        #expect(described.displayTitle == "1")
        #expect(described.origin == .authoritative)
    }

    @Test("A field the card is silent about keeps what the file said")
    func silenceKeepsTheFile() {
        // The server having no summary is not the server saying there is none.
        let bare = KavitaCard(
            publicationId: "p1",
            sourceId: "s",
            seriesId: 7,
            chapterId: 1,
            seriesName: "Tidal Reach",
            chapterName: "The Harbour"
        )
        let described = bare.applied(to: fromFile())
        #expect(described.summary == "What the file says.")
        #expect(described.authors == ["File author"])
        #expect(described.year == 1970)
        #expect(described.tags == ["file-tag"])
    }

    @Test("What the file alone knows survives the overlay")
    func fileFactsSurvive() {
        // The card describes a publication; it does not describe the archive. A page count
        // or a cover path replaced from a card would be the server answering a question it
        // was never asked.
        let described = card("p1", series: "Tidal Reach").applied(to: fromFile())
        #expect(described.pageCount == 24)
        #expect(described.format == fromFile().format)
        #expect(described.id == fromFile().id)
    }

    @Test("An empty query asks for nothing")
    func emptyQuery() {
        #expect(KavitaFind.term("") == nil)
    }

    @Test("A query of only spaces asks for nothing")
    func blankQuery() {
        // A server asked for whitespace answers with its whole library, which reads as a
        // search that matched everything.
        #expect(KavitaFind.term("   ") == nil)
        #expect(KavitaFind.inCache("  ", [card("a", series: "Tidal Reach")]).isEmpty)
    }

    @Test("A series name match is a series hit")
    func seriesMatch() {
        let hits = KavitaFind.inCache("tidal", [card("a", series: "Tidal Reach", seriesId: 7)])
        #expect(hits == [KavitaHit(kind: .series, title: "Tidal Reach", seriesId: 7, downloadId: "download-a")])
    }

    @Test("A chapter name match is a chapter hit")
    func chapterMatch() {
        let hits = KavitaFind.inCache(
            "harbour",
            [card("a", series: "Tidal Reach", seriesId: 7, chapter: "The Harbour")]
        )
        #expect(hits == [KavitaHit(kind: .chapter, title: "The Harbour", seriesId: 7, downloadId: "download-a")])
    }

    @Test("Matching ignores case")
    func caseInsensitive() {
        #expect(KavitaFind.inCache("TIDAL", [card("a", series: "Tidal Reach")]).count == 1)
    }

    @Test("A person match is named after the person, not the series")
    func personMatch() {
        let hits = KavitaFind.inCache(
            "okonkwo",
            [card("a", series: "Tidal Reach", people: ["Ada Okonkwo"])]
        )
        #expect(hits == [KavitaHit(kind: .person, title: "Ada Okonkwo")])
        // Nowhere to go: Kavita answers with the name alone.
        #expect(hits.first?.isOpenable == false)
    }

    @Test("A genre or a tag match is one kind of hit, not two")
    func subjectMatch() {
        let hits = KavitaFind.inCache(
            "horror",
            [card("a", series: "Tidal Reach", subjects: ["Horror", "Cosmic Horror"])]
        )
        #expect(hits.map(\.kind) == [.subject, .subject])
        #expect(hits.map(\.title) == ["Horror", "Cosmic Horror"])
    }

    @Test("One card matching two ways yields one hit of each kind")
    func twoKinds() {
        let hits = KavitaFind.inCache(
            "reach",
            [card("a", series: "Tidal Reach", seriesId: 7, chapter: "Reach for it")]
        )
        #expect(hits.map(\.kind) == [.series, .chapter])
    }

    @Test("Two chapters of one series are one series row")
    func oneRowPerSeries() {
        let hits = KavitaFind.inCache("tidal", [
            card("a", series: "Tidal Reach", seriesId: 7, chapter: "1"),
            card("b", series: "Tidal Reach", seriesId: 7, chapter: "2"),
        ])
        #expect(hits.count == 1)
    }

    @Test("A cached row names the download it opens, not the publication it describes")
    func cachedRowOpens() {
        // Offline a row that cannot be opened is a row that is only there to disappoint —
        // and the two keys are different, which is what made the row inert when it was the
        // publication's.
        let hits = KavitaFind.inCache("tidal", [card("p1", series: "Tidal Reach")])
        #expect(hits.first?.downloadId == "download-p1")
    }

    @Test("A card matching nothing is not a result")
    func noMatch() {
        #expect(KavitaFind.inCache("zzz", [card("a", series: "Tidal Reach")]).isEmpty)
    }

    @Test("Headings come back in the spec's own order, and an empty one is left out")
    func grouping() {
        let hits = KavitaFind.inCache("a", [
            card("a", series: "Tidal Reach", seriesId: 7, chapter: "Harbour", people: ["Ada"]),
        ])
        let groups = KavitaFind.grouped(hits)
        #expect(groups.map(\.kind) == [.series, .chapter, .person])
    }
}
