internal import Foundation

internal import Kavita
internal import Persistence

/// One chapter a server shelf holds, with everything a keep or a mark needs to name it.
///
/// A collection holds series and a reading list holds chapters, so the two are brought to one
/// shape here and the actions below ask about chapters only. Android's `KavitaShelfChapter`
/// is its twin.
struct KavitaShelfChapter: Equatable, Sendable {
    let chapter: KavitaChapter
    let series: KavitaSeries
    let volumeID: Int
    /// The file's size in bytes, or zero where the server stated none.
    let bytes: Int64

    var isFinished: Bool { chapter.isFinished }

    /// Where the chapter sits on the server, which a mark and a kept copy both have to name.
    func origin(sourceID: String) -> KavitaOrigin {
        KavitaOrigin(
            sourceId: sourceID,
            libraryId: series.libraryId,
            seriesId: series.id,
            volumeId: volumeID,
            chapterId: chapter.id,
            pages: chapter.pages
        )
    }
}

/// How large a whole-shelf download will be, in the three ways a server can leave it.
enum KavitaBulkSize: Equatable, Sendable {
    /// Every chapter stated its size, so this is the total.
    case known(Int64)
    /// Some did not, so this is a floor and the sentence says so.
    case atLeast(Int64)
    /// None did, so there is no number to give.
    case unstated
}

/// What a whole-shelf download will copy: stated to the reader before anything starts.
struct KavitaBulkDownloadAsk: Equatable, Sendable {
    let chapters: [KavitaShelfChapter]
    let size: KavitaBulkSize

    var count: Int { chapters.count }
}

/// What a whole-shelf mark changed, so ten seconds later one tap can put it back.
struct KavitaMarkUndo: Equatable, Sendable, Identifiable {
    /// Which mark this is, so the ten seconds restart for a second mark and not for a redraw.
    let id = UUID()
    let chapters: [KavitaShelfChapter]
    let read: Bool
}

/// Acting on everything a server's collection or reading list holds.
///
/// `collections-and-reading-lists`: a reader downloads "an entire collection or reading list"
/// and is told "the item count and total size before starting", or marks one read, "and the
/// action is undoable for 10 seconds". Every rule is here and free of the view, so a test
/// states it without a window. The view asks these functions and draws their answers.
/// Android's `KavitaShelfBulk` is its twin.
enum KavitaShelfBulk {

    /// How long a whole-shelf mark can be taken back. `collections-and-reading-lists`: ten.
    static let undoSeconds = 10

    /// A reading list's entries as chapters, in the server's order, each chapter once.
    static func chapters(of items: [KavitaReadingListItem]) -> [KavitaShelfChapter] {
        var seen = Set<Int>()
        return items.filter { seen.insert($0.chapterId).inserted }.map { item in
            KavitaShelfChapter(
                chapter: KavitaChapter(
                    id: item.chapterId,
                    number: "",
                    title: item.title,
                    pages: item.pagesTotal,
                    pagesRead: item.pagesRead,
                    seriesId: item.seriesId
                ),
                series: KavitaSeries(
                    id: item.seriesId, name: item.seriesName ?? "", libraryId: item.libraryId
                ),
                volumeID: item.volumeId,
                bytes: item.fileSize
            )
        }
    }

    /// Every chapter of a collection's series, or nil when any series could not be read.
    ///
    /// Nil rather than the chapters that did arrive: a count stated over part of a collection
    /// is a count that is wrong, and the reader is told the server did not answer instead.
    static func chapters(
        of series: [KavitaSeries],
        volumes: @escaping @Sendable (Int) async throws -> [KavitaVolume]
    ) async -> [KavitaShelfChapter]? {
        let read: [(KavitaSeries, [KavitaVolume])?] = await withTaskGroup(
            of: (Int, (KavitaSeries, [KavitaVolume])?).self
        ) { group in
            for (index, each) in series.enumerated() {
                group.addTask {
                    guard let held = try? await volumes(each.id) else { return (index, nil) }
                    return (index, (each, held))
                }
            }
            var answers = [(KavitaSeries, [KavitaVolume])?](repeating: nil, count: series.count)
            for await (index, answer) in group { answers[index] = answer }
            return answers
        }
        guard !read.contains(where: { $0 == nil }) else { return nil }
        var seen = Set<Int>()
        return read.compactMap { $0 }.flatMap { each, held in
            held.flatMap { volume in
                volume.chapters.map {
                    KavitaShelfChapter(chapter: $0, series: each, volumeID: volume.id, bytes: $0.fileBytes)
                }
            }
        }.filter { seen.insert($0.chapter.id).inserted }
    }

    /// What a download would copy, or nil when everything is already on the device.
    ///
    /// `kept` is the chapters this device already holds a download of. A chapter in it is not
    /// counted and not queued, so the number stated is the number started.
    static func downloadAsk(
        _ chapters: [KavitaShelfChapter], kept: Set<Int>
    ) -> KavitaBulkDownloadAsk? {
        let wanted = chapters.filter { !kept.contains($0.chapter.id) }
        guard !wanted.isEmpty else { return nil }
        let stated = wanted.filter { $0.bytes > 0 }
        let total = stated.reduce(Int64(0)) { $0 + $1.bytes }
        let size: KavitaBulkSize = if stated.isEmpty {
            .unstated
        } else if stated.count == wanted.count {
            .known(total)
        } else {
            .atLeast(total)
        }
        return KavitaBulkDownloadAsk(chapters: wanted, size: size)
    }

    /// Queues every chapter the reader was told about, together.
    ///
    /// Together rather than one after another: `keep` returns when its file has landed, so one
    /// at a time would put one row in the downloads view and hide the other seventy until
    /// their turn. The queue bounds how many transfers run at once.
    ///
    /// - Returns: how many chapters `keep` kept.
    static func download(
        _ ask: KavitaBulkDownloadAsk,
        keep: @escaping @Sendable (KavitaShelfChapter) async -> Bool
    ) async -> Int {
        await withTaskGroup(of: Bool.self) { group in
            for each in ask.chapters { group.addTask { await keep(each) } }
            var kept = 0
            for await done in group where done { kept += 1 }
            return kept
        }
    }

    /// The chapters a mark would change: those not already in the state asked for.
    static func changing(_ chapters: [KavitaShelfChapter], read: Bool) -> [KavitaShelfChapter] {
        chapters.filter { $0.isFinished != read }
    }

    /// Sends a mark for each of `chapters`, one at a time.
    ///
    /// One at a time and in order: each goes through the one queue every other mark uses, and a
    /// server that cannot take the route says so through ``KavitaSync/mark``'s own notice.
    static func mark(
        _ chapters: [KavitaShelfChapter],
        read: Bool,
        send: @Sendable (KavitaShelfChapter, Bool) async -> Void
    ) async {
        for each in chapters { await send(each, read) }
    }
}
