public import Foundation

internal import Compression

// DEFLATE, split out of `ZipReader`.
//
// The container parsing and the decompression are two different jobs that
// happen to live behind one type: one reads offsets and lengths, the other hands
// bytes to the platform (ADR-0008). Keeping them in one file made it the longest
// in the package and neither half easier to read.

extension ZipReader {
    /// Raw DEFLATE, via the platform. We parse the container; we do not implement
    /// compression (ADR-0008).
    static func inflate(_ compressed: Data, expectedSize: Int) throws -> Data {
        guard expectedSize >= 0 else { throw ZipError.malformed("negative uncompressed size") }
        // Zero can mean two things. An entry that really is empty has no compressed
        // bytes either; an entry recovered from a local header with a data
        // descriptor has bytes and no declared size. Only the first is empty.
        guard expectedSize > 0 || !compressed.isEmpty else { return Data() }

        if expectedSize == 0 {
            return try inflateUnknownSize(compressed)
        }

        // `expectedSize` comes from the central directory, so it is attacker
        // controlled. Capped so a lying header cannot make us allocate the world.
        let capacity = min(expectedSize, 512 * 1024 * 1024)
        var output = Data(count: capacity)

        let written: Int = output.withUnsafeMutableBytes { destination in
            compressed.withUnsafeBytes { origin in
                guard let destinationBase = destination.bindMemory(to: UInt8.self).baseAddress,
                      let originBase = origin.bindMemory(to: UInt8.self).baseAddress
                else { return 0 }
                return compression_decode_buffer(
                    destinationBase, capacity,
                    originBase, compressed.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }

        guard written > 0 else { throw ZipError.inflateFailed }
        return output.prefix(written)
    }

    /// Inflates when the uncompressed size is not known.
    ///
    /// Only reachable through recovery: a local header that used a data descriptor
    /// declares no size, and in recovery there is no central directory to ask. The
    /// buffer starts at a generous multiple of the compressed size and doubles
    /// while the result exactly fills it, which is the signal that it was clipped.
    private static func inflateUnknownSize(_ compressed: Data) throws -> Data {
        var capacity = max(compressed.count * 8, 64 * 1024)
        let ceiling = 512 * 1024 * 1024
        while true {
            var output = Data(count: capacity)
            let written: Int = output.withUnsafeMutableBytes { destination in
                compressed.withUnsafeBytes { origin in
                    guard let destinationBase = destination.bindMemory(to: UInt8.self).baseAddress,
                          let originBase = origin.bindMemory(to: UInt8.self).baseAddress
                    else { return 0 }
                    return compression_decode_buffer(
                        destinationBase, capacity,
                        originBase, compressed.count,
                        nil, COMPRESSION_ZLIB
                    )
                }
            }
            guard written > 0 else { throw ZipError.inflateFailed }
            // A result that exactly fills the buffer may have been truncated, so
            // try again with more room — unless there is no more room to give.
            if written < capacity || capacity >= ceiling { return output.prefix(written) }
            capacity = min(capacity * 2, ceiling)
        }
    }
}
