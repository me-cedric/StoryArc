import Foundation
import Testing

@testable import StoryArcCore

/// What an identifier is, which provider owns it, and where it is asked about.
struct CoverLookupProviderTests {
    @Test("An ISBN is read without the hyphens an OPF writes it with")
    func readsAnIsbn() {
        #expect(CoverIdentifier.isbn(reading: "978-0-14-118776-1") == .isbn("9780141187761"))
        #expect(CoverIdentifier.isbn(reading: "0 14 118776 X") == .isbn("014118776X"))
    }

    @Test("A malformed ISBN is refused rather than put in a URL")
    func refusesAMalformedIsbn() {
        // One request per publication is all `cover-art` allows, so a request that can only
        // fail is the only request that publication would ever get.
        #expect(CoverIdentifier.isbn(reading: "12345") == nil)
        #expect(CoverIdentifier.isbn(reading: "978014118776X") == nil)
        #expect(CoverIdentifier.isbn(reading: "") == nil)
    }

    @Test("A release-group id is a UUID and nothing else")
    func readsAMusicBrainzIdentifier() {
        let value = "B1A9C0E9-D987-4042-AE91-78D6A3267D69"
        #expect(
            CoverIdentifier.musicBrainz(reading: value)
                == .musicBrainzReleaseGroup(value.lowercased())
        )
        #expect(CoverIdentifier.musicBrainz(reading: "not-a-uuid") == nil)
    }

    @Test("An ASIN is ten letters and digits")
    func readsAnAsin() {
        #expect(CoverIdentifier.asin(reading: "b08g9prs1k") == .audibleASIN("B08G9PRS1K"))
        #expect(CoverIdentifier.asin(reading: "B08G9PRS") == nil)
    }

    @Test("Each identifier belongs to exactly one provider")
    func pairsEachIdentifierWithItsProvider() {
        #expect(CoverIdentifier.isbn("9780141187761").provider == .openLibrary)
        #expect(CoverIdentifier.musicBrainzReleaseGroup("x").provider == .coverArtArchive)
        #expect(CoverIdentifier.audibleASIN("B08G9PRS1K").provider == .audnexus)
    }

    @Test("Open Library is asked not to answer with a placeholder")
    func asksOpenLibraryForARealCover() throws {
        // Without `default=false` the service answers a blank grey image with status 200,
        // and the app would store that as the reader's cover and never ask again.
        let url = try #require(CoverLookupRequest.url(for: .isbn("9780141187761")))
        #expect(url.absoluteString.contains("default=false"))
        #expect(url.host() == CoverLookupProvider.openLibrary.host)
    }

    @Test("A request carries the identifier and nothing else")
    func sendsTheIdentifierAndNothingElse() throws {
        // `cover-art`: "it sends the identifier and nothing else: no library listing, no
        // reading history, no device identifier". The URL is the whole request, so the URL
        // is where that is asserted.
        let identifier = CoverIdentifier.audibleASIN("B08G9PRS1K")
        let url = try #require(CoverLookupRequest.url(for: identifier))
        let trailing = url.absoluteString
            .replacingOccurrences(of: "https://api.audnex.us/books/", with: "")
        #expect(trailing == identifier.value)
    }

    @Test("Every provider states a name and a host for the setting to show")
    func namesEveryProvider() {
        for provider in CoverLookupProvider.allCases {
            #expect(!provider.displayName.isEmpty)
            #expect(provider.host.contains("."))
        }
        #expect(CoverLookupProvider.allCases.count == 3)
    }

    @Test("Only Audnexus answers with a document rather than a picture")
    func knowsWhichProviderAnswersWithADocument() {
        #expect(CoverLookupProvider.openLibrary.answersWithImage)
        #expect(CoverLookupProvider.coverArtArchive.answersWithImage)
        #expect(!CoverLookupProvider.audnexus.answersWithImage)
    }
}
