public import Foundation

import Synchronization

/// An archive that can change where its bytes come from without the reader noticing.
///
/// `offline-downloads`' *Reading while downloading* asks a publication opened by streaming to
/// "switch to the local copy when the download completes, without interrupting reading". This
/// is the switch. Every page the reader has already decoded stays decoded, the page list is
/// never rewritten, and no position is read or written here — so a reader on page 14 is on
/// page 14 before and after, and nothing reopens under them.
///
/// The reader wraps whatever it opened, local or streamed, so there is one shape above this
/// line rather than two. Android's `AdoptingArchive` is the same object.
///
/// A class holding a lock rather than a value, for both halves of what this has to be:
/// ``ComicArchiveReading`` is `Sendable` and decoding runs off the main actor, so the source
/// can be read from anywhere — and a switch has to be seen by every holder of the reference
/// at once, which is exactly what a value type cannot do.
public final class AdoptingArchive: ComicArchiveReading {
    private let state: Mutex<any ComicArchiveReading>

    public init(_ reading: any ComicArchiveReading) {
        state = Mutex(reading)
    }

    public var pages: [PageEntry] { state.withLock { $0.pages } }

    public var skippedPageCount: Int { state.withLock { $0.skippedPageCount } }

    public var coverPage: PageEntry? { state.withLock { $0.coverPage } }

    public var doublePageIndices: [Int] { state.withLock { $0.doublePageIndices } }

    public func data(for page: PageEntry) async throws -> Data {
        // The lock is released before the read: a page fetched over a range request takes as
        // long as the network does, and holding a mutex across it would stop the reader.
        try await state.withLock { $0 }.data(for: page)
    }

    /// Reads from `local` from now on, when it holds the same pages.
    ///
    /// Refused when it does not, and that is the whole of the safety here: the reader indexes
    /// its pages by position, so an archive listing different entries would move every page
    /// the reader has not decoded yet. A refusal leaves this archive exactly as it was.
    ///
    /// - Returns: whether the switch happened.
    @discardableResult
    public func adopt(_ local: any ComicArchiveReading) -> Bool {
        state.withLock { reading in
            guard local.pages == reading.pages else { return false }
            reading = local
            return true
        }
    }
}
