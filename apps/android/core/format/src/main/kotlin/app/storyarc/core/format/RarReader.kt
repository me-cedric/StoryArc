package app.storyarc.core.format

/** One file inside a RAR archive. */
data class RarEntry(
    val path: String,
    /** Size after decompression. What the page decoder will see. */
    val size: Long,
    /** Size on disk. Equal to [size] when the entry is stored. */
    val packedSize: Long,
    /** Where the entry's packed bytes start. */
    val dataOffset: Long,
    /** Stored entries carry their bytes verbatim, so they need no decoder at all. */
    val isStored: Boolean,
    /** Solid entries cannot be decompressed without the entries before them. */
    val isSolid: Boolean,
    val isEncrypted: Boolean,
)

/**
 * Which RAR format an archive uses. They share an extension and nothing else:
 * different signatures, different header layouts, different integer encodings.
 */
enum class RarGeneration { RAR4, RAR5 }

sealed class RarException(message: String) : Exception(message) {
    class Malformed(message: String) : RarException(message)

    class NotRar : RarException("not a rar archive")

    /**
     * The entry is compressed, and decompressing it needs a decoder StoryArc
     * does not carry yet. Distinct from [Malformed]: the archive is fine.
     */
    class NeedsDecoder(val method: Int) : RarException("entry needs a decoder, method $method")

    /**
     * More headers than any real publication has. A guard against a crafted file
     * that would otherwise be read into an unbounded list.
     */
    class TooManyEntries : RarException("archive declares too many entries")
}

/**
 * Reads RAR *headers*, and the bytes of stored entries.
 *
 * Deliberately not a RAR decoder. Everything the library needs in order to index
 * a publication — page names, page sizes, the cover, whether the archive is
 * solid or encrypted — lives in the headers, and headers are a documented layout
 * with no compression in them. So this is written here, the same reasoning
 * ADR-0008 applies to ZIP, and libarchive's remaining job shrinks to one
 * function: turn a compressed entry's packed bytes into unpacked bytes.
 *
 * The practical payoff is that the answers `Streaming capability per format`
 * needs are available before any C library is linked, and that a solid archive is
 * recognised from its flags rather than from a decoder failing halfway.
 *
 * This parser runs on untrusted input. `SECURITY.md` names archive parsing as the
 * largest attack surface in the app: every offset is bounds-checked against the
 * source before use, no length from a header is used to allocate, and the entry
 * count is capped.
 */
