public import Foundation

internal import AVFoundation

/// Where an audiobook's own artwork comes from, read once at index time.
///
/// Task 16.9, `audio-playback`'s *The full player*: no audiobook cover was ever extracted,
/// so the shelf, the player and the lock screen all drew the coverless well for every
/// audiobook — even one whose file carries its own picture. Two ways in:
///
/// - **A single file's embedded artwork.** An MP4 `covr` atom or an ID3 `APIC` frame, both
///   of which `AVAsset.commonMetadata` surfaces under the one identifier,
///   `.commonIdentifierArtwork` — the same lookup Apple's own Music and Podcasts apps make,
///   so a book tagged by any ordinary tool already carries what this reads.
/// - **A folder's own loose cover image**, for the one shape with no single file to embed
///   one in: the names a media server's own `folder.jpg` convention already uses.
///
/// What this does *not* do is decode anything. `CoverLoader` already owns "bytes in, a sized
/// `CGImage` out" for every other format, and an audiobook's cover is bytes exactly like a
/// comic page's — this only has to find them once and say where they are.
public enum AudiobookCover {
    /// The names a folder's own cover is looked for by, in the order they are tried.
    public static let folderCoverNames = [
        "cover.jpg", "cover.jpeg", "cover.png",
        "folder.jpg", "folder.jpeg", "folder.png",
    ]

    /// A single audio file's own embedded artwork, or `nil` where it carries none.
    ///
    /// `AVAsset.commonMetadata` is the one call: Apple's own mapping puts an MP4 `covr` atom
    /// and an ID3 `APIC` frame under the identical `.commonIdentifierArtwork`, so there is no
    /// branch here on which container this is — the container-specific reading already
    /// happened inside the framework.
    public static func embedded(in url: URL) async -> Data? {
        let asset = AVURLAsset(url: url)
        guard let metadata = try? await asset.load(.commonMetadata) else { return nil }
        let artwork = AVMetadataItem.metadataItems(
            from: metadata, filteredByIdentifier: .commonIdentifierArtwork
        )
        guard let item = artwork.first else { return nil }
        return try? await item.load(.dataValue)
    }

    /// A loose cover image beside a folder's own tracks, by the first of
    /// ``folderCoverNames`` that exists.
    ///
    /// The file itself, not its bytes: the image lives inside the reader's own library for
    /// as long as the folder does, exactly as a comic archive's own cover page does, so there
    /// is nothing here for ``AudiobookCoverStore`` to copy.
    public static func inFolder(at url: URL) -> URL? {
        for name in folderCoverNames {
            let candidate = url.appending(path: name)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }
}

/// Where embedded artwork is written once it has been read out of its container.
///
/// A single file's cover has no path of its own the way a folder's loose image or a comic's
/// archive entry does — the bytes exist only inside the container until something reads them
/// out — so this is the one place in the audio path that writes rather than only locates.
/// ``Publication/coverPath`` carries the file this writes, and ``CoverLoader`` reads it back
/// exactly as it reads a comic's cover page or an EPUB's cover href.
public struct AudiobookCoverStore: Sendable {
    private let directory: URL

    public init(directory: URL? = nil) {
        self.directory = directory
            ?? URL.cachesDirectory.appending(path: "audio-covers", directoryHint: .isDirectory)
    }

    /// Writes `data` under a name derived from `source`'s own path, replacing whatever was
    /// written for it before, and returns the file's own path.
    ///
    /// Failure is silent and correct, the same rule `CoverCache.store` follows: a device with
    /// no room left should index the book, not refuse to.
    public func write(_ data: Data, for source: URL) -> String? {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = file(for: source)
        guard (try? data.write(to: url, options: .atomic)) != nil else { return nil }
        return url.path
    }

    /// Keyed by a hash of the source path rather than the path itself, for the reason
    /// `CoverCache.file(for:maxPixelSize:)` already gives: a path carries separators, and a
    /// file name is not a place to find that out.
    private func file(for source: URL) -> URL {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in Data(source.path.utf8) {
            hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01b3
        }
        return directory.appending(path: String(hash, radix: 36))
    }
}
