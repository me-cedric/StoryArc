public import Foundation

/// Where the reader opens a publication that may still be arriving.
///
/// `offline-downloads`' *Reading while downloading*: a publication that is still downloading
/// "opens immediately by streaming, and switches to the local copy when the download
/// completes". Both halves are decisions about an *address*, so both live here:
/// ``of(local:transfer:readsWhereItLies:)`` picks the address a screen opens, and
/// ``arrived(at:in:)`` reports the local copy that may take over from a streamed one.
///
/// Held outside every view because two views ask it — the publication's own page and the
/// reader — and because a rule inside a view can only be checked by reading its text.
/// Android's `ReadingAddress` is the same rules in the same order.
public enum ReadingAddress {

    /// The schemes a publication can be read a range at a time over.
    ///
    /// ``HttpSource/register(transport:)`` teaches `ComicArchiveOpener` these two and no
    /// others, so an address outside this list is a local file to every caller above. That is
    /// why the check is made rather than assumed: a `Download` is read back from a store on
    /// disk, and an address this rule waved through would be opened as a file that is not
    /// there.
    private static let streamed = ["http", "https"]

    /// Whether this address is read over the network rather than off the disk.
    public static func isStreamed(_ address: URL) -> Bool {
        guard let scheme = address.scheme?.lowercased() else { return false }
        return streamed.contains(scheme)
    }

    /// The address to open, or `nil` when there is nothing to open yet.
    ///
    /// - Parameters:
    ///   - local: a copy on this device, when there is one. It always wins: a publication
    ///     already here reads with no network at all, which is `offline-downloads`' whole
    ///     point.
    ///   - transfer: the queue's record for this publication, when there is one.
    ///   - readsWhereItLies: whether this publication's decoder can read from a source rather
    ///     than from a file. The platform half of ``StreamingOffer``'s question of the same
    ///     name, answered by the caller because the list of such decoders is the caller's.
    public static func of(
        local: URL?,
        transfer: Download?,
        readsWhereItLies: Bool
    ) -> URL? {
        if let local { return local }
        guard readsWhereItLies, let transfer else { return nil }
        // Queued, running and paused are all "still downloading" — a held transfer resumes,
        // and the bytes already on the server can be read meanwhile. Finished without a local
        // copy means the file went away, and failed is a state `offline-downloads` requires to
        // be stated with a retry action rather than read past.
        switch transfer.state {
        case .queued, .running, .paused: break
        case .finished, .failed: return nil
        }
        return isStreamed(transfer.remote) ? transfer.remote : nil
    }

    /// The copy that has arrived for a publication being read at `address`, or `nil`.
    ///
    /// Matched on the address itself rather than on a publication identity, because the
    /// address is what the reader actually opened: the transfer fetching those exact bytes is
    /// the one whose file is a copy of what is on screen. A reader already on a local file has
    /// nothing to switch to, so a local address matches nothing.
    public static func arrived(at address: URL, in downloads: DownloadLibrary) -> Download? {
        guard isStreamed(address) else { return nil }
        return downloads.finished.first { $0.remote == address }
    }
}
