public import Foundation

/// Copies a ``RandomAccessSource`` to a local file in fixed-size chunks.
///
/// A single `source.read(offset: 0, count: Int(source.length))` asks a remote source for the
/// whole file in one message, and every transport this app speaks refuses that past some
/// size: an SMB read reply is capped by the wire format's own `UInt32` length (see
/// `SmbClient.readOnce`), and holding a multi-hundred-megabyte `Data` in memory to write it
/// back out is its own way to lose to a large publication before the size is even reached.
/// This is the one place either happens — the share browser's download and the offline-copy
/// action both call it rather than each carrying its own one-shot read.
public enum ChunkedCopy {
    /// 4 MiB. Comfortably under what a server negotiates for a single SMB read, and small
    /// enough that memory use stays flat regardless of the source's length.
    public static let defaultChunkSize = 4 << 20

    /// Copies `source` into `destination`, overwriting a stale file already there.
    ///
    /// Written to a sibling `.partial` file and moved into place only once every chunk has
    /// landed, so a reader who looks at `destination` mid-copy — or a copy the app is killed
    /// during — sees either the previous file or the finished one, never a truncated one
    /// under the name the rest of the app already trusts.
    public static func copy(
        _ source: any RandomAccessSource,
        to destination: URL,
        chunkSize: Int = defaultChunkSize
    ) async throws {
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let partial = destination.appendingPathExtension("partial")
        try? FileManager.default.removeItem(at: partial)
        guard FileManager.default.createFile(atPath: partial.path, contents: nil) else {
            throw SourceError.unreadable
        }
        let handle = try FileHandle(forWritingTo: partial)

        do {
            var offset: Int64 = 0
            while offset < source.length {
                let count = Int(min(Int64(chunkSize), source.length - offset))
                let bytes = try await source.read(offset: offset, count: count)
                // A source that stops short of the length it stated would otherwise land as
                // a truncated file under the finished name, recorded as a whole download.
                guard !bytes.isEmpty else { throw SourceError.unreadable }
                try handle.write(contentsOf: bytes)
                offset += Int64(bytes.count)
            }
        } catch {
            try? handle.close()
            try? FileManager.default.removeItem(at: partial)
            throw error
        }

        try handle.close()
        _ = try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: partial, to: destination)
    }
}
