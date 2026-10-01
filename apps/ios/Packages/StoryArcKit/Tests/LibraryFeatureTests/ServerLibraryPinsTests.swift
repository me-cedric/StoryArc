import Catalogue
import Foundation
import StoryArcCore
import Testing

@testable import LibraryFeature

/// The library read of an OPDS catalogue carries the app's one pin set.
///
/// 11.3: `ServerLibrary`'s catalogue branch used to build an unpinned `OpdsClient`, so a
/// catalogue behind a certificate the reader had already pinned refused the handshake and
/// `try?` turned the refusal into `.none` — the same answer an offline server gives, so
/// nothing ever said a pinned catalogue was the reason the shelf stayed empty.
///
/// This cannot reach the handshake itself without a live TLS server, which nothing else in
/// this suite stands up either — `OpdsTrustTests` asserts the trust decision directly,
/// against certificates with no server behind them. What this proves instead is the wiring
/// a server-side regression here would actually break: that the client the read is about to
/// use is built from the pins handed in, not from a fresh, empty set that would refuse every
/// pin the reader has already accepted.
struct ServerLibraryPinsTests {
    private func page() throws -> CataloguePage {
        let source = Source(displayName: "Library", kind: .opdsCatalog, locator: "https://books.example/feed")
        return try #require(CataloguePage(source: source, credentials: nil))
    }

    @Test func theClientTheCatalogueBranchReadsWithCarriesTheAppsPins() throws {
        let client = ServerLibrary.client(for: try page())
        #expect(client.pins === CertificatePins.app)
    }
}
