import Foundation
import Testing

@testable import StoryArcCore

/// The address the system browser is handed, and what it does not carry.
struct CoverWebSearchTests {
    @Test("The search is for the title, the author and the word cover")
    func searchesForTheTitle() throws {
        let url = try #require(CoverWebSearch.url(title: "Fine Print", author: "Ada Lovelace"))
        let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "q" }?.value)
        #expect(query == "Fine Print Ada Lovelace cover")
    }

    @Test("A title with no author still searches")
    func searchesWithoutAnAuthor() throws {
        let url = try #require(CoverWebSearch.url(title: "Book 03"))
        let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "q" }?.value)
        #expect(query == "Book 03 cover")
    }

    @Test("An empty title opens nothing")
    func refusesAnEmptyTitle() {
        // A search for nothing lands on an engine's front page, and handing a reader that is
        // worse than not offering the action at all.
        #expect(CoverWebSearch.url(title: "   ") == nil)
    }

    @Test("The hand-off goes to an engine that keeps no profile")
    func handsOffToAPrivateEngine() throws {
        // The app has no analytics and no account. Choosing an engine that builds a profile
        // against a signed-in identity would undo that at the one moment the app picks the
        // address.
        let url = try #require(CoverWebSearch.url(title: "Fine Print"))
        #expect(url.host() == "duckduckgo.com")
        #expect(url.scheme == "https")
    }

    @Test("The image results are what opens")
    func opensTheImageResults() throws {
        let url = try #require(CoverWebSearch.url(title: "Fine Print"))
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems)
        #expect(items.contains { $0.name == "iax" && $0.value == "images" })
        #expect(items.contains { $0.name == "ia" && $0.value == "images" })
    }
}
