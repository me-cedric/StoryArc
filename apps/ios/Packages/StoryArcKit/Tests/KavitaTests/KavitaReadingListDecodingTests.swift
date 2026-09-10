import Foundation
import Testing

@testable import Kavita

/// What a reading list and its entries carry off the wire, beyond a title.
///
/// `collections-and-reading-lists` asks a list to say "how many entries are finished and
/// where the user's position is", and asks a shelf with no cover of its own to be drawn from
/// what it holds "unless the user sets a specific one". Both answers are already in the
/// payload and both were being discarded on the way in.
///
/// The payloads below are the shape a live Kavita **0.9.1.4** answered with on 2026-09-10 —
/// every field name, every type, and the two nulls it sends. The names and the ids are
/// invented, because a fixture in a public repository should not be a reader's own library.
///
/// Android's `KavitaReadingListDecodingTest` makes the same three claims.
struct KavitaReadingListDecodingTests {

    /// One list, as `ReadingList/lists` answers: an unlocked cover and a count.
    private static let lists = #"""
    [{"id":8,"title":"The long crossover","summary":"Read in publication order",
      "promoted":false,"coverImageLocked":false,"coverImage":"readinglist8.png",
      "primaryColor":"#20303f","secondaryColor":"#c8b28a","itemCount":77,
      "startingYear":2005,"startingMonth":4,"endingYear":2006,"endingMonth":1,
      "ageRating":0,"ownerUserName":"ada","sourcePath":null,"downloadUrl":null,
      "shaHash":null,"provider":0,"lastSyncCheckUtc":null,"lastSyncedUtc":null,
      "totalItemsAtImport":77,"tags":[],"canSync":false}]
    """#

    /// Three entries, as `ReadingList/items` answers: unread, part-read, finished.
    private static let items = #"""
    [{"id":1,"order":0,"chapterId":3103,"seriesId":312,"seriesName":"Lantern Green",
      "seriesSortName":"Lantern Green","seriesFormat":0,"pagesRead":0,"pagesTotal":22,
      "chapterNumber":"43","volumeNumber":"0","chapterTitleName":"Issue #43",
      "volumeId":516,"libraryId":2,"title":"Issue #43","libraryType":0,
      "libraryName":"Comics","releaseDate":"2005-04-01T00:00:00","readingListId":8,
      "lastReadingProgressUtc":null,"fileSize":41943040,"summary":null,
      "isSpecial":false,"chapter":{},"volume":{}},
     {"id":2,"order":1,"chapterId":3104,"seriesId":312,"seriesName":"Lantern Green",
      "seriesSortName":"Lantern Green","seriesFormat":0,"pagesRead":11,"pagesTotal":22,
      "chapterNumber":"44","volumeNumber":"0","chapterTitleName":"Issue #44",
      "volumeId":516,"libraryId":2,"title":"Issue #44","libraryType":0,
      "libraryName":"Comics","releaseDate":"2005-05-01T00:00:00","readingListId":8,
      "lastReadingProgressUtc":"2026-09-01T18:04:51","fileSize":41943040,"summary":null,
      "isSpecial":false,"chapter":{},"volume":{}},
     {"id":3,"order":2,"chapterId":3105,"seriesId":312,"seriesName":"Lantern Green",
      "seriesSortName":"Lantern Green","seriesFormat":0,"pagesRead":22,"pagesTotal":22,
      "chapterNumber":"45","volumeNumber":"0","chapterTitleName":"Issue #45",
      "volumeId":516,"libraryId":2,"title":"Issue #45","libraryType":0,
      "libraryName":"Comics","releaseDate":"2005-06-01T00:00:00","readingListId":8,
      "lastReadingProgressUtc":"2026-09-02T09:11:02","fileSize":41943040,"summary":null,
      "isSpecial":false,"chapter":{},"volume":{}}]
    """#

    private func client(answering body: String) throws -> KavitaClient {
        let host = "\(UUID().uuidString).example"
        let configuration = KavitaStub.session(host: host) { request in
            if request.url?.path().contains("authenticate") == true {
                return .response(status: 200, body: Data(#"{"username":"ada","token":"t"}"#.utf8))
            }
            return .response(status: 200, body: Data(body.utf8))
        }
        let address = try #require(KavitaAddress.from(base: "https://\(host)", apiKey: "key"))
        return KavitaClient(address: address, configuration: configuration)
    }

    @Test("An entry carries the two numbers its read state is made of")
    func entryCarriesItsProgress() async throws {
        let entries = try await client(answering: Self.items).readingListItems(8)

        #expect(entries.map(\.pagesRead) == [0, 11, 22])
        #expect(entries.map(\.pagesTotal) == [22, 22, 22])
    }

    @Test("A list carries the cover it has and whether a reader locked it")
    func listCarriesItsCover() async throws {
        let shelf = try #require(try await client(answering: Self.lists).readingLists().first)

        #expect(shelf.coverImage == "readinglist8.png")
        // An unlocked cover is the case where the app composites its own.
        #expect(shelf.coverImageLocked == false)
        #expect(shelf.itemCount == 77)
    }

    @Test("A server that says nothing about a cover leaves the shelf compositing")
    func olderServerLeavesTheDefaults() {
        // An older Kavita sends neither field. The defaults are what that means: no cover of
        // its own, nothing locked.
        let bare = KavitaReadingList(id: 8, title: "The long crossover")

        #expect(bare.coverImage == nil)
        #expect(bare.coverImageLocked == false)
        #expect(bare.itemCount == 0)
    }
}
