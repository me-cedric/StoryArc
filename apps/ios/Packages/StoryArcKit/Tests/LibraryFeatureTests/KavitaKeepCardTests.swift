import Foundation
import Kavita
import Persistence
import StoryArcCore
import Testing

@testable import LibraryFeature

/// What a keep writes down, which is the whole of *Reading a downloaded Kavita title offline*.
///
/// **These two lines are the feature and nothing was standing behind them.** `KavitaCard`
/// carries `ageRating` and `publicationStatus`; the card store round-trips them; both tables
/// map them; `KavitaCardFacts` draws them. Every one of those is asserted from a card a test
/// built by hand — so `KavitaKeep.card` could be changed to write "the server said nothing"
/// for every keep, every kept chapter would draw neither line on either platform, and the
/// whole iOS suite and every Android suite would still pass.
///
/// This is the one seam where the server's answer becomes the card. Android's
/// `KavitaKeepCardTest` makes the same three claims.
///
/// The metadata is decoded from the wire rather than built, because the interesting absences
/// are wire-shaped: `/api/Series/metadata` answering without `publicationStatus` is what
/// Kavita does for a series that has none, and a status read as zero there is `OnGoing`.
@Suite("Kavita keep card")
struct KavitaKeepCardTests {

    private func metadata(_ json: String) throws -> KavitaMetadata {
        try JSONDecoder().decode(KavitaMetadata.self, from: Data(json.utf8))
    }

    private func subject(_ metadata: KavitaMetadata?) -> KavitaKeep.Subject {
        KavitaKeep.Subject(
            chapter: KavitaChapter(id: 1, number: "1", title: "The Harbour", pages: 8),
            series: KavitaSeries(id: 7, name: "Tidal Reach", libraryId: 3),
            metadata: metadata,
            origin: KavitaOrigin(
                sourceId: "kavita-1",
                libraryId: 3,
                seriesId: 7,
                volumeId: 700,
                chapterId: 1
            ),
            sourceID: nil
        )
    }

    private func card(_ metadata: KavitaMetadata?) -> KavitaCard {
        KavitaKeep.card("p1", downloadId: "kavita:kavita-1:1", subject(metadata))
    }

    @Test("A keep writes down the rating and the status the server stated")
    func statedFieldsAreWrittenDown() throws {
        // Kavita's own numbers: 10 is `Mature 17+` and 2 is `Completed`.
        let kept = card(try metadata(
            #"{"seriesId":7,"ageRating":10,"publicationStatus":2,"releaseYear":2020}"#
        ))

        #expect(kept.ageRating == 10)
        #expect(kept.publicationStatus == 2)
        // Read back through the same two rules the live answer gets, because that is what
        // the page asks the card for.
        #expect(kept.rating == .mature17Plus)
        #expect(kept.status == .completed)
        // And the five that do have somewhere to go still go there.
        #expect(kept.releaseYear == 2020)
    }

    @Test("A keep from an answer that stated neither writes down neither")
    func absentFieldsAreWrittenAsAbsences() throws {
        // The ordinary case: Kavita omits what a series does not have. The two absences are
        // different shapes because Kavita's two enums are — zero is its own `Unknown` rating
        // and its `OnGoing` status — so an absent status has to leave the table entirely.
        let kept = card(try metadata(#"{"seriesId":7,"releaseYear":2020}"#))

        #expect(kept.ageRating == 0)
        #expect(kept.publicationStatus == -1)
        #expect(kept.rating == nil)
        #expect(kept.status == nil)
    }

    @Test("A keep from a server that answered nothing at all writes down neither")
    func noAnswerIsAlsoAnAbsence() {
        // `Subject.metadata` is nil when the metadata call failed. A card with a name and no
        // description is better than no card, and it must still not state a status.
        let kept = card(nil)

        #expect(kept.ageRating == 0)
        #expect(kept.publicationStatus == -1)
        #expect(kept.status == nil)
    }
}
