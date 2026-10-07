public import Foundation

public import StoryArcCore

/// The identifier a publication carries, read on demand for the cover lookup.
///
/// Task 6.1 of `cover-for-every-publication`. Read when the lookup rung asks, not at index
/// time: `Publication` has no identifier field, and adding one would need a migration of the
/// stored library for a value only a reader who turned the lookup on ever uses. Android's
/// `CoverIdentifierReader` is its twin.
public enum CoverIdentifierReader {

    /// The identifier for the publication at `url`: a file, or a folder of tracks.
    ///
    /// A folder is read through its first track, because every track of an album carries the
    /// same release group.
    public static func identifier(for publication: Publication, at url: URL) async -> CoverIdentifier? {
        guard let target = readable(url),
              let source = try? FileSource(url: target)
        else { return nil }
        return await identifier(for: publication, source: source)
    }

    /// The same, over bytes already open. The call a test makes.
    public static func identifier(
        for publication: Publication, source: some RandomAccessSource
    ) async -> CoverIdentifier? {
        switch publication.format {
        case .epub:
            await epubISBN(source)
        case .m4b, .mp3, .flac, .ogg, .audioFolder:
            await AudioTagIdentifiers.identifier(in: source)
        case .pdf, .cbz, .cbr, .cbt, .cb7, .imageFolder:
            nil
        }
    }

    private static func epubISBN(_ source: some RandomAccessSource) async -> CoverIdentifier? {
        guard let reader = try? await EpubReader(source: source) else { return nil }
        return reader.metadata.identifiers.lazy.compactMap(isbn(in:)).first
    }

    /// An ISBN as an OPF writes it: bare, hyphenated, or behind `urn:isbn:`.
    static func isbn(in text: String) -> CoverIdentifier? {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["urn:isbn:", "isbn:"] where trimmed.lowercased().hasPrefix(prefix) {
            trimmed = String(trimmed.dropFirst(prefix.count))
            break
        }
        return CoverIdentifier.isbn(reading: trimmed)
    }

    private static func readable(_ url: URL) -> URL? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return nil
        }
        guard isDirectory.boolValue else { return url }
        let tracks = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
        return tracks
            .filter { FolderKind.audioExtensions.contains(($0 as NSString).pathExtension.lowercased()) }
            .sorted()
            .first
            .map { url.appending(path: $0) }
    }
}
