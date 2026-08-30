import Foundation
import Testing

@testable import Catalogue

/// What a typed address becomes.
///
/// The one piece of the add-a-catalogue flow that is not a network call, and the one that
/// decides whether a password travels in the clear.
struct OpdsAddressTests {
    @Test func aBareHostBecomesHttps() throws {
        let url = try #require(OpdsDocument.address(from: "library.example.com/opds"))
        #expect(url.absoluteString == "https://library.example.com/opds")
    }

    @Test func anExplicitSchemeIsKept() throws {
        // A reader who typed `http` meant it — usually a server on their own network. The
        // default is the secure one; the override is theirs.
        let url = try #require(OpdsDocument.address(from: "http://nas.local:8080/opds"))
        #expect(url.absoluteString == "http://nas.local:8080/opds")
    }

    @Test func surroundingSpaceIsIgnored() throws {
        let url = try #require(OpdsDocument.address(from: "  komga.local/opds  "))
        #expect(url.absoluteString == "https://komga.local/opds")
    }

    @Test func somethingWithNoHostIsNotAnAddress() {
        #expect(OpdsDocument.address(from: "") == nil)
        #expect(OpdsDocument.address(from: "   ") == nil)
        #expect(OpdsDocument.address(from: "https://") == nil)
        #expect(OpdsDocument.address(from: "not a host at all") == nil)
    }
}

/// Which failures are worth trying again.
///
/// `offline-downloads` retries a failed download three times. Retrying one that cannot
/// succeed spends a reader's data to arrive at the same answer.
struct OpdsTransienceTests {
    @Test func aServerHavingAMomentIsWorthRetrying() {
        #expect(OpdsError.http(status: 500).isTransient)
        #expect(OpdsError.http(status: 503).isTransient)
        #expect(OpdsError.http(status: 408).isTransient)
        #expect(OpdsError.http(status: 429).isTransient)
        #expect(OpdsError.empty.isTransient)
    }

    @Test func anAnswerThatWillNotChangeIsNot() {
        #expect(!OpdsError.http(status: 404).isTransient)
        #expect(!OpdsError.http(status: 403).isTransient)
        #expect(!OpdsError.unauthorized(scheme: .basic).isTransient)
        #expect(!OpdsError.notAFeed(received: .html).isTransient)
        #expect(!OpdsError.malformed(reason: "bad XML").isTransient)
        // An address this app refuses is not one it will change its mind about.
        #expect(!OpdsError.refusedAddress.isTransient)
    }
}

/// What a feed's own hrefs are allowed to become.
///
/// The scheme is judged where the href is *resolved*, not where it is fetched: an absolute
/// `file:` or `ftp:` href replaces the base entirely, and everything downstream — the cover
/// load, the download, the next page — then works from an address nothing checked.
///
/// Android's `OpdsResolutionTest` asserts the same cases in the same order.
struct OpdsResolutionTests {
    private func base() throws -> URL {
        try #require(URL(string: "https://library.example/opds/"))
    }

    @Test func aRelativeHrefResolvesAgainstTheFeed() throws {
        let resolved = try #require(OpdsDocument.resolve("unread", relativeTo: base()))
        #expect(resolved.absoluteString == "https://library.example/opds/unread")
    }

    @Test func anAbsoluteHttpHrefIsKept() throws {
        let base = try base()
        let resolved = try #require(OpdsDocument.resolve("http://nas.local/1.jpg", relativeTo: base))
        #expect(resolved.absoluteString == "http://nas.local/1.jpg")
    }

    @Test func anHrefWithAnyOtherSchemeResolvesToNothing() throws {
        let base = try base()
        #expect(OpdsDocument.resolve("file:///etc/hosts", relativeTo: base) == nil)
        #expect(OpdsDocument.resolve("ftp://library.example/x", relativeTo: base) == nil)
        #expect(OpdsDocument.resolve("javascript:alert(1)", relativeTo: base) == nil)
    }

    @Test func aSearchTemplateIsHeldToTheSameSchemes() throws {
        let base = try base()
        #expect(OpdsDocument.resolveTemplate("file:///x?q={searchTerms}", relativeTo: base) == nil)
        let kept = try #require(OpdsDocument.resolveTemplate("search?q={searchTerms}", relativeTo: base))
        #expect(kept == "https://library.example/opds/search?q={searchTerms}")
    }
}
