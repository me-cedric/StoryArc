import Foundation
import Testing

@testable import Kavita

/// Kavita's two integer fields, and the rules for turning them into something a reader reads.
///
/// The table is copied from `Kavita.Models/Entities/Enums/AgeRating.cs` and
/// `PublicationStatus.cs`, and the age rating is parental-control adjacent: an off-by-one shows
/// a reader *Teen* where the server said *Mature 17+*. So every number is asserted, not a
/// sample of them.
///
/// **The Android mirror asserts the same table**, in
/// `core/kavita/src/test/kotlin/app/storyarc/core/kavita/KavitaRatingsTest.kt`. Two apps that
/// disagree about a parental control is the failure worth guarding, and neither suite can see
/// the other — so both name the same source file and both list every case, which is the most a
/// per-platform test can do about it.
struct KavitaRatingsTests {

    /// Every rating Kavita defines, at the number Kavita gives it.
    ///
    /// Written out rather than derived from the enum, because deriving it from the thing under
    /// test asserts only that the code equals itself. This list came from Kavita's source.
    @Test("Every age rating maps to Kavita's own number and its own label")
    func everyRating() {
        // A named row rather than a three-member tuple: the linter refuses those, and a
        // table about parental controls reads better with its columns named anyway.
        struct Row {
            let number: Int
            let rating: KavitaAgeRating
            let label: String
        }
        let table = [
            Row(number: -1, rating: .notApplicable, label: "Not Applicable"),
            Row(number: 0, rating: .unknown, label: "Unknown"),
            Row(number: 1, rating: .ratingPending, label: "Rating Pending"),
            Row(number: 2, rating: .earlyChildhood, label: "Early Childhood"),
            Row(number: 3, rating: .everyone, label: "Everyone"),
            Row(number: 4, rating: .ratedG, label: "G"),
            Row(number: 5, rating: .everyone10Plus, label: "Everyone 10+"),
            Row(number: 6, rating: .pg, label: "PG"),
            Row(number: 7, rating: .kidsToAdults, label: "Kids to Adults"),
            Row(number: 8, rating: .teen, label: "Teen"),
            Row(number: 9, rating: .mature15Plus, label: "MA15+"),
            Row(number: 10, rating: .mature17Plus, label: "Mature 17+"),
            Row(number: 11, rating: .mature, label: "M"),
            Row(number: 12, rating: .r18Plus, label: "R18+"),
            Row(number: 13, rating: .adultsOnly, label: "Adults Only 18+"),
            Row(number: 14, rating: .x18Plus, label: "X18+"),
        ]
        #expect(table.count == KavitaAgeRating.allCases.count, "a case was added without a row here")
        for entry in table {
            #expect(KavitaAgeRating(rawValue: entry.number) == entry.rating, "\(entry.number) is not \(entry.rating)")
            #expect(entry.rating.label == entry.label)
        }
    }

    /// Kavita adds cases — v2.1 added several to this very enum — and the next number it adds
    /// must read as "no rating" rather than as the nearest one this app happens to know.
    @Test("A number no version of this app knows is not a rating", arguments: [15, 99, -2, Int.max])
    func unknownNumberIsNoRating(number: Int) {
        #expect(KavitaAgeRating(rawValue: number) == nil)
        #expect(metadata(ageRating: number).rating == nil)
    }

    /// `Unknown` is Kavita's default for a series nobody has rated and `Not Applicable` is a
    /// profile setting that leaked into the same enum. Drawing either would tell a parent this
    /// book had been assessed when nobody has assessed it.
    @Test("Kavita's two non-ratings are not ratings")
    func nonRatings() {
        #expect(KavitaAgeRating.unknown.isStated == false)
        #expect(KavitaAgeRating.notApplicable.isStated == false)
        #expect(metadata(ageRating: 0).rating == nil)
        #expect(metadata(ageRating: -1).rating == nil)
        // And everything else is.
        for rating in KavitaAgeRating.allCases where rating != .unknown && rating != .notApplicable {
            #expect(rating.isStated, "\(rating) should be a stated rating")
        }
    }

    @Test("Every publication status maps to its own case")
    func everyStatus() {
        let table: [(Int, KavitaPublicationStatus)] = [
            (0, .ongoing), (1, .hiatus), (2, .completed), (3, .cancelled), (4, .ended),
        ]
        #expect(table.count == KavitaPublicationStatus.allCases.count, "a case was added without a row here")
        for (number, expected) in table {
            #expect(KavitaPublicationStatus(rawValue: number) == expected)
        }
    }

    @Test("An unrecognised status is left unsaid rather than guessed", arguments: [5, 42, -1])
    func unknownStatus(number: Int) {
        #expect(KavitaPublicationStatus(rawValue: number) == nil)
        #expect(metadata(publicationStatus: number).status == nil)
    }

    /// The fields have to survive the decode the client actually does, which is the half that
    /// was missing: the model had no `ageRating` and no `publicationStatus`, so a server that
    /// sent both was parsed into a value that could not carry either.
    ///
    /// **The absence is not a default, and the first version of this test said it was.** It
    /// asserted `absent.publicationStatus == 0` and `absent.status == .ongoing`, with a comment
    /// arguing that "an absent field and a server that never set one read alike, which is what
    /// they are". They are not. Kavita's zero there is `OnGoing` — a state a curator chose —
    /// so reading an omitted field as zero makes the app state that the series is running on
    /// the server's behalf. A reviewer found it; the field is optional now and this test
    /// asserts the correction rather than the mistake.
    ///
    /// `ageRating` genuinely does default: Kavita's own zero is `Unknown`, which already means
    /// nobody has rated it. Two fields, two shapes, and the difference is the whole point.
    @Test("The two fields survive the decode, and an absent status is not a stated one")
    func decoding() throws {
        let sent = try decode(#"{ "seriesId": 7, "ageRating": 10, "publicationStatus": 2 }"#)
        #expect(sent.rating == .mature17Plus)
        #expect(sent.status == .completed)

        let absent = try decode(#"{ "seriesId": 7 }"#)
        #expect(absent.ageRating == 0, "Kavita's own zero, which is Unknown")
        #expect(absent.publicationStatus == nil, "no number at all, rather than OnGoing")
        #expect(absent.rating == nil, "Unknown is not a rating")
        #expect(absent.status == nil, "a server that said nothing has not said OnGoing")

        // And a server that really does say OnGoing still reads as OnGoing.
        let stated = try decode(#"{ "seriesId": 7, "publicationStatus": 0 }"#)
        #expect(stated.status == .ongoing)
    }

    // MARK: - Private

    private func decode(_ json: String) throws -> KavitaMetadata {
        try JSONDecoder().decode(KavitaMetadata.self, from: Data(json.utf8))
    }

    private func metadata(ageRating: Int = 0, publicationStatus: Int = 0) -> KavitaMetadata {
        // Through the decoder, because that is the only way this type is ever built.
        let json = #"{ "seriesId": 1, "ageRating": \#(ageRating), "publicationStatus": \#(publicationStatus) }"#
        // A fixture this test wrote itself; a throw here is this test being wrong.
        // swiftlint:disable:next force_try
        return try! decode(json)
    }
}
