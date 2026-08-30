public import Foundation

internal import Formats
public import Persistence
public import StoryArcCore

/// The downloaded half of the library.
///
/// `library-browsing`'s first requirement is one library "spanning every source", and a
/// download is how a publication from a server comes to be on this device. Until this
/// existed the shelf held what a folder scan found and nothing else: a reader who had
/// downloaded forty chapters from Kavita saw none of them in their library, and could only
/// reach them by browsing back to the server they came from — which is the opposite of
/// taking a library with you, and made the source selector a list of sources with nothing
/// behind them.
///
/// Its own file because ``LibraryModel`` is at the length where things stop being findable
/// in it, and this is a seam that was already there: everything here is about the download
/// tree, and nothing else in the model knows that tree exists.
extension LibraryModel {
    /// Brings finished downloads onto the shelf, each attributed to its source.
    ///
    /// The tree is walked rather than each record's path being reconstructed. The record
    /// says what a download is called and the writers have not always agreed on the file's
    /// name; they have always agreed on the *directory*, which is why
    /// ``Persistence/DownloadStore/download(forFileAt:in:)`` matches on that.
    ///
    /// Only finished downloads. A running one is a partial file, and indexing a truncated
    /// archive produces either an error or, worse, a publication with three of its pages.
    public func adoptDownloads() async {
        guard let downloadStore else { return }
        let downloads = downloadStore.library()
        guard !downloads.finished.isEmpty else { return }

        var added = false
        for await event in LibraryScanner.scan(folderAt: downloadStore.directory) {
            guard case let .found(publication) = event,
                  let path = publication.identity.normalizedPath
            else { continue }

            let url = URL(fileURLWithPath: path)
            guard let record = downloadStore.download(forFileAt: url, in: downloads),
                  record.state.isFinished
            else { continue }

            if adopt(publication, from: record, at: url) { added = true }
        }

        guard added else { return }
        rebuild()
        // Their reading positions too. A chapter downloaded and then read has a position on
        // this device like any other, and the bar under its cover is how a reader sees that
        // the library and the reader are talking about the same book.
        await refreshProgress()
    }

    /// Puts one downloaded publication on the shelf.
    ///
    /// Returns whether the shelf actually changed, so a walk that found nothing new does
    /// not trigger a re-sort of the whole library.
    ///
    /// A publication already there is not added twice: identity decides, not the path, so a
    /// comic that lives in a picked folder *and* was downloaded is one row (ADR-0006). The
    /// existing row gains the attribution when it had none, for the same reason a second
    /// folder scan hands one over — a row that knows where it came from beats one that does
    /// not, whichever found it first.
    private func adopt(_ publication: Publication, from record: Download, at url: URL) -> Bool {
        var attributed = publication
        attributed.sourceID = record.sourceID

        if let seen = publications.firstIndex(
            where: { $0.identity.matches(publication.identity) }
        ) {
            if publications[seen].sourceID == nil, attributed.sourceID != nil {
                publications[seen].sourceID = attributed.sourceID
            }
            return false
        }

        publications.append(attributed)
        locations[attributed.id] = url
        return true
    }
}
