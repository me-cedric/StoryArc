import Foundation
import Testing

@testable import StoryArcCore

/// Which addresses a publication is allowed to send the reader to.
///
/// A book is untrusted input. `<a href="someapp://do?x=y">Continue reading →</a>` under
/// innocuous link text launches whatever registered that scheme with the parameters the
/// book chose, and the reader never sees where they were going.
///
/// Android's `ExternalLinkTest` asserts the same cases in the same order.
struct ExternalLinkTests {
    private func url(_ string: String) throws -> URL {
        try #require(URL(string: string))
    }

    @Test func aWebAddressIsOfferedWithItsHostNamed() throws {
        let leaving = try #require(ExternalLink(url: url("https://example.com/notes/1")))
        #expect(leaving.host == "example.com")
        #expect(leaving.url.absoluteString == "https://example.com/notes/1")
    }

    @Test func cleartextIsStillTheReadersToRefuse() throws {
        // Not a security decision this app makes for them: a link to a plain-HTTP page is
        // an ordinary web page, and the host is shown either way.
        let leaving = try #require(ExternalLink(url: url("http://nas.local/index.html")))
        #expect(leaving.host == "nas.local")
    }

    @Test func aWwwPrefixIsShownAsTheReaderWouldReadIt() throws {
        let leaving = try #require(ExternalLink(url: url("https://www.example.com/x")))
        #expect(leaving.host == "example.com")
    }

    @Test func anythingThatIsNotTheWebIsDropped() throws {
        #expect(ExternalLink(url: try url("someinstalledapp://action?param=chosen")) == nil)
        #expect(ExternalLink(url: try url("tel:+15551234567")) == nil)
        #expect(ExternalLink(url: try url("sms:+15551234567")) == nil)
        #expect(ExternalLink(url: try url("mailto:reader@example.com")) == nil)
        #expect(ExternalLink(url: try url("facetime:reader@example.com")) == nil)
        #expect(ExternalLink(url: try url("file:///etc/hosts")) == nil)
        #expect(ExternalLink(url: try url("javascript:alert(1)")) == nil)
    }

    @Test func anAddressWithNoHostIsNotSomewhereToGo() throws {
        #expect(ExternalLink(url: try url("https:///nowhere")) == nil)
    }
}
