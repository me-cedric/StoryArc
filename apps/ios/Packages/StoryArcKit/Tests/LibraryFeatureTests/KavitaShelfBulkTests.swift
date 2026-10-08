import Foundation
import Testing

import Kavita
@testable import LibraryFeature

/// Task 7.8 of `close-the-audited-gaps`: a server's collection or reading list is downloaded
/// and marked read as a whole, with its count and size stated first and a ten-second undo on
/// the mark. Android's `KavitaShelfBulkTest` is the twin of this file.
struct KavitaShelfBulkTests {

    private struct Row {
        let chapter: Int
        let read: Int
        let size: Int

        init(_ chapter: Int, _ read: Int, _ size: Int) {
            (self.chapter, self.read, self.size) = (chapter, read, size)
        }
    }

    private func entries(_ rows: [Row]) throws -> [KavitaReadingListItem] {
        let json = rows.map { row in
            """
            {"id":\(row.chapter),"order":\(row.chapter),"chapterId":\(row.chapter),"seriesId":1,
             "seriesName":"Lantern","title":"Issue #\(row.chapter)","pagesRead":\(row.read),
             "pagesTotal":20,"volumeId":100,"libraryId":2,"fileSize":\(row.size)}
            """
        }.joined(separator: ",")
        return try JSONDecoder().decode([KavitaReadingListItem].self, from: Data("[\(json)]".utf8))
    }

    private func items() throws -> [KavitaReadingListItem] {
        try entries([Row(11, 0, 1_000), Row(12, 5, 2_000), Row(13, 20, 3_000)])
    }

    private final class Recorder<Value: Sendable>: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [Value] = []

        func add(_ value: Value) {
            lock.lock()
            values.append(value)
            lock.unlock()
        }

