package app.storyarc.core.format

/** One regular file inside a TAR archive. */
data class TarEntry(
    val path: String,
    val size: Long,
    /**
     * Where the file's bytes start. TAR stores data uncompressed and contiguous,
     * so this offset plus [size] is the whole read — no decode step at all.
     */
    val dataOffset: Long,
)

sealed class TarException(message: String) : Exception(message) {
    class Malformed(message: String) : TarException(message)

    /** No `ustar` magic and no parsable header. The file is not a TAR. */
    class NotTar : TarException("not a tar archive")
}

/**
 * A TAR reader, written here rather than delegated to libarchive.
 *
 * TAR is 512-byte blocks with fixed-offset ASCII fields: there is no
 * compression, no central directory and no bit-packing. Reading it needs no C
 * library, which is the same reasoning ADR-0008 applies to ZIP — and it means
 * CBT ships without waiting on the libarchive vendoring question.
 *
 * Every read goes through [RandomAccessSource], so indexing a CBT on an SMB
 * share fetches one 512-byte header per entry rather than the whole file.
 *
 * This parser runs on untrusted input. `SECURITY.md` names archive parsing as
 * the largest attack surface in the app, so no length taken from a header is
 * used before it is checked against the source, and every header's checksum is
 * verified.
 */
class TarReader private constructor(
    private val source: RandomAccessSource,
    /**
     * Regular files only, in archive order. Directories, symlinks and metadata
     * blocks are consumed and dropped.
     */
    val entries: List<TarEntry>,
) {

    companion object {
        private const val BLOCK_SIZE = 512

        /**
         * `ustar` sits at offset 257, which is why format sniffing has to read
         * further into a TAR than into any other container.
         */
        const val MAGIC_OFFSET = 257

        /** A long-name block's data is a path, so a sane ceiling is enough. */
        private const val MAX_NAME_BYTES = 8192

        suspend fun open(source: RandomAccessSource): TarReader {
            val found = mutableListOf<TarEntry>()
            var offset = 0L
            // Set by a GNU `L` block or a pax `path=` record, and consumed by
            // the next real entry.
            var pendingLongName: String? = null
            var sawAnyHeader = false

            while (offset + BLOCK_SIZE <= source.length) {
                val block = source.readExactly(offset, BLOCK_SIZE)
                offset += BLOCK_SIZE

                // Two consecutive zero blocks end an archive, but one is enough
                // to stop: there is nothing after it a reader could use.
                if (block.all { it == 0.toByte() }) break

                if (!checksumMatches(block)) {
                    // A bad checksum on the very first block means this was
                    // never a TAR. Later on it means the archive is damaged, and
                    // `publication-formats` requires returning what was readable.
                    if (!sawAnyHeader) throw TarException.NotTar()
                    break
                }
                sawAnyHeader = true

                val size = sizeOf(block)
                val dataOffset = offset
                // Entry data is padded to a whole number of blocks.
                offset += (size + BLOCK_SIZE - 1) / BLOCK_SIZE * BLOCK_SIZE

                if (size < 0 || dataOffset + size > source.length) {
                    // The header claims more bytes than the file holds. Stop
                    // rather than trusting the next offset, which is now
                    // meaningless.
                    break
                }

                when (block[156].toInt() and 0xFF) {
                    0x4C -> // 'L' — GNU long name; this block's data names the next entry.
                        pendingLongName = trimmedString(
                            source.readExactly(dataOffset, minOf(size, MAX_NAME_BYTES.toLong()).toInt()),
                        )

                    0x78, 0x67 -> { // 'x', 'g' — pax extended header.
                        val raw =
                            source.readExactly(dataOffset, minOf(size, MAX_NAME_BYTES.toLong()).toInt())
                        pendingLongName = paxPath(raw) ?: pendingLongName
                    }

                    0x30, 0x00 -> { // '0' or NUL — a regular file.
                        val path = pendingLongName ?: pathOf(block)
                        pendingLongName = null
                        if (path.isNotEmpty() && !path.endsWith("/")) {
                            found += TarEntry(path, size, dataOffset)
                        }
                    }

                    // Directories, symlinks, devices, FIFOs. Not pages.
                    else -> pendingLongName = null
                }
            }

            if (!sawAnyHeader) throw TarException.NotTar()
            return TarReader(source, found)
        }

        /**
         * The header checksum, treating its own eight bytes as spaces.
         *
         * Historic writers disagreed on whether the bytes are signed, so both
         * sums are accepted. This is the only integrity check TAR offers, and it
         * is what stops a random 512 bytes from being read as an entry.
         */
        private fun checksumMatches(block: ByteArray): Boolean {
            if (block.size != BLOCK_SIZE) return false
            val declared = runCatching { octal(block, 148, 156) }.getOrNull() ?: return false
            var unsigned = 0L
            var signed = 0L
            for (index in block.indices) {
                if (index in 148 until 156) {
                    unsigned += 0x20
                    signed += 0x20
                } else {
                    unsigned += (block[index].toInt() and 0xFF).toLong()
                    signed += block[index].toLong()
                }
            }
            return declared == unsigned || declared == signed
        }

        /** USTAR splits long paths across a 155-byte prefix and a 100-byte name. */
        private fun pathOf(block: ByteArray): String {
            val name = trimmedString(block.copyOfRange(0, 100))
            val isUstar = String(block, MAGIC_OFFSET, 5, Charsets.US_ASCII) == "ustar"
            if (!isUstar) return name
            val prefix = trimmedString(block.copyOfRange(345, 500))
            return if (prefix.isEmpty()) name else "$prefix/$name"
        }

        private fun sizeOf(block: ByteArray): Long {
            // GNU base-256: the high bit of the first byte marks a big-endian
            // integer instead of ASCII octal, for sizes that will not fit in 11
            // octal digits.
            if (block[124].toInt() and 0x80 != 0) {
                var value = (block[124].toInt() and 0x7F).toLong()
                for (index in 125 until 136) {
                    if (value >= Long.MAX_VALUE shr 8) {
                        throw TarException.Malformed("size overflows")
                    }
                    value = value shl 8 or (block[index].toLong() and 0xFF)
                }
                return value
            }
            return octal(block, 124, 136)
        }

        private fun octal(block: ByteArray, from: Int, until: Int): Long {
            var value = 0L
            var sawDigit = false
            for (index in from until until) {
                val byte = block[index].toInt() and 0xFF
                if (byte == 0 || byte == 0x20) {
                    // Trailing NUL or space terminates the field; leading ones
                    // are padding.
                    if (sawDigit) break else continue
                }
                if (byte < 0x30 || byte > 0x37) throw TarException.Malformed("not an octal field")
                if (value >= Long.MAX_VALUE shr 3) throw TarException.Malformed("octal field overflows")
                value = value shl 3 or (byte - 0x30).toLong()
                sawDigit = true
            }
            return value
        }

        /**
         * A NUL-terminated fixed-width field. UTF-8 where possible,
         * ISO-8859-1 otherwise, so no byte sequence costs us an entry name.
         */
        private fun trimmedString(bytes: ByteArray): String {
            val end = bytes.indexOfFirst { it == 0.toByte() }.let { if (it < 0) bytes.size else it }
            val slice = bytes.copyOfRange(0, end)
            val utf8 = String(slice, Charsets.UTF_8)
            // A replacement character means the bytes were not UTF-8; keeping
            // every byte round-trippable beats losing the name.
            return if (utf8.contains('�')) String(slice, Charsets.ISO_8859_1) else utf8
        }

        /**
         * The `path=` record from a pax extended header. Records are
         * `<length> <key>=<value>\n`, with the length counting the whole record.
         */
        private fun paxPath(data: ByteArray): String? {
            var rest = String(data, Charsets.UTF_8)
            while (true) {
                val space = rest.indexOf(' ')
                if (space <= 0) return null
                val declared = rest.substring(0, space).toIntOrNull() ?: return null
                if (declared <= 0 || declared > rest.length) return null
                val body = rest.substring(space + 1, declared).trimEnd('\n')
                rest = rest.substring(declared)
                if (body.startsWith("path=")) return body.removePrefix("path=")
            }
        }
    }

    /** A whole entry. No decompression: TAR stores bytes verbatim. */
    suspend fun data(entry: TarEntry): ByteArray {
        if (entry.size < 0 || entry.dataOffset < 0 || entry.dataOffset + entry.size > source.length) {
            throw TarException.Malformed("entry lies outside the source")
        }
        return source.readExactly(entry.dataOffset, entry.size.toInt())
    }
}