class RarReader private constructor(
    private val source: RandomAccessSource,
    val generation: RarGeneration,
    val entries: List<RarEntry>,
    /** The archive-level solid flag. Individual entries carry their own. */
    val isSolidArchive: Boolean,
    /**
     * Set when headers or entries are encrypted. `publication-formats` requires
     * saying so rather than prompting for a password.
     */
    val isEncrypted: Boolean,
) {
    /**
     * True when any entry cannot be reached without decompressing the ones before
     * it — the question `Streaming capability per format` asks. A solid archive is
     * never streamable, on either generation.
     */
    val isSolid: Boolean get() = isSolidArchive || entries.any { it.isSolid }

    /**
     * Whether the archive can be read at all once it is local.
     *
     * This is where the two generations part company, measured rather than
     * assumed. libarchive reads a solid RAR5 completely — its own test suite's
     * `test_read_format_rar5_solid.rar` yields all seven entries. It cannot read a
     * solid RAR4 at all: `read_header()` returns `ARCHIVE_FATAL` on any file
     * header carrying `FHD_SOLID`, with no compression-method check and no
     * fallback. So a solid RAR4 is unsupported and downloading it changes nothing,
     * while a solid RAR5 is merely download-only.
     */
    val isReadableWhenLocal: Boolean get() = !(isSolid && generation == RarGeneration.RAR4)

    /** A read position, so [vint] can advance it the way an `inout` would. */
    class Cursor(var value: Int)

    companion object {
        val RAR4_SIGNATURE = byteArrayOf(0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x00)
        val RAR5_SIGNATURE = byteArrayOf(0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x01, 0x00)

        /** A comic has hundreds of pages. Tens of thousands means a crafted file. */
        private const val ENTRY_LIMIT = 50_000

        /** Headers are small. Anything claiming more is not a header. */
        private const val MAX_HEADER_SIZE = 1 shl 20

        suspend fun open(source: RandomAccessSource): RarReader {
            val head = source.read(0, RAR5_SIGNATURE.size)
            return when {
                head.startsWith(RAR5_SIGNATURE) -> parseRar5(source)
                head.startsWith(RAR4_SIGNATURE) -> parseRar4(source)
                else -> throw RarException.NotRar()
            }
        }

        private fun ByteArray.startsWith(signature: ByteArray) =
            size >= signature.size && signature.indices.all { this[it] == signature[it] }

        // RAR4.

        private suspend fun parseRar4(source: RandomAccessSource): RarReader {
            val entries = mutableListOf<RarEntry>()
            var solidArchive = false
            var encrypted = false
            var offset = RAR4_SIGNATURE.size.toLong()

            while (offset + 7 <= source.length) {
                val head = source.readExactly(offset, 7)
                val flags = (head[3].toInt() and 0xFF) or ((head[4].toInt() and 0xFF) shl 8)
                val headerSize = (head[5].toInt() and 0xFF) or ((head[6].toInt() and 0xFF) shl 8)
                if (headerSize < 7 || headerSize > MAX_HEADER_SIZE ||
                    offset + headerSize > source.length
                ) {
                    break
                }

                when (head[2].toInt() and 0xFF) {
                    0x73 -> { // main archive header
                        solidArchive = flags and 0x0008 != 0
                        // 0x0080 means the block headers themselves are
                        // encrypted, so nothing past this point can be parsed.
                        if (flags and 0x0080 != 0) {
                            return RarReader(source, RarGeneration.RAR4, emptyList(), solidArchive, true)
                        }
                        offset += headerSize
                        continue
                    }

                    0x7B -> break // end of archive

                    0x74 -> Unit // file header, handled below

                    else -> {
                        val addSize =
                            if (flags and 0x8000 != 0) rar4AddSize(source, offset, headerSize) else 0L
                        offset += headerSize + addSize
                        continue
                    }
                }

                val header = source.readExactly(offset, headerSize)
                if (header.size < 32) break

                var packed = le32(header, 7)
                var unpacked = le32(header, 11)
                val method = header[25].toInt() and 0xFF
                val nameSize = (header[26].toInt() and 0xFF) or ((header[27].toInt() and 0xFF) shl 8)
                var cursor = 32
                if (flags and 0x0100 != 0) { // LHD_LARGE: 64-bit sizes in two halves
                    if (header.size < cursor + 8) break
                    packed = packed or (le32(header, cursor) shl 32)
                    unpacked = unpacked or (le32(header, cursor + 4) shl 32)
                    cursor += 8
                }
                if (nameSize < 0 || cursor + nameSize > header.size) break

                val rawName = header.copyOfRange(cursor, cursor + nameSize)
                val isDirectory = flags and 0x00E0 == 0x00E0
                val entryEncrypted = flags and 0x0004 != 0
                if (entryEncrypted) encrypted = true

                val dataOffset = offset + headerSize
                if (!isDirectory && packed >= 0 && unpacked >= 0 &&
                    dataOffset + packed <= source.length
                ) {
                    if (entries.size >= ENTRY_LIMIT) throw RarException.TooManyEntries()
                    entries += RarEntry(
                        path = rar4Name(rawName, isUnicode = flags and 0x0200 != 0),
                        size = unpacked,
                        packedSize = packed,
                        dataOffset = dataOffset,
                        isStored = method == 0x30,
                        isSolid = flags and 0x0010 != 0,
                        isEncrypted = entryEncrypted,
                    )
                }
                offset = dataOffset + maxOf(packed, 0)
            }

            return RarReader(source, RarGeneration.RAR4, entries, solidArchive, encrypted)
        }

        /** A non-file block's payload size, directly after its 7-byte head. */
        private suspend fun rar4AddSize(
            source: RandomAccessSource,
            offset: Long,
            headerSize: Int,
        ): Long {
            if (headerSize < 11) return 0
            return le32(source.readExactly(offset, 11), 7)
        }

        /**
         * RAR4 stores a long name as `asciiName <packed unicode>`. The ASCII
         * half is always present and always valid, so it is what we use.
         *
         * ponytail: the packed-unicode half needs RAR's own name codec. Page
         * paths are ASCII in every comic that exists; revisit if a real file
         * proves otherwise.
         */
        private fun rar4Name(raw: ByteArray, isUnicode: Boolean): String {
            val end =
                if (isUnicode) {
                    raw.indexOfFirst { it == 0.toByte() }.let { if (it < 0) raw.size else it }
                } else {
                    raw.size
                }
            val slice = raw.copyOfRange(0, end)
            val utf8 = String(slice, Charsets.UTF_8)
            return if (utf8.contains('�')) String(slice, Charsets.ISO_8859_1) else utf8
        }

        private fun le32(bytes: ByteArray, at: Int): Long {
            if (at + 4 > bytes.size) return 0
            return (bytes[at].toLong() and 0xFF) or
                ((bytes[at + 1].toLong() and 0xFF) shl 8) or
                ((bytes[at + 2].toLong() and 0xFF) shl 16) or
                ((bytes[at + 3].toLong() and 0xFF) shl 24)
        }

        // RAR5.

        private suspend fun parseRar5(source: RandomAccessSource): RarReader {
            val entries = mutableListOf<RarEntry>()
            var solidArchive = false
            var encrypted = false
            var offset = RAR5_SIGNATURE.size.toLong()

            while (offset + 8 <= source.length) {
                // The header's own size is a vint, so read a window big enough to
                // hold the size field and then the header it describes.
                val window = source.read(offset, 64)
                if (window.size <= 4) break
                val sizeCursor = Cursor(4) // past the header CRC32
                val headerSize = vint(window, sizeCursor)
                if (headerSize == null || headerSize <= 0 || headerSize > MAX_HEADER_SIZE) break

                val headerStart = offset + sizeCursor.value
                if (headerStart + headerSize > source.length) break
                val bytes = source.readExactly(headerStart, headerSize.toInt())
                val cursor = Cursor(0)

                val type = vint(bytes, cursor) ?: break
                val flags = vint(bytes, cursor) ?: break
                var extraSize = 0L
                var dataSize = 0L
                if (flags and 0x0001L != 0L) extraSize = vint(bytes, cursor) ?: 0L
                if (flags and 0x0002L != 0L) dataSize = vint(bytes, cursor) ?: 0L

                val dataOffset = headerStart + headerSize
                val nextOffset = dataOffset + maxOf(dataSize, 0)

                when (type) {
                    1L -> vint(bytes, cursor)?.let { solidArchive = it and 0x0004L != 0L }

                    // Encrypted headers: nothing past this point can be parsed.
                    4L -> return RarReader(
                        source, RarGeneration.RAR5, emptyList(), solidArchive, true,
                    )

                    5L -> return RarReader(
                        source, RarGeneration.RAR5, entries, solidArchive, encrypted,
                    )

                    2L, 3L -> {
                        val fileFlags = vint(bytes, cursor)
                        val unpacked = vint(bytes, cursor)
                        val attributes = vint(bytes, cursor)
                        if (fileFlags == null || unpacked == null || attributes == null) break
                        if (fileFlags and 0x0002L != 0L) cursor.value += 4 // mtime
                        if (fileFlags and 0x0004L != 0L) cursor.value += 4 // data CRC32
                        val compression = vint(bytes, cursor)
                        val hostOs = vint(bytes, cursor)
                        val nameSize = vint(bytes, cursor)
                        if (compression == null || hostOs == null || nameSize == null) break
                        if (nameSize < 0 || cursor.value + nameSize > bytes.size) break
                        val name = String(
                            bytes, cursor.value, nameSize.toInt(), Charsets.UTF_8,
                        )

                        val entryEncrypted = extraSize > 0 &&
                            hasEncryptionRecord(bytes, (headerSize - extraSize).toInt())
                        if (entryEncrypted) encrypted = true

                        // Only real files. A service header carries metadata, and
                        // fileFlags bit 0 marks a directory.
                        if (type == 2L && fileFlags and 0x0001L == 0L &&
                            dataOffset + dataSize <= source.length
                        ) {
                            if (entries.size >= ENTRY_LIMIT) throw RarException.TooManyEntries()
                            entries += RarEntry(
                                path = name,
                                size = unpacked,
                                packedSize = dataSize,
                                dataOffset = dataOffset,
                                // CompressionInfo bits 7-9 hold the method; 0 is store.
                                isStored = (compression shr 7) and 0x07L == 0L,
                                isSolid = compression and 0x40L != 0L,
                                isEncrypted = entryEncrypted,
                            )
                        }
                    }

                    else -> Unit
                }

                if (nextOffset <= offset) break // never move backwards
                offset = nextOffset
            }

            return RarReader(source, RarGeneration.RAR5, entries, solidArchive, encrypted)
        }

        /**
         * Whether a file header's extra area declares encryption (record type 1).
         * Records are `size(vint) type(vint) payload`, with `size` covering the
         * type and payload.
         */
        private fun hasEncryptionRecord(bytes: ByteArray, start: Int): Boolean {
            var at = start
            if (at < 0 || at >= bytes.size) return false
            while (at < bytes.size) {
                val probe = Cursor(at)
                val size = vint(bytes, probe) ?: return false
                if (size <= 0) return false
                val typeCursor = Cursor(probe.value)
                val type = vint(bytes, typeCursor) ?: return false
                if (type == 1L) return true
                val next = probe.value + size.toInt()
                if (next <= at || next > bytes.size) return false
                at = next
            }
            return false
        }

        /**
         * RAR5's variable-length integer: seven bits per byte, low group first,
         * high bit marks continuation. Capped at ten groups so a run of 0x80
         * bytes cannot spin, and rejected on overflow rather than wrapping.
         */
        fun vint(bytes: ByteArray, cursor: Cursor): Long? {
            var value = 0L
            var shift = 0
            var groups = 0
            while (cursor.value < bytes.size && groups < 10) {
                val byte = bytes[cursor.value].toInt() and 0xFF
                cursor.value++
                groups++
                if (shift >= 63) return null
                value = value or ((byte and 0x7F).toLong() shl shift)
                if (byte and 0x80 == 0) return if (value >= 0) value else null
                shift += 7
            }
            return null
        }
    }

    /**
     * A stored entry's bytes. Compressed entries throw [RarException.NeedsDecoder],
     * which is the seam libarchive fills.
     */
    suspend fun data(entry: RarEntry): ByteArray {
        if (entry.isEncrypted) throw RarException.NeedsDecoder(-1)
        if (!entry.isStored) throw RarException.NeedsDecoder(1)
        if (entry.dataOffset < 0 || entry.packedSize < 0 ||
            entry.dataOffset + entry.packedSize > source.length
        ) {
            throw RarException.Malformed("entry lies outside the source")
        }
        return source.readExactly(entry.dataOffset, entry.packedSize.toInt())
    }
}
