import Foundation
import Testing

@testable import Catalogue
@testable import StoryArcCore

/// How a title is asked about, and how each of the three answers is read.
struct CoverTitleSearchTests {
    @Test("Open Library is asked by title and author, for three fields")
    func buildsTheOpenLibraryRequest() throws {
        let request = try #require(
            CoverTitleSearch.request(.openLibrary, title: "Fine Print", author: "Ada")
        )
        let url = try #require(request.url)
        let items = try #require(
            URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        )
        #expect(items.contains { $0.name == "title" && $0.value == "Fine Print" })
        #expect(items.contains { $0.name == "author" && $0.value == "Ada" })
        #expect(items.contains { $0.name == "fields" && $0.value == "title,author_name,cover_i" })
    }

    @Test("AniList and MangaUpdates are asked by POST, with the title in the body")
    func buildsThePostRequests() throws {
        for provider in [CoverTitleProvider.aniList, .mangaUpdates] {
            let request = try #require(CoverTitleSearch.request(provider, title: "Nausicaa"))
            #expect(request.httpMethod == "POST")
            #expect(request.url?.host() == provider.host)
            let body = try #require(request.httpBody)
            #expect(String(bytes: body, encoding: .utf8)?.contains("Nausicaa") == true)
        }
    }

    @Test("An empty title asks nobody")
    func refusesAnEmptyTitle() {
        for provider in CoverTitleProvider.allCases {
            #expect(CoverTitleSearch.request(provider, title: " ") == nil)
        }
    }

    @Test("Open Library's documents become candidates, and a coverless one does not")
    func readsOpenLibraryCandidates() {
        // A document with no `cover_i` has no picture, so it is not a candidate however well
        // its title matches.
        let body = """
        {"docs":[{"title":"Fine Print","author_name":["Ada"],"cover_i":42},
                 {"title":"Fine Print, again","author_name":["Ada"]}]}
        """
        let found = CoverTitleSearch.candidates(in: Data(body.utf8), from: .openLibrary)

        #expect(found.count == 1)
        #expect(found.first?.title == "Fine Print")
        #expect(found.first?.subtitle == "Ada")
        #expect(
            found.first?.imageURL.absoluteString
                == "https://covers.openlibrary.org/b/id/42-L.jpg"
        )
    }

    @Test("AniList's media become candidates, English title first")
    func readsAniListCandidates() {
        let body = """
        {"data":{"Page":{"media":[
          {"title":{"romaji":"Kaze no Tani","english":"Valley of the Wind"},
           "coverImage":{"large":"https://art.example/1.jpg"}}]}}}
        """
        let found = CoverTitleSearch.candidates(in: Data(body.utf8), from: .aniList)

        #expect(found.count == 1)
        #expect(found.first?.title == "Valley of the Wind")
        #expect(found.first?.provider == .aniList)
    }

    @Test("MangaUpdates' records become candidates")
    func readsMangaUpdatesCandidates() {
        let body = """
        {"results":[{"record":{"title":"Nausicaa",
          "image":{"url":{"original":"https://art.example/2.jpg"}}}}]}
        """
        let found = CoverTitleSearch.candidates(in: Data(body.utf8), from: .mangaUpdates)

        #expect(found.count == 1)
        #expect(found.first?.imageURL.absoluteString == "https://art.example/2.jpg")
    }

    @Test("A nonsense answer reads as no candidates rather than as an error")
    func readsNonsenseAsNothing() {
        // A provider that answers nonsense has not answered, and `cover-art` says an
        // unanswered lookup leaves the publication with the cover it had.
        for provider in CoverTitleProvider.allCases {
            #expect(CoverTitleSearch.candidates(in: Data("not json".utf8), from: provider).isEmpty)
        }
    }

    @Test("Every title provider states a name and a host")
    func namesEveryTitleProvider() {
        for provider in CoverTitleProvider.allCases {
            #expect(!provider.displayName.isEmpty)
            #expect(provider.host.contains("."))
        }
    }
}
