import Formats
import Foundation
import Smb
import StoryArcCore

/// What a network share puts in the library.
///
/// Unlike a server, a share cannot be *asked* — it is a filesystem, and a filesystem is
/// walked. That is the whole difficulty, and it is why this was the last of the three.
///
/// **A bounded walk, breadth-first.** A share may hold a hundred thousand files, and a
/// blind walk over a network is minutes of round trips nobody asked for. This lists the
/// root, then the folders it found, level by level, and stops at ``firstSlice``
/// publications or ``maxFolders`` listings, whichever comes first. Breadth-first on
/// purpose: shares put their folders at the root, so depth-first would spend the whole
/// budget inside the first one.
///
/// **The metadata is the filename's, and says so.** Reading a publication's own metadata
/// means fetching the archive, which this bound exists to avoid. ``MetadataOrigin/inferred``
/// is what the row carries, so a later read of the file itself outranks it.
///
/// Android's `SmbContributor` is its twin.
enum SmbContributor {

    /// How many publications one read of a share takes.
    static let firstSlice = 200

    /// How many directory listings it will spend to find them.
    static let maxFolders = 40

    /// The publications a bounded walk of the share finds.
    static func publications(source: UUID, client: SmbClient, address: SmbAddress) async -> SourceSlice {
        var found: [Publication] = []
        var queue = [address.path]
        var listings = 0

        while !queue.isEmpty, found.count < firstSlice, listings < maxFolders {
            let path = queue.removeFirst()
            // A folder that refuses is skipped, not fatal: one unreadable directory must
            // not cost a reader the rest of the share.
            guard let entries = try? await client.list(path) else { continue }
            listings += 1
            for entry in entries {
                if entry.isDirectory {
                    queue.append(entry.path)
                    continue
                }
                if found.count >= firstSlice { break }
                if let row = publication(source: source, entry: entry, address: address, folder: path) {
                    found.append(row)
                }
            }
        }
        // Either budget running out is the walk stopping before the share did, and so is a
        // queue with folders still in it. All three mean the same thing to a reader: there
        // is more on the share than the number on the screen.
        return SourceSlice(
            publications: found,
            holdsMore: !queue.isEmpty || found.count >= firstSlice || listings >= maxFolders
        )
    }

    /// One file as a row, or nil for a file this app cannot open.
    ///
    /// The identity is the share's own `smb://` address for this file, not the bare path
    /// `SmbClient.list` returns: `entry.path` is relative to the share's root, and a
    /// location that is not a real address reads as local — `PublicationAccess.isRemote`
    /// matches it against nothing, the shelf counts a row nobody has downloaded as already
    /// on the device, and opening it hands the reader a path that exists nowhere on the
    /// filesystem. `SmbLocator.write` on the share's own root, not on `address` itself:
    /// `entry.path` already carries the walk's own root — `publications(source:client:
    /// address:)` seeds the recursion at `address.path` and every entry's path is joined
    /// against whichever folder produced it — so a locator built from `address` would
    /// state a configured root twice for a share whose reader picked one deeper than the
    /// top.
    ///
    /// Still one identity per file on the share: two rows are the same publication when
    /// they are the same file, and a share's row and the same file downloaded fold together
    /// with no server identifier.
    static func publication(
        source: UUID,
        entry: SmbEntry,
        address: SmbAddress,
        folder: String
    ) -> Publication? {
        guard let format = format(entry.name) else { return nil }
        let facts = FilenameMetadata(
            filename: entry.name,
            seriesHint: folder.split(separator: "/").last.map(String.init)
        )
        let shareRoot = SmbLocator.write(
            SmbAddress(host: address.host, share: address.share, username: address.username, port: address.port)
        )
        // Encoded component by component: `entry.path` is `/`-joined already, and `entry.path`
        // encoded whole would turn every `/` a folder contributed into `%2F` along with the
        // spaces a filename actually needs escaped — `URL(string:)` would then read the whole
        // remainder as one path component instead of the folders and the file it names.
        let encodedPath = entry.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }
            .joined(separator: "/")
        return Publication(
            identity: PublicationIdentity(normalizedPath: "\(shareRoot)/\(encodedPath)"),
            format: format,
            // The filename without its extension. ``FilenameMetadata`` answers series,
            // number, volume and year and deliberately not a title.
            displayTitle: (entry.name as NSString).deletingPathExtension,
            series: facts.series,
            number: facts.number,
            volume: facts.volume,
            year: facts.year,
            origin: .inferred,
            sourceID: source
        )
    }

    /// The format a name declares, or nil for a file that is not a publication.
    private static func format(_ name: String) -> PublicationFormat? {
        switch (name as NSString).pathExtension.lowercased() {
        case "cbz": .cbz
        case "cbr": .cbr
        case "cb7": .cb7
        case "cbt": .cbt
        case "epub": .epub
        case "pdf": .pdf
        default: nil
        }
    }
}
