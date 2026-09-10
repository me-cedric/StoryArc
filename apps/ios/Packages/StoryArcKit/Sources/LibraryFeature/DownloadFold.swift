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
    /// row. A card the store does not hold changes neither: a file downloaded from an OPDS
    /// catalogue, or imported by hand, has no server row to join and no cached description.
    static func described(_ publication: Publication, card: KavitaCard?) -> Publication {
        var described = card?.applied(to: publication) ?? publication
        guard let server = card?.remoteIdentity else { return described }
        described.identity = described.identity.recordingServer(server)
        return described
    }

    /// Which row on the shelf this file belongs to, or `nil` when it is a new one.
    ///
    /// The first match, because two rows that both match would already be one row.
    static func rowFor(_ rows: [Publication], downloaded: Publication) -> Int? {
        rows.firstIndex { $0.identity.matches(downloaded.identity) }
    }
}
