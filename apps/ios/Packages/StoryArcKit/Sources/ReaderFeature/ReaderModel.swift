public import CoreGraphics
public import Foundation

public import Formats
public import Persistence
public import StoryArcCore

/// One publication, open for reading.
///
/// Holds the page list, the current position, and a small window of decoded
/// pages. `comic-reader` requires a turn to be immediate, which means the next
/// page has to be decoded before it is asked for — so this keeps neighbours warm
/// and drops what has scrolled away.
///
/// `@MainActor` because it is view state. Decoding happens off it.
@MainActor
@Observable
public final class ReaderModel {
    public let publication: Publication
    public private(set) var pages: [PageEntry] = []
    public private(set) var currentIndex = 0
    /// Set when the publication could not be opened at all.
    public private(set) var failure: String?

    /// How many pages either side of the current one to keep decoded.
    ///
    /// One is enough to make a turn instant in both directions and small enough
    /// that a 2000×3000 page corpus does not sit in memory. `publication-formats`
    /// requires decoding not to exhaust memory regardless of source image size.
    private let window = 1

    private var decoded: [Int: CGImage] = [:]
    private var archive: (any ComicArchiveReading)?
    private let url: URL
    private var maxPixelSize = 2048
    private let progress: ProgressStore?

    public init(publication: Publication, url: URL, progress: ProgressStore? = nil) {
        self.publication = publication
        self.url = url
        self.progress = progress
    }

    /// The direction the reader turns pages in.
    ///
    /// From the publication, which took it from `ComicInfo` or the language. The
    /// reader never guesses it separately — a manga that opens left-to-right on
    /// one screen and right-to-left on another is worse than either.
    public var readingDirection: ReadingDirection { publication.readingDirection }

    public var currentPage: PageEntry? {
        pages.indices.contains(currentIndex) ? pages[currentIndex] : nil
    }

    /// Opens the publication and decodes the first page.
    public func open(maxPixelSize: Int) async {
        self.maxPixelSize = maxPixelSize
        do {
            let opened = try await ComicArchiveOpener.open(fileAt: url)
            archive = opened
            pages = opened.pages
            // Start at the designated cover when there is one. `publication-formats`
            // lets ComicInfo name a cover that is not page one, and opening on a
            // different page than the library showed would be disorienting.
            if let coverPath = publication.coverPath,
               let index = pages.firstIndex(where: { $0.path == coverPath }) {
                currentIndex = index
            }
            // A recorded position wins over the cover. `reading-progress` is about
            // picking up where you left off, and a book you are halfway through
            // should not reopen at its cover.
            if let recorded = try? await progress?.progress(for: publication.identity),
               case let .page(index, _) = recorded.position,
               pages.indices.contains(index) {
                currentIndex = index
            }
            await warm(around: currentIndex)
        } catch {
            failure = String(describing: error)
        }
    }

    /// The decoded page at an index, if it is ready.
    public func image(at index: Int) -> CGImage? { decoded[index] }

    /// Whether a page failed to decode, as opposed to not being ready yet.
    public func isUnavailable(at index: Int) -> Bool {
        attempted.contains(index) && decoded[index] == nil
    }

    private var attempted: Set<Int> = []

    public func go(to index: Int) async {
        guard pages.indices.contains(index) else { return }
        currentIndex = index
        await warm(around: index)
        await record(index)
    }

    /// Writes the position down.
    ///
    /// Every turn, not on leaving: ADR-0006 makes the local store authoritative,
    /// and a reader that only saves on a clean exit loses the evening when the app
    /// is killed in the background — which is the normal way a phone closes an app.
    ///
    /// The last page marks the publication finished. Finished is sticky, so
    /// turning back afterwards does not unmark it.
    private func record(_ index: Int) async {
        guard let progress, !pages.isEmpty else { return }
        try? await progress.save(
            ReadingProgress(
                identity: publication.identity,
                position: .page(index: index, of: pages.count),
                isFinished: index == pages.count - 1,
                updatedAt: Date()
            )
        )
    }

    /// The next page in *reading* order, which is not always the next index.
    public func advance() async {
        await go(to: currentIndex + 1)
    }

    public func retreat() async {
        await go(to: currentIndex - 1)
    }

    /// Decodes the current page and its neighbours, and drops the rest.
    private func warm(around index: Int) async {
        let wanted = Set((index - window)...(index + window)).filter { pages.indices.contains($0) }
        // Dropped before decoding, so peak memory is the window and not the window
        // plus whatever was there before.
        for key in decoded.keys where !wanted.contains(key) {
            decoded.removeValue(forKey: key)
            attempted.remove(key)
        }
        // The current page first: a turn should not wait on its neighbours.
        for target in [index] + wanted.sorted(by: { abs($0 - index) < abs($1 - index) }) {
            guard decoded[target] == nil, !attempted.contains(target) else { continue }
            await decode(target)
        }
    }

    private func decode(_ index: Int) async {
        guard let archive, pages.indices.contains(index) else { return }
        attempted.insert(index)
        let page = pages[index]
        let size = maxPixelSize
        let image = await Task.detached(priority: .userInitiated) {
            guard let data = try? await archive.data(for: page) else { return CGImage?.none }
            return try? PageDecoder.decode(data, maxPixelSize: size)
        }.value
        if let image { decoded[index] = image }
    }
}
