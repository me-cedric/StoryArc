import Foundation
import Testing

@testable import LibraryFeature
import StoryArcCore

/// The provenance line is one whole sentence per state, and the second place is named
/// (`one-vocabulary-in-four-languages` 4.6, `close-the-audited-gaps` 15.10, O19).
///
/// Asked of `PublicationProvenance.sentence`, which the view draws, so reverting the view to
/// two joined clauses fails here. The four languages are pinned by
/// `ReconciledWordingTests` over the catalogue files, because `swift test` on this host
/// resolves `String(localized:)` against the system language; what this suite proves is which
/// key each state asks for, by the name it puts in.
@Suite("The provenance line is one sentence per state")
struct ProvenanceSentenceTests {

    private func provenance(
        _ home: PublicationProvenance.Home,
        _ availability: PublicationProvenance.Availability,
        alsoIn: String? = nil
    ) -> PublicationProvenance {
        PublicationProvenance(home: home, availability: availability, alsoIn: alsoIn)
    }

    @Test("Each state is its own sentence, and a library state names the library")
    func eachStateIsItsOwnSentence() {
        let states: [(PublicationProvenance, String)] = [
            (provenance(.thisDevice, .offline), "detail.provenance.device"),
            (provenance(.library(name: "Attic"), .now), "detail.provenance.library"),
            (provenance(.library(name: "Attic"), .notHere), "detail.provenance.notHere"),
            (provenance(.library(name: "Attic"), .notAnswering), "detail.provenance.away"),
            (provenance(.unattributed, .notHere), "detail.provenance.unattributed"),
        ]

        let sentences = states.map(\.0.sentence)
        #expect(Set(sentences).count == states.count, "two states read the same: \(sentences)")

        for (state, key) in states {
            let name = "Attic"
            let expected: String
            switch key {
            case "detail.provenance.library": expected = DetailStrings.text("detail.provenance.library \(name)")
            case "detail.provenance.notHere": expected = DetailStrings.text("detail.provenance.notHere \(name)")
            case "detail.provenance.away": expected = DetailStrings.text("detail.provenance.away \(name)")
            case "detail.provenance.device": expected = DetailStrings.text("detail.provenance.device")
            default: expected = DetailStrings.text("detail.provenance.unattributed")
            }
            #expect(state.sentence == expected, "\(key) is not what the \(state.availability) state reads")
        }

        for sentence in sentences.dropFirst().prefix(3) {
            #expect(sentence.contains("Attic"), "a library state that does not name its library: \(sentence)")
        }
    }

    @Test("The second place is a sentence that names it, and is absent when there is none")
    func theSecondPlaceIsNamed() {
        let also = provenance(.thisDevice, .offline, alsoIn: "Cellar")
        let sentence = also.alsoInSentence
        #expect(sentence?.contains("Cellar") == true, "read: \(sentence ?? "nothing")")
        #expect(also.sentence.contains("Cellar") == false)

        #expect(provenance(.thisDevice, .offline).alsoInSentence == nil)
    }
}
