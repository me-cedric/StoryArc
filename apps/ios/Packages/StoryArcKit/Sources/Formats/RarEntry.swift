// The value types `RarReader` hands out, split from the reader at its 400-line cap.

/// One file inside a RAR archive.
public struct RarEntry: Sendable, Equatable {
    public let path: String
    /// Size after decompression. What the page decoder will see.
    public let size: Int64
    /// Size on disk. Equal to `size` when the entry is stored.
    public let packedSize: Int64
    /// Where the entry's packed bytes start.
    public let dataOffset: Int64
    /// Stored entries carry their bytes verbatim, so they need no decoder at all.
    public let isStored: Bool
    /// Solid entries cannot be decompressed without the entries before them.
    public let isSolid: Bool
    public let isEncrypted: Bool
    /// Where the entry's own header block starts. With ``dataOffset`` and ``packedSize`` it
    /// bounds everything a decoder needs for a non-solid entry.
    public let headerOffset: Int64
}

/// Which RAR format an archive uses. They share an extension and nothing else:
/// different signatures, different header layouts, different integer encodings.
public enum RarGeneration: String, Sendable {
    case rar4, rar5
}

public enum RarError: Error, Equatable {
    case malformed(String)
    case notRar
    /// The entry is compressed, and decompressing it needs a decoder StoryArc
    /// does not carry yet. Distinct from `malformed`: the archive is fine.
    case needsDecoder(method: Int)
    /// More headers than any real publication has. A guard against a crafted
    /// file that would otherwise be read into an unbounded array.
    case tooManyEntries
}
