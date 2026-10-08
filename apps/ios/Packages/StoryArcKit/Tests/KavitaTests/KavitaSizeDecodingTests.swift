import Foundation
import Testing

@testable import Kavita

/// What a chapter and a reading-list entry say about how large their file is.
///
/// Task 7.8 of `close-the-audited-gaps`: a whole-shelf download states its size before it
/// starts, so the size has to come off the wire. Both numbers are in the payloads a live
/// Kavita 0.9.1.4 answers with — `ReadingListItemDto.fileSize` and `ChapterDto.files[].bytes`
/// — and both were dropped on the way in. A server that states none reads as zero, which the
/// shelf download treats as "not stated" and never as an empty file. Android's
/// `KavitaSizeDecodingTest` makes the same four claims.
struct KavitaSizeDecodingTests {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    @Test("An entry states the size of its file")
    func entryStatesItsSize() throws {
        let entry = try decode(
            [KavitaReadingListItem].self,
            #"[{"id":1,"order":0,"chapterId":3103,"seriesId":312,"pagesTotal":22,"fileSize":41943040}]"#
        ).first

        #expect(entry?.fileSize == 41_943_040)
    }

    @Test("An entry that states no size reads as zero")
    func entryWithoutASize() throws {
        let entry = try decode(
            [KavitaReadingListItem].self, #"[{"id":1,"order":0,"chapterId":3103,"seriesId":312}]"#
        ).first

        #expect(entry?.fileSize == 0)
    }

    @Test("A chapter's size is the sum of its files")
    func chapterSumsItsFiles() throws {
        let chapter = try decode(
            KavitaChapter.self,
            #"{"id":3103,"pages":22,"files":[{"id":1,"bytes":1000,"pages":10},{"id":2,"bytes":2500,"pages":12}]}"#
        )

        #expect(chapter.fileBytes == 3_500)
    }

    @Test("A chapter with no files states no size")
    func chapterWithoutFiles() throws {
        #expect(try decode(KavitaChapter.self, #"{"id":3103}"#).fileBytes == 0)
    }
}