        var value: [Value] {
            lock.lock()
            defer { lock.unlock() }
            return values
        }
    }

    // MARK: Download

    @Test("The count stated is the count of chapters not already on the device")
    func countExcludesWhatIsKept() throws {
        let ask = KavitaShelfBulk.downloadAsk(
            KavitaShelfBulk.chapters(of: try items()), kept: [11]
        )

        #expect(ask?.count == 2)
        #expect(ask?.chapters.map(\.chapter.id) == [12, 13])
    }

    @Test("Everything already kept states nothing to ask")
    func allKeptAsksNothing() throws {
        #expect(KavitaShelfBulk.downloadAsk(KavitaShelfBulk.chapters(of: try items()), kept: [11, 12, 13]) == nil)
    }

    @Test("The size is the sum when every chapter states one, a floor when some do not, and none when none do")
    func sizeInThreeWays() throws {
        let all = KavitaShelfBulk.chapters(of: try items())
        let some = KavitaShelfBulk.chapters(of: try entries([Row(11, 0, 1_000), Row(12, 0, 0)]))
        let none = KavitaShelfBulk.chapters(of: try entries([Row(11, 0, 0)]))

        #expect(KavitaShelfBulk.downloadAsk(all, kept: [])?.size == .known(6_000))
        #expect(KavitaShelfBulk.downloadAsk(some, kept: [])?.size == .atLeast(1_000))
        #expect(KavitaShelfBulk.downloadAsk(none, kept: [])?.size == .unstated)
    }

    @Test("The chapters queued are exactly the chapters the reader was told about")
    func queuedIsStated() async throws {
        let ask = try #require(
            KavitaShelfBulk.downloadAsk(KavitaShelfBulk.chapters(of: try items()), kept: [12])
        )
        let queued = Recorder<Int>()

        let kept = await KavitaShelfBulk.download(ask) { each in
            queued.add(each.chapter.id)
            return true
        }

        #expect(queued.value.count == ask.count)
        #expect(queued.value.sorted() == ask.chapters.map(\.chapter.id).sorted())
        #expect(kept == ask.count)
    }

    // MARK: Mark

    @Test("A mark changes only the chapters not already in that state, and the undo is those same chapters")
    func markAndUndo() async throws {
        let chapters = KavitaShelfBulk.chapters(of: try items())
        let moving = KavitaShelfBulk.changing(chapters, read: true)
        let sent = Recorder<String>()

        await KavitaShelfBulk.mark(moving, read: true) { each, read in sent.add("\(each.chapter.id) \(read)") }
        let undo = KavitaMarkUndo(chapters: moving, read: true)
        await KavitaShelfBulk.mark(undo.chapters, read: !undo.read) { each, read in
            sent.add("\(each.chapter.id) \(read)")
        }

        #expect(sent.value == ["11 true", "12 true", "11 false", "12 false"])
    }

    // MARK: A collection

    @Test("A collection holds the chapters of its series, and a series the server cannot read makes it unreadable")
    func collectionChapters() async throws {
        let series = [
            KavitaSeries(id: 1, name: "Lantern", libraryId: 2),
            KavitaSeries(id: 2, name: "Harbour", libraryId: 2),
        ]
        let volumes: [Int: [KavitaVolume]] = [
            1: [KavitaVolume(id: 100, number: 1, chapters: [KavitaChapter(id: 11, number: "1", pages: 20)])],
            2: [KavitaVolume(id: 200, number: 1, chapters: [KavitaChapter(id: 21, number: "1", fileBytes: 500)])],
        ]
        struct Unanswered: Error {}

        let whole = await KavitaShelfBulk.chapters(of: series) { volumes[$0] ?? [] }
        let broken = await KavitaShelfBulk.chapters(of: series) { id in
            guard id != 2 else { throw Unanswered() }
            return volumes[id] ?? []
        }

        #expect(whole?.map(\.chapter.id) == [11, 21])
        #expect(whole?.last?.bytes == 500)
        #expect(broken == nil, "A count over part of a collection was stated.")
    }

    @Test("An empty shelf is asked again, and a server that does not answer leaves nothing to act on")
    func emptyShelfIsAskedAgain() async throws {
        let rows = try items()
        let asked = Recorder<Int>()
        struct Unanswered: Error {}

        let shown = await KavitaShelfBulk.held(rows, askingAgain: {
            asked.add(1)
            return []
        })
        let answered = await KavitaShelfBulk.held([KavitaReadingListItem](), askingAgain: {
            asked.add(1)
            return rows
        })
        let silent = await KavitaShelfBulk.held([KavitaReadingListItem](), askingAgain: { throw Unanswered() })

        #expect(shown?.map(\.chapterId) == [11, 12, 13])
        #expect(answered?.map(\.chapterId) == [11, 12, 13])
        #expect(asked.value.count == 1, "A shelf already on screen was asked for again.")
        #expect(silent == nil, "An unanswered shelf was taken as an empty one.")
    }

    // MARK: The placement

    private func source(_ name: String) throws -> String {
        var directory = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 { directory.deleteLastPathComponent() }
        let path = directory.appendingPathComponent("Sources/LibraryFeature/\(name)").path
        let text = try #require(
            try? String(contentsOfFile: path, encoding: .utf8),
            "\(path) could not be read. A guard that cannot find what it guards passes for ever."
        )
        return text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    @Test("Both server shelf screens place the whole-shelf actions")
    func bothScreensPlaceTheActions() throws {
        let views = try source("KavitaShelfViews.swift")
        let split = try #require(views.range(of: "struct KavitaListView"))

        #expect(String(views[..<split.lowerBound]).contains(".kavitaShelfBulkActions("),
                "The collection screen does not place the whole-shelf actions.")
        #expect(String(views[split.lowerBound...]).contains(".kavitaShelfBulkActions("),
                "The list screen does not place the whole-shelf actions.")
        // An empty screen is also what a server that did not answer leaves.
        #expect(String(views[..<split.lowerBound]).contains("KavitaShelfBulk.held("),
                "The collection screen believes an empty grid.")
        #expect(String(views[split.lowerBound...]).contains("KavitaShelfBulk.held("),
                "The list screen believes an empty list.")
    }
}
