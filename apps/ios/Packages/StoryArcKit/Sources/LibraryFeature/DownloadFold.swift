internal import Foundation

internal import StoryArcCore

/// How a downloaded file joins the row the source it came from already put on the shelf.
///
/// `library-browsing`: a publication a source offers and the same publication downloaded
/// are one row. They were two. A server row is identified by its `ServerIdentifier` and
/// nothing else — there is no file yet — and a downloaded file is identified by its path
/// and its digest, so `PublicationIdentity.matches` had nothing in common to match on. The
/// library drew the download beside the row it was downloaded from, and the reader saw a
/// duplicate the moment a Kavita chapter finished.
///
/// **The card is the bridge.** It is written when the chapter is kept and holds the source
/// and the chapter, which is exactly the pair ``KavitaContributor`` builds a server
/// identifier from. Recording it on the downloaded file's identity is all the fold is:
/// `matches` then finds the remote row, and the *existing* row is the one kept — so
/// nothing filed against its key moves when the bytes arrive.
///
/// Pure, so the decision can be asserted without a library, a download store or an archive
/// on disk. Android's `DownloadFold` is the twin, and `DownloadFoldTests` asserts the same
/// claims on both.
enum DownloadFold {

    /// The downloaded publication as the shelf should hold it: described by the card, and
    /// carrying the identifier of the row it is a copy of.
    ///
    /// `kavita-server` requires the server's description to win over the file's own, which
    /// is what ``KavitaCard/applied(to:)`` does; the identifier is what makes the two one
    /// row. A card the store does not hold changes neither: a file downloaded by hand has no
    /// server row to join and no cached description.
    ///
    /// - Parameter record: the download this file was landed by, when there is one. dl-core
    ///   1.4: an OPDS download has no card — Kavita's own bridge — so ``opdsIdentity(for:)``
    ///   is asked instead, and only when the card did not already answer. Defaulted to `nil`
    ///   so every existing caller — Kavita's own, and every test that built this claim before
    ///   an OPDS record was in scope — is unchanged.
    static func described(_ publication: Publication, card: KavitaCard?, record: Download? = nil) -> Publication {
        var described = card?.applied(to: publication) ?? publication
        guard let server = card?.remoteIdentity ?? record.flatMap(opdsIdentity(for:)) else {
            return described
        }
        described.identity = described.identity.recordingServer(server)
        return described
    }

    /// The server identity an OPDS download's own record implies, or `nil` for a download
    /// this queue did not key that way.
    ///
    /// `OpdsContributor` builds the catalogue row's identifier as `"opds:<entry id>"`, and
    /// `DownloadQueue/downloadID(for:sourceID:)` keys the record as
    /// `"opds:<source>:<entry id>"` — the same two parts in a different order, with the
    /// source written out again. Parsed rather than re-derived from an `OpdsEntry`: adopting
    /// a download walks the download tree and has no entry to ask, only the record it wrote.
    static func opdsIdentity(for download: Download) -> PublicationIdentity.ServerIdentifier? {
        guard let source = download.sourceID else { return nil }
        let prefix = "opds:\(source.uuidString):"
        guard download.id.hasPrefix(prefix) else { return nil }
        let entryID = download.id.dropFirst(prefix.count)
        return PublicationIdentity.ServerIdentifier(sourceID: source, remoteID: "opds:\(entryID)")
    }

    /// Which row on the shelf this file belongs to, or `nil` when it is a new one.
    ///
    /// The first match, because two rows that both match would already be one row.
    static func rowFor(_ rows: [Publication], downloaded: Publication) -> Int? {
        rows.firstIndex { $0.identity.matches(downloaded.identity) }
    }
}
