import Foundation
import Testing

@testable import LibraryFeature
import Catalogue
import Kavita

/// What "Add catalogue" does with what was pasted into it.
///
/// Rank 7 of the 30 August security review: a Kavita OPDS URL pasted into the *generic*
/// catalogue sheet became an OPDS source. Kavita's OPDS URL carries the reader's
/// full-privilege API key in its path, the fetch therefore succeeded with no 401 and no
/// prompt, and the whole key-bearing URL was written to `UserDefaults` in the clear — where
/// the secure store was never consulted at all.
///
/// Android's `CatalogueTargetTest` asserts the same cases in the same order.
@Suite("Catalogue target")
struct CatalogueTargetTests {

    @Test("A pasted Kavita OPDS URL is a Kavita server, not a feed")
    func aKavitaOpdsUrlIsNotAFeed() throws {
        let target = CatalogueTarget.of("https://kavita.example/api/opds/97b1f0e2c4")

        guard case let .kavita(address) = target else {
            Issue.record("expected a Kavita server, got \(target)")
            return
        }
        #expect(address.base.absoluteString == "https://kavita.example")
        #expect(address.apiKey == "97b1f0e2c4")
    }

    @Test("The key never reaches the feed path, whatever the OPDS parser would make of it")
    func theOpdsParserWouldHaveAcceptedIt() throws {
        // The reason order matters: asked on its own, the catalogue's own address parser
        // completes that URL into a perfectly good feed URL, key and all. Anything that
        // asks it first has already lost the key into the catalogue flow.
        let typed = "https://kavita.example/api/opds/97b1f0e2c4"
        #expect(OpdsDocument.address(from: typed) != nil)
        #expect(CatalogueTarget.of(typed) != .feed(try #require(OpdsDocument.address(from: typed))))
    }

    @Test("A Kavita URL behind a reverse-proxy subpath is recognised too")
    func aReverseProxySubpath() throws {
        let target = CatalogueTarget.of("https://home.example/books/api/opds/key")

        guard case let .kavita(address) = target else {
            Issue.record("expected a Kavita server, got \(target)")
            return
        }
        #expect(address.base.absoluteString == "https://home.example/books")
    }

    @Test("An ordinary catalogue URL is still a feed")
    func anOrdinaryCatalogue() throws {
        let target = CatalogueTarget.of("https://calibre.example/opds")
        #expect(target == .feed(try #require(URL(string: "https://calibre.example/opds"))))
    }

    @Test("Something that is not an address at all is neither")
    func nonsense() {
        #expect(CatalogueTarget.of("   ") == .unusable)
    }

    @Test("A locator never carries a password the reader typed into the address")
    func userinfoIsStrippedFromTheLocator() throws {
        // `https://user:password@host/feed` is a working credential written as an address,
        // and `URLSession` authenticates from it — so the fetch succeeds and, before this,
        // the password was written to preferences as part of the locator.
        let url = try #require(URL(string: "https://reader:hunter2@books.example/opds"))
        #expect(CatalogueTarget.storableLocator(for: url) == "https://books.example/opds")
    }

    @Test("An address with nothing secret in it is stored unchanged")
    func anOrdinaryLocatorIsUntouched() throws {
        let url = try #require(URL(string: "https://books.example/opds?shelf=comics"))
        #expect(CatalogueTarget.storableLocator(for: url) == "https://books.example/opds?shelf=comics")
    }
}
