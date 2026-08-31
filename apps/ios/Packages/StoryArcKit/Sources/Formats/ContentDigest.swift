public import Foundation

public import StoryArcCore

internal import CryptoKit

/// What makes a moved file the same file.
///
/// Split from ``PublicationIndexer`` itself, which it is still spelled as part of: the
/// rule below is one decision with a long justification, and it reads better beside the
/// reasoning than buried among the per-container branches. Android keeps it inside
/// `PublicationIndexer` because a Kotlin `object` cannot be split across files — the API
/// is the same on both, and so are the bytes.
extension PublicationIndexer {
    /// How many bytes at each end of a publication the digest reads.
    ///
    /// ADR-0006 writes the rule as "the file's size plus the first and last 64 KB".
    /// The window here is larger, and is deliberately **not** being reduced to the
    /// number in that sentence: the digest string is a bare hex SHA-256 with no scheme
    /// tag, so changing what it is computed from turns every digest already written
    /// into a stranger, and the records that carry one — a file Android was handed
    /// from outside the app — have no path to fall back to. Eight times cheaper is not
    /// worth losing them. What ADR-0006 actually decides is the *shape* — size, head,
    /// tail, no full read — and that is unchanged.
    private static let digestWindow = 512 * 1024

    /// A content digest for one publication: what makes a moved file the same file.
    ///
    /// **SHA-256 over three things, in this order:** the source's length as eight
    /// little-endian bytes, its first ``digestWindow`` bytes, and its last
    /// ``digestWindow`` bytes — the tail omitted when the source is no longer than the
    /// window, because the head already covered every byte there is.
    ///
    /// *Why not the whole file.* A comic is tens to hundreds of megabytes and this
    /// runs for every publication a folder walk finds. Reading all of it would put
    /// gigabytes of I/O in front of the first screen of covers, which
    /// `local-library` gives three seconds.
    ///
    /// *Why not the name.* The name is the one thing a rename changes, and a rename
    /// losing someone's place is the whole reason this exists.
    ///
    /// *Why the raw bytes and not the archive's contents.* Two entries beyond the
    /// central directory would make this a parse, and AGENTS.md is blunt that the
    /// central directory is a ZIP's only authority — a data descriptor leaves zeros in
    /// the local headers, so a digest built from those would agree between two
    /// unrelated archives. Hashing bytes takes no position on what the container says
    /// about itself: `data-descriptor.cbz` and `truncated.cbz` digest exactly as
    /// readily as a well-formed one, and a file too broken to index still gets an
    /// identity.
    ///
    /// *What it cannot tell apart.* Two files of the same length differing only in
    /// the middle. For a comic that means an archive re-compressed at a different
    /// level to the same byte count, which is not a thing that happens by accident —
    /// and the accepted trade for reading a megabyte instead of four hundred.
    /// `PublicationIndexerTests` asserts it rather than leaving it to be discovered.
    ///
    /// *Where the bytes come from.* A ``RandomAccessSource``, so the caller passes the
    /// handle it already opened to sniff the format and read the central directory:
    /// the reads land on pages the indexer has just touched, and nothing is opened
    /// twice. ADR-0008's interface is what makes that possible, and it is the same
    /// reason this works over a share without a full transfer.
    public static func contentDigest(of source: any RandomAccessSource) async throws -> String {
        var hasher = SHA256()
        withUnsafeBytes(of: source.length.littleEndian) { hasher.update(bufferPointer: $0) }
        hasher.update(data: try await source.read(offset: 0, count: digestWindow))
        if source.length > Int64(digestWindow) {
            let (tail, _) = try await source.readTail(count: digestWindow)
            hasher.update(data: tail)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// The digest of a local file. See ``contentDigest(of:)`` for what is hashed.
    public static func contentDigest(fileAt url: URL) async throws -> String {
        try await contentDigest(of: FileSource(url: url))
    }
    /// An identity carrying both what the publication *is* and where it was found.
    ///
    /// ADR-0006's rules 2 and 3 together. The path is what the app files the
    /// publication under (`PublicationIdentity.stableID`); the digest is what
    /// recognises it again after a rename or a move, because
    /// `PublicationIdentity.matches` and `ProgressStore` both try the digest before
    /// the path. A `nil` digest is the honest answer for something that has no file
    /// of its own — a folder of images — and leaves the path as the only key, which
    /// is what every publication had before the digest was computed at all.
    static func identity(forPath path: String, digest: String?) -> PublicationIdentity {
        PublicationIdentity(
            contentDigest: digest,
            normalizedPath: (path as NSString).standardizingPath
        )
    }
}
