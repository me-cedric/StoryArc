public import Foundation

public import StoryArcCore

/// How ``PublicationIndexer`` turns audio into a `Publication`.
///
/// Its own file rather than another builder beside the comic ones: the comic builders share
/// a metadata-precedence question — `ComicInfo.xml` against a filename guess — that audio
/// does not have, and `PublicationIndexer+Building.swift` is already near the 400-line cap.
extension PublicationIndexer {
    /// The one publication a directory is.
    ///
    /// `publication-formats` lists a plain folder of ordered images as a publication and a
    /// folder of ordered audio as one too, so a folder has to be asked which it is before
    /// anything in it is opened. `FolderKind` answers from the entries' names — see its own
    /// note on why this one detection reads extensions where the rest of the layer reads
    /// bytes — and each part is still sniffed from its bytes when it is played.
    ///
    /// No digest either way. A folder keys on its path alone, because there is no file to
    /// hash.
    static func folderPublication(at url: URL) async throws -> Publication {
        let name = url.lastPathComponent
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
        let found = identity(forPath: url.path, digest: nil)

        if FolderKind.of(entryNames: entries) == .audiobook {
            return await audiobook(
                at: url,
                identity: found,
                format: .audioFolder,
                fallback: FilenameMetadata(filename: name)
            )
        }
        return comic(
            try ImageFolderArchive(directory: url),
            format: .imageFolder,
            identity: found,
            filename: name,
            fallback: FilenameMetadata(filename: name)
        )
    }

    /// A publication whose pages are minutes.
    ///
    /// `publication-formats` lists three shapes and this builds all three: an M4B with its
    /// own chapter markers, a single audio file with none, and a folder of ordered parts.
    /// Which of them it is decides nothing here — ``AudiobookReader`` has already turned all
    /// three into parts, and this is the metadata half.
    ///
    /// **The part count goes in `pageCount`, and the damage in `skippedPageCount`.** Not a
    /// pun on a field name: the library and `reading-progress` both ask how much of a
    /// publication there is and how much of it was lost, and a comic missing pages and an
    /// audiobook missing a part are the same question — "by the same rule that opens a comic
    /// missing pages", as `publication-formats` puts it. Two more fields would be two more
    /// things every list, filter and progress bar had to learn for no gain a reader can see.
    static func audiobook(
        at url: URL,
        identity: PublicationIdentity,
        format: PublicationFormat,
        fallback: FilenameMetadata
    ) async -> Publication {
        let filename = url.lastPathComponent
        let book = format == .audioFolder
            ? await AudiobookReader.read(folderAt: url)
            : await AudiobookReader.read(fileAt: url)
        let coverPath = await audiobookCoverPath(at: url, format: format)

        return Publication(
            identity: identity,
            format: format,
            displayTitle: title(from: nil, fallback: fallback, filename: filename),
            series: fallback.series,
            number: fallback.number,
            volume: fallback.volume,
            year: fallback.year,
            origin: .inferred,
            pageCount: book.parts.isEmpty ? nil : book.parts.count,
            skippedPageCount: book.unreadablePartCount,
            // Task 16.9: the container's own embedded artwork, or a folder's loose cover
            // image — see `audiobookCoverPath(at:format:)`. `nil` for a book with neither,
            // which draws the placeholder every publication with no art draws.
            coverPath: coverPath,
            // `.downloadOnly` rather than `.streams`. `AVURLAsset` will stream an HTTP
            // source, but this app reaches its sources through `RandomAccessSource` and
            // hands the player a file URL, so a remote audiobook has to arrive before it
            // plays. `.streams` here would promise something the player cannot do.
            streaming: .downloadOnly
        )
    }

    /// Where this audiobook's own cover is, if it has one. Task 16.9.
    ///
    /// A folder is asked for its own loose image — there is no single file to read embedded
    /// artwork out of, and asking the first part would read whichever track happened to sort
    /// first rather than the book. Every other shape is one file, so its embedded artwork,
    /// once found, is written to disk once by ``AudiobookCoverStore`` and that copy's path is
    /// what `coverPath` carries from here on — the bytes themselves are gone the moment this
    /// function returns, and the file this just wrote is where `CoverLoader` reads them back.
    private static func audiobookCoverPath(at url: URL, format: PublicationFormat) async -> String? {
        if format == .audioFolder {
            return AudiobookCover.inFolder(at: url)?.path
        }
        guard let data = await AudiobookCover.embedded(in: url) else { return nil }
        return AudiobookCoverStore().write(data, for: url)
    }
}
