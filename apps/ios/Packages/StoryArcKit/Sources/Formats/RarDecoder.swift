public import Foundation

internal import CLibarchive

/// Decompresses RAR entries, and nothing else.
///
/// This is the whole of libarchive's job in StoryArc. `RarReader` already answers
/// every question the library asks — entry names, sizes, the cover, solid,
/// encrypted — from headers alone, and reads stored entries directly. What it
/// cannot do is undo RAR's LZ and PPMd coding, which is a real codec and the one
/// thing worth a C dependency (ADR-0005).
///
/// So the seam is deliberately narrow: a path in, entry bytes out. Nothing above
/// this type knows libarchive exists, which is what makes the dependency
/// replaceable and keeps the untrusted-input surface to a single call.
///
/// ponytail: takes a file path rather than a `RandomAccessSource`. Decompressing
/// an entry is sequential by nature, and a remote publication is downloaded
/// before it is read anyway — `RarReader` is what makes *indexing* a remote CBR
/// cheap. Wire the callback API in if streaming a compressed remote CBR ever
/// becomes a real requirement.
public enum RarDecoder {
    public enum DecodeError: Error, Equatable {
        /// libarchive refused to open the archive at all.
        case cannotOpen(String)
        /// The archive opened but the entry was never reached.
        case entryNotFound(String)
        /// libarchive stopped part-way through the entry's data.
        case truncated(path: String, expected: Int, got: Int)
        /// The entry claims — or delivers — more than ``RarDecoder/maxEntryBytes``.
        case tooLarge(path: String, declared: Int, cap: Int)
        /// libarchive's own message, kept verbatim so a bug report can carry it.
        case libarchive(String)
    }

    /// Reading in 64 KB blocks. Large enough that a comic page is a handful of
    /// reads, small enough not to matter on a phone.
    private static let blockSize = 64 * 1024

    /// A ceiling on one entry's unpacked size.
    ///
    /// The size in a RAR header is untrusted: without a cap, a crafted archive
    /// claiming a petabyte drives the loop until jetsam kills the app. 512 MB is
    /// far past any real comic page.
    ///
    /// The same number as Android's `MAX_ENTRY_BYTES` in `rar_decoder.c`, and the
    /// one `SECURITY.md` publishes — which was true on one platform only until
    /// this existed, because the declared size seeded the buffer here and never
    /// bounded the loop.
    public static let maxEntryBytes = 512 * 1024 * 1024

    /// Unpacked bytes for one entry, found by its path inside the archive.
    ///
    /// Walks headers until the path matches. That is linear, which is correct for
    /// RAR: a solid archive *must* be read in order, and for a non-solid one
    /// libarchive skips entry data without decompressing it.
    public static func data(forEntryAt path: String, inArchiveAt url: URL) throws -> Data {
        let handle = try open(url)
        defer { archive_read_free(handle) }

        var entry: OpaquePointer?
        while true {
            let status = archive_read_next_header(handle, &entry)
            if status == ARCHIVE_EOF { throw DecodeError.entryNotFound(path) }
            guard status == ARCHIVE_OK || status == ARCHIVE_WARN else {
                throw DecodeError.libarchive(message(handle))
            }
            guard let entry, let name = archive_entry_pathname(entry) else { continue }
            guard String(cString: name) == path else { continue }

            let declared = Int(archive_entry_size(entry))
            return try readCurrentEntry(handle, path: path, declaredSize: declared)
        }
    }

    /// Every entry's unpacked bytes in archive order, for the paths given.
    ///
    /// One pass rather than one open per page. A solid archive makes this the only
    /// affordable shape — reading page 30 there means decompressing 1 to 29, so
    /// asking for pages one at a time would be quadratic.
    public static func data(
        forEntriesAt paths: Set<String>, inArchiveAt url: URL
    ) throws -> [String: Data] {
        guard !paths.isEmpty else { return [:] }
        let handle = try open(url)
        defer { archive_read_free(handle) }

        var found: [String: Data] = [:]
        var entry: OpaquePointer?
        while found.count < paths.count {
            let status = archive_read_next_header(handle, &entry)
            if status == ARCHIVE_EOF { break }
            guard status == ARCHIVE_OK || status == ARCHIVE_WARN else {
                throw DecodeError.libarchive(message(handle))
            }
            guard let entry, let name = archive_entry_pathname(entry) else { continue }
            let path = String(cString: name)
            guard paths.contains(path) else { continue }
            found[path] = try readCurrentEntry(
                handle, path: path, declaredSize: Int(archive_entry_size(entry))
            )
        }
        return found
    }

