import AppKit
import Testing

@testable import StoryArc

extension WindowWalks {
    /// The library window's destinations, driven inside the app.
    ///
    /// `navigation-shell`, *Each destination remembers where the reader had got to*: a page
    /// pushed in Library is still there after a visit to Home. The window's title is the
    /// page on show, which is what the walk reads.
    @MainActor
    @Suite("Library walk")
    struct LibraryWalkTests {
        @Test("A publication's page pushed in Library is still there after a visit to Home")
        func destinationsRemember() async throws {
            let library = try await Walk.fixtureLibrary()
            let window = try #require(ShellWalk.libraryWindow())
            let publication = try #require(Walk.publication(named: "natural-sort", in: library))
            defer { library.navigationRequest = .go(.home) }

            library.navigationRequest = .go(.library)
            _ = await Walk.until { library.navigationRequest == nil ? true : nil }
            library.navigationRequest = .root
            _ = await Walk.until { library.navigationRequest == nil ? true : nil }
            library.navigationRequest = .details(publicationID: publication.id)
            let pushed = await Walk.until { window.title == publication.displayTitle ? true : nil }
            #expect(pushed == true, "the page did not open: the title is \(window.title)")

            library.navigationRequest = .go(.home)
            let home = await Walk.until { window.title != publication.displayTitle ? window.title : nil }
            #expect(home != nil, "Home did not take the window")

            library.navigationRequest = .go(.library)
            let back = await Walk.until { window.title == publication.displayTitle ? true : nil }
            #expect(back == true, "Library came back at \(window.title), not at the page")

            library.navigationRequest = .root
            _ = await Walk.until { window.title != publication.displayTitle ? true : nil }
        }
    }
}
