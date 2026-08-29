public import Foundation

public import StoryArcCore

/// What a scan has produced so far, kept so an interrupted one can pick up.
///
/// `local-library` requires a folder scan to be "cancellable and resumable". Cancellable is
/// free — the walk stops when nothing is consuming it. Resumable is not: a scan of ten
/// thousand comics is minutes of opening archives, and a reader who backgrounded the app or
/// whose phone reclaimed the process would otherwise watch the whole thing happen again.
///
/// So the scan writes down what it has indexed, in batches, and the next scan of the same
/// folder puts those publications straight into the library and walks past the files they
/// came from. Nothing is opened twice.
///
/// Deliberately **not** a metadata cache. The journal is cleared the moment a scan finishes,
/// because a completed scan has nothing left to resume — `sources` asks for a cache that
/// survives a launch and keeps a library browsable offline, and that is a different
/// requirement with different rules about staleness.
public struct ScanJournal {
    private let defaults: UserDefaults
    private let key = "app.storyarc.scan-journal"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// What a scan of this folder had already indexed when it stopped.
    ///
    /// Empty when the last scan finished, which is the usual case.
    public func indexed(inFolder folder: String) -> [Publication] {
        (stored()[folder] ?? []).map(\.publication)
    }

    /// Records what a scan has produced so far.
    ///
    /// The whole list each time rather than an append: the writer holds it anyway, and a
    /// store that could be half-written is exactly the thing a resume must not read.
    public func record(_ publications: [Publication], inFolder folder: String) {
        var all = stored()
        all[folder] = publications.map(StoredPublication.init)
        save(all)
    }

    /// Forgets a folder's journal. Called when its scan finishes.
    public func clear(folder: String) {
        var all = stored()
        guard all.removeValue(forKey: folder) != nil else { return }
        save(all)
    }

    /// Forgets every journal. Used by a reset, and by the tests.
    public func reset() {
        defaults.removeObject(forKey: key)
    }

    private func stored() -> [String: [StoredPublication]] {
        guard let data = defaults.data(forKey: key),
              let all = try? JSONDecoder().decode([String: [StoredPublication]].self, from: data)
        else { return [:] }
        return all
    }

    private func save(_ all: [String: [StoredPublication]]) {
        guard let data = try? JSONEncoder().encode(all) else { return }
        defaults.set(data, forKey: key)
    }
}

/// What is actually written.
///
/// A separate shape rather than a `Codable` conformance on ``Publication``, for the same
/// reason `StoredDownload` and `StoredRegistry` exist: what is durable is this store's
/// decision, and a conformance on the domain type would let any future field reach the disk
/// without anyone deciding it should.
private struct StoredPublication: Codable {
    let identity: PublicationIdentity
    let format: String
    let displayTitle: String
    let series: String?
    let number: String?
    let volume: Int?
    let authors: [String]
    let publisher: String?
    let year: Int?
    let language: String?
    let summary: String?
    let origin: String
    let pageCount: Int?
    let skippedPageCount: Int
    let coverPath: String?
    let readingDirection: String
    let isFixedLayout: Bool
    let streaming: String
    let sourceID: UUID?

    init(_ publication: Publication) {
        identity = publication.identity
        format = publication.format.rawValue
        displayTitle = publication.displayTitle
        series = publication.series
        number = publication.number
        volume = publication.volume
        authors = publication.authors
        publisher = publication.publisher
        year = publication.year
        language = publication.language
        summary = publication.summary
        origin = publication.origin.rawValue
        pageCount = publication.pageCount
        skippedPageCount = publication.skippedPageCount
        coverPath = publication.coverPath
        readingDirection = publication.readingDirection.rawValue
        isFixedLayout = publication.isFixedLayout
        streaming = publication.streaming.rawValue
        sourceID = publication.sourceID
    }

    /// A row this build cannot read comes back as an unopenable placeholder rather than
    /// being dropped, so a resumed scan does not silently lose a file it had already done.
    var publication: Publication {
        Publication(
            identity: identity,
            format: PublicationFormat(rawValue: format) ?? .cbz,
            displayTitle: displayTitle,
            series: series,
            number: number,
            volume: volume,
            authors: authors,
            publisher: publisher,
            year: year,
            language: language,
            summary: summary,
            origin: MetadataOrigin(rawValue: origin) ?? .inferred,
            pageCount: pageCount,
            skippedPageCount: skippedPageCount,
            coverPath: coverPath,
            readingDirection: ReadingDirection(rawValue: readingDirection) ?? .leftToRight,
            isFixedLayout: isFixedLayout,
            streaming: StreamingCapability(rawValue: streaming) ?? .streams,
            sourceID: sourceID
        )
    }
}