    /// Entry names and sizes as *libarchive* sees them.
    ///
    /// Not used for indexing — `RarReader` does that without a C library. This
    /// exists so a test can assert the two agree, which is the only way to know
    /// our header parser and the decoder are looking at the same archive.
    public static func entryNames(inArchiveAt url: URL) throws -> [(path: String, size: Int)] {
        let handle = try open(url)
        defer { archive_read_free(handle) }

        var names: [(path: String, size: Int)] = []
        var entry: OpaquePointer?
        while true {
            let status = archive_read_next_header(handle, &entry)
            if status == ARCHIVE_EOF { return names }
            guard status == ARCHIVE_OK || status == ARCHIVE_WARN else {
                throw DecodeError.libarchive(message(handle))
            }
            guard let entry, let name = archive_entry_pathname(entry) else { continue }
            names.append((String(cString: name), Int(archive_entry_size(entry))))
        }
    }

    // MARK: - Private

    /// A read handle with only the RAR readers registered.
    ///
    /// Registering `format_all` would pull every parser libarchive has into the
    /// binary and into reach of a crafted file. Two readers and the null filter is
    /// the whole attack surface, which is also why the other 106 sources are not
    /// vendored.
    private static func open(_ url: URL) throws -> OpaquePointer {
        guard let handle = archive_read_new() else {
            throw DecodeError.cannotOpen("could not allocate an archive reader")
        }
        archive_read_support_format_rar(handle)
        archive_read_support_format_rar5(handle)
        archive_read_support_filter_none(handle)

        let status = url.path.withCString { path in
            archive_read_open_filename(handle, path, blockSize)
        }
        guard status == ARCHIVE_OK else {
            let text = message(handle)
            archive_read_free(handle)
            throw DecodeError.cannotOpen(text)
        }
        return handle
    }

    /// Drains the current entry's data, up to ``maxEntryBytes``.
    ///
    /// `declaredSize` is a header field, so it is untrusted twice over. It is
    /// refused outright when it exceeds the cap — before a byte is read, which is
    /// the whole point: an archive that means to exhaust the device says so in its
    /// header and never gets to prove it. And it seeds the buffer's capacity but
    /// does not bound the loop, so the loop carries the same ceiling for the case
    /// where the header declares nothing at all.
    ///
    /// A mismatch at the end is reported rather than papered over, which is also
    /// what turns a run that hit the ceiling into a failure: `out.count` is then
    /// the cap rather than the declared size.
    ///
    /// Android's `read_entry` in `rar_decoder.c` is the same three checks in the
    /// same order.
    private static func readCurrentEntry(
        _ handle: OpaquePointer, path: String, declaredSize: Int
    ) throws -> Data {
        guard declaredSize >= 0, declaredSize <= maxEntryBytes else {
            throw DecodeError.tooLarge(path: path, declared: declaredSize, cap: maxEntryBytes)
        }
        var out = Data()
        if declaredSize > 0 {
            out.reserveCapacity(declaredSize)
        }
        var block = [UInt8](repeating: 0, count: blockSize)
        while out.count < maxEntryBytes {
            let read = block.withUnsafeMutableBytes { buffer in
                archive_read_data(handle, buffer.baseAddress, buffer.count)
            }
            if read == 0 { break }
            guard read > 0 else { throw DecodeError.libarchive(message(handle)) }
            let room = min(read, maxEntryBytes - out.count)
            out.append(contentsOf: block[0..<room])
        }
        // A short read means the archive claimed more than it delivered. Saying so
        // beats handing a truncated page to the decoder and reporting a corrupt
        // image.
        if declaredSize > 0, out.count != declaredSize {
            throw DecodeError.truncated(path: path, expected: declaredSize, got: out.count)
        }
        return out
    }

    private static func message(_ handle: OpaquePointer) -> String {
        guard let raw = archive_error_string(handle) else { return "unknown libarchive error" }
        return String(cString: raw)
    }
}
