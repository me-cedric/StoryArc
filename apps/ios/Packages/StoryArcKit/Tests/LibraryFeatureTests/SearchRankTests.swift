import Testing

@testable import LibraryFeature
@testable import StoryArcCore

/// How one answer is ordered, asserted against the same table as Android's `SearchRankTest`.
///
/// `library-browsing` asks for "one ranked list". These are the cases that say what ranked
/// means, including the one the whole design turns on: a remote row that answers better than
/// a local row is above it, and where they answer equally the local one wins.
///
/// Case for case on both platforms, per ADR-0001. Add a case here, add it there.
@Suite("Search rank")
struct SearchRankTests {

    private func held(_ title: String, kind: MatchKind = .publication) -> FoundRow {
        FoundRow(
            result: SearchResult(kind: kind, title: title, publicationID: title),
            origin: .thisDevice
        )
    }

    private func away(
        _ title: String,
        kind: MatchKind = .publication,
        from source: String = "server"
    ) -> FoundRow {
        FoundRow(
            result: SearchResult(
                kind: kind,
                title: title,
                route: SearchRoute(sourceID: source, key: title)
            ),
            origin: .library(id: source, name: source)
        )
    }

    @Test("The five tiers, from the title that is the term to the title that is not in it")
    func tiers() {
        let strength = { (title: String) in
            SearchRank.strength(ofFolded: SearchRank.fold(title), forFolded: "bone")
        }
        #expect(strength("Bone") == .exact)
        #expect(strength("Bone Companion") == .start)
        #expect(strength("The Bone Orchard") == .word)
        #expect(strength("Carbone") == .within)
        #expect(strength("Ada Lovelace") == .elsewhere)
    }

    @Test("Case and accents are not part of the question")
    func folding() {
        let strength = { (title: String, term: String) in
            SearchRank.strength(ofFolded: SearchRank.fold(title), forFolded: SearchRank.fold(term))
        }
        #expect(strength("Café Noir", "cafe") == .start)
        #expect(strength("CAFÉ", "café") == .exact)
        #expect(strength("Élan", "elan") == .exact)
    }

    @Test("A word begins after punctuation as well as after a space")
    func punctuationStartsAWord() {
        let strength = { (title: String, term: String) in
            SearchRank.strength(ofFolded: SearchRank.fold(title), forFolded: SearchRank.fold(term))
        }
        #expect(strength("Vol.2 Bone", "2") == .word)
        #expect(strength("d’Artagnan", "artagnan") == .word)
    }

    @Test("A server's better match outranks the device's worse one")
    func questionBeatsPlace() {
        let ordered = SearchRank.ordered([held("Carbone"), away("Bone")], for: "bone")
        #expect(ordered.map(\.result.title) == ["Bone", "Carbone"])
    }

    @Test("Where two rows answer equally well, the one that opens now wins")
    func placeBreaksTheTie() {
        let ordered = SearchRank.ordered([away("Bone"), held("Bone")], for: "bone")
        #expect(ordered.map(\.origin) == [.thisDevice, .library(id: "server", name: "server")])
    }

    @Test("At equal strength the shorter title is the fuller answer")
    func shorterFirst() {
        let ordered = SearchRank.ordered(
            [away("Bone Companion"), away("Bone Up")],
            for: "bone"
        )
        #expect(ordered.map(\.result.title) == ["Bone Up", "Bone Companion"])
    }

    @Test("Rows equal on every other key still have one fixed order")
    func totalOrder() {
        let ordered = SearchRank.ordered([away("Bone Bb"), away("Bone Aa")], for: "bone")
        #expect(ordered.map(\.result.title) == ["Bone Aa", "Bone Bb"])
    }

    @Test("The heading a row sits under is not a ranking key")
    func kindDoesNotRank() {
        // A series that is the term is above a title that merely contains it, and the two
        // land under different headings — which `SearchListing.groups` decides, not this.
        let ordered = SearchRank.ordered(
            [away("Carbone", kind: .publication), away("Bone", kind: .series)],
            for: "bone"
        )
        #expect(ordered.map(\.result.kind) == [.series, .publication])
    }

    @Test("An empty term ranks nothing above anything")
    func emptyTerm() {
        let ordered = SearchRank.ordered([away("Bb"), held("Aa")], for: "")
        #expect(ordered.map(\.result.title) == ["Aa", "Bb"])
    }
}
