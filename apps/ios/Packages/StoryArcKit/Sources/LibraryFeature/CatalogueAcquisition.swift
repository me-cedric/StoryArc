public import Foundation
public import Catalogue
internal import Formats
public import Persistence
public import StoryArcCore

/// Fetching a publication a catalogue offers, and making it something the reader can open.
///
/// `opds-catalog`'s third requirement, and the first half of `offline-downloads`. A
/// catalogue entry is not a publication: it is a promise of one, in one or more formats,
/// some of which this app cannot read. This is what turns the promise into a file the
/// reader keeps.
///
/// The file is a download, not a cache entry. It lands in a directory excluded from
/// backups, it is recorded so it can be listed and removed, and it is verified before it
/// is called finished. What is still missing from `offline-downloads` is the queue: this
/// fetches one publication at a time, in the foreground, with no pause and no resume.
@Observable
@MainActor
public final class CatalogueAcquisition {
    public enum State: Equatable, Sendable {
        case idle
        case fetching(title: String)
        case failed(String)
    }

    public private(set) var state: State = .idle

    private let client: OpdsClient
    private let store: DownloadStore?

    /// What has been downloaded, published so the library can show it.
    public private(set) var library: DownloadLibrary

    public init(pins: CertificatePins = CertificatePins(), store: DownloadStore? = nil) {
        client = OpdsClient(pins: pins)
        self.store = store
        library = store?.library() ?? DownloadLibrary()
    }

    /// Which publications are recorded as being on the device.
    ///
    /// From the record, not the filesystem: this is read once per redraw for a whole grid,
    /// and a `stat` per cell per frame is not a thing to do for a badge. The filesystem is
    /// asked at the moment of opening, by ``downloaded(_:)``, which is where being wrong
    /// would matter.
    public var onDevice: Set<String> {
        Set(library.finished.map(\.id))
    }

    /// Where a publication already downloaded lives, if it does.
    ///
    /// `offline-downloads`: when a publication is already downloaded "the download action
    /// is replaced by a state indicator and a remove-download action, and the app does not
    /// re-fetch it". This is how a caller asks.
    public func downloaded(_ entry: OpdsEntry) -> URL? {
        guard let download = library[entry.id], download.state.isFinished, let store else {
            return nil
        }
        let file = store.location(
            for: entry.id,
            extension: PublicationFormat(mediaType: download.mediaType)?.rawValue ?? "bin"
        )
        // Asked of the filesystem, not of the record. A download the system reclaimed is
        // one the reader should be offered again rather than shown a missing file.
        return FileManager.default.fileExists(atPath: file.path()) ? file : nil
    }

    /// Forgets a download and deletes its file.
    public func remove(_ id: Download.ID) {
        if let store, let download = library[id] {
            store.delete(
                store.location(
                    for: id,
                    extension: PublicationFormat(mediaType: download.mediaType)?.rawValue ?? "bin"
                )
            )
        }
        library = library.removing(id)
        store?.save(library)
    }

    /// Which acquisition to take when the entry offers several.
    ///
    /// `opds-catalog`: "the app selects EPUB for reflowable reading and lets the user
    /// choose another format". EPUB first, then the comic containers, then PDF — a comic
    /// offered as both CBZ and PDF is a comic, and the PDF is a worse copy of it.
    public static func best(of entry: OpdsEntry) -> OpdsAcquisition? {
        readable(in: entry).min { left, right in
            rank(left) < rank(right)
        }
    }

    /// Every acquisition this app could act on, in the order the feed listed them.
    public static func readable(in entry: OpdsEntry) -> [OpdsAcquisition] {
        entry.acquisitions.filter { acquisition in
            guard acquisition.kind.isFetchable else { return false }
            return PublicationFormat(mediaType: acquisition.mediaType)?.isOpenable == true
        }
    }

    private static func rank(_ acquisition: OpdsAcquisition) -> Int {
        switch PublicationFormat(mediaType: acquisition.mediaType) {
        case .epub: 0
        case .cbz, .cbt, .cbr: 1
        case .pdf: 2
        default: 3
        }
    }

    /// Fetches one acquisition and indexes it.
    ///
    /// Returns the publication and where it landed, which is exactly what the library
    /// hands to a reader. Nil when anything went wrong, with ``state`` saying what.
    public func fetch(
        _ entry: OpdsEntry,
        using acquisition: OpdsAcquisition,
        credential: OpdsCredential?
    ) async -> (publication: Publication, location: URL)? {
        state = .fetching(title: entry.title)
        library = library.queueing(
            Download(
                id: entry.id,
                title: entry.title,
                remote: acquisition.href,
                mediaType: acquisition.mediaType,
                state: .running
            )
        ).marking(entry.id, as: .running)

        do {
            let data = try await client.data(at: acquisition.href, credential: credential)
            let file = try write(data, for: entry, as: acquisition)
            // Indexing *is* the verification. `offline-downloads` requires integrity to be
            // checked "before it is marked available offline", and with no checksum from
            // the server the honest check is whether the bytes are a publication this app
            // can open. A truncated archive fails here rather than at the first page turn.
            let publication = try await PublicationIndexer.index(fileAt: file, seriesHint: entry.series)
            library = library
                .advancing(entry.id, downloaded: Int64(data.count), expected: Int64(data.count))
                .marking(entry.id, as: .finished)
            store?.save(library)
            state = .idle
            return (publication, file)
        } catch let error as PublicationIndexer.IndexError {
            // Named, not generic. The catalogue said this was an EPUB and the bytes say
            // otherwise, and a reader can only tell a broken server from a broken app if
            // the app says which it found.
            let message = if case let .unsupported(format) = error {
                String(
                    format: String(localized: "catalogue.acquire.unsupported", bundle: .module),
                    format
                )
            } else {
                String(localized: "catalogue.acquire.unreadable", bundle: .module)
            }
            fail(entry.id, reason: message)
        } catch let error as OpdsError {
            fail(entry.id, reason: CatalogueMessages.describe(error))
        } catch {
            fail(entry.id, reason: CatalogueMessages.reachability(error))
        }
        return nil
    }

    /// Records a failure, throws away the partial file, and tells the reader.
    ///
    /// The file goes because it did not verify, and a half-written archive left on disk is
    /// counted by the storage view as a book the reader has.
    private func fail(_ id: Download.ID, reason: String) {
        library = library.failing(id, reason: reason)
        if let store, let download = library[id] {
            store.delete(
                store.location(
                    for: id,
                    extension: PublicationFormat(mediaType: download.mediaType)?.rawValue ?? "bin"
                )
            )
        }
        store?.save(library)
        state = .failed(reason)
    }

    /// Where a fetched publication is put.
    ///
    /// The store decides, because the store is what knows which directory is excluded from
    /// backups and how a file is named from an identity.
    private func write(_ data: Data, for entry: OpdsEntry, as acquisition: OpdsAcquisition) throws -> URL {
        guard let store else { throw CocoaError(.fileNoSuchFile) }
        try store.prepare()
        let format = PublicationFormat(mediaType: acquisition.mediaType)
        let file = store.location(for: entry.id, extension: format?.rawValue ?? "bin")
        try data.write(to: file, options: .atomic)
        return file
    }
}
