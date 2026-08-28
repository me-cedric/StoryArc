public import Foundation
public import Catalogue
internal import Formats
public import StoryArcCore

/// Fetching a publication a catalogue offers, and making it something the reader can open.
///
/// `opds-catalog`'s third requirement. A catalogue entry is not a publication: it is a
/// promise of one, in one or more formats, some of which this app cannot read. This is
/// what turns the promise into a file.
///
/// The file lands in the caches directory. `offline-downloads` is a separate capability
/// with its own promises about storage, eviction and a reader's control over both; until
/// that exists, calling this a download would be a claim the app cannot keep. The system
/// may reclaim a cached file, and the catalogue can always be asked again.
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

    public init(pins: CertificatePins = CertificatePins()) {
        client = OpdsClient(pins: pins)
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
        do {
            let data = try await client.data(at: acquisition.href, credential: credential)
            let file = try write(data, for: entry, as: acquisition)
            let publication = try await PublicationIndexer.index(fileAt: file, seriesHint: entry.series)
            state = .idle
            return (publication, file)
        } catch let error as PublicationIndexer.IndexError {
            // Named, not generic. The catalogue said this was an EPUB and the bytes say
            // otherwise, and a reader can only tell a broken server from a broken app if
            // the app says which it found.
            if case let .unsupported(format) = error {
                state = .failed(
                    String(
                        format: String(localized: "catalogue.acquire.unsupported", bundle: .module),
                        format
                    )
                )
            } else {
                state = .failed(String(localized: "catalogue.acquire.unreadable", bundle: .module))
            }
        } catch let error as OpdsError {
            state = .failed(CatalogueMessages.describe(error))
        } catch {
            state = .failed(CatalogueMessages.reachability(error))
        }
        return nil
    }

    /// Where a fetched publication is put.
    ///
    /// Named by the entry's identifier rather than its title: two catalogues can offer the
    /// same title, and a filename collision would hand the reader the wrong book. The
    /// extension is kept because the indexer reads it as one signal among several.
    private func write(_ data: Data, for entry: OpdsEntry, as acquisition: OpdsAcquisition) throws -> URL {
        let directory = URL.cachesDirectory.appending(path: "Catalogue", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let name = entry.id.replacing(#/[^A-Za-z0-9._-]/#, with: "-")
        let format = PublicationFormat(mediaType: acquisition.mediaType)
        let file = directory
            .appending(path: name)
            .appendingPathExtension(format?.rawValue ?? "bin")

        try data.write(to: file, options: .atomic)
        return file
    }
}
