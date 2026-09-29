import Foundation

internal import StoryArcCore

/// Where a fetched chapter is written, named for what it actually is.
///
/// `kavita-server` serves comics and books from the same endpoint, and the reader the app
/// opens is chosen by the file's format. Writing every chapter as `.cbz` sent an EPUB to the
/// comic reader, which spun for ever on a file it could not page.
/// Where a chapter fetched from a server is kept while it is read.
///
/// The chapter's id is the *directory* and the name is the publication's own. It used to be
/// the other way round, and `chapter-5.cbz` was then the only name anything downstream had:
/// the indexer reads a series out of a filename, so every chapter of one series landed on a
/// shelf of its own, and `comic-reader`'s "applies to the series" applied to one chapter.
/// The id still makes the path unique; it no longer has to be the name as well.
func kavitaCacheFile(chapterId: Int, mediaType: String?, named: String? = nil) -> URL? {
    let directory = URL.cachesDirectory
        .appending(path: "Kavita", directoryHint: .isDirectory)
        .appending(path: String(chapterId), directoryHint: .isDirectory)
    guard (try? FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true
    )) != nil else { return nil }

    let format = mediaType.flatMap(PublicationFormat.init(mediaType:))
    let ext = format.map { String(describing: $0).lowercased() } ?? "cbz"
    // A path separator in a server's title would make a directory rather than a name.
    let stem = (named?.replacingOccurrences(of: "/", with: "-")).flatMap {
        $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0
    } ?? "chapter-\(chapterId)"
    return directory.appending(path: "\(stem).\(ext)")
}
