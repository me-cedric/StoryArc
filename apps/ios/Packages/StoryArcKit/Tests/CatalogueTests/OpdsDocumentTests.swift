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
    }
}
