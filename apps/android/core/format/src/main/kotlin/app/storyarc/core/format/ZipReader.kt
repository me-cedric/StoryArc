package app.storyarc.core.format

import java.util.zip.Inflater

sealed class ZipException(message: String) : Exception(message) {
    /** No End of Central Directory record found. Either not a ZIP, or truncated. */
    class NoCentralDirectory : ZipException("no end of central directory record")
    class Malformed(detail: String) : ZipException("malformed zip: $detail")

    /**
     * General-purpose bit 0 is set. `publication-formats` requires StoryArc to
     * say the archive is protected rather than prompt for a password.
     */
    class Encrypted : ZipException("archive is encrypted")
    class UnsupportedCompression(val method: Int) : ZipException("unsupported method $method")
    class InflateFailed : ZipException("inflate failed")
}

/**
 * One entry, as described by the central directory.
 *
 * **The central directory is the only authority.** Local headers are read for
 * their name and extra-field lengths and never trusted for sizes — with a data
 * descriptor they legitimately contain zeros. ADR-0008's central rule.
 */
data class ZipEntry(
    val path: String,
    val compressedSize: Long,
    val uncompressedSize: Long,
    val localHeaderOffset: Long,
    val compressionMethod: Int,
    val isEncrypted: Boolean,
) {
    val isStored: Boolean get() = compressionMethod == 0
    val isDeflated: Boolean get() = compressionMethod == 8
}

/**
 * Reads a ZIP's index and individual entries with ranged reads.
 *
 * Three reads get any single entry out of an arbitrarily large archive: the
 * tail, the central directory if it did not fit in the tail, then the entry
 * itself. For a 400 MB comic that is megabytes, not gigabytes — which is what
 * makes the `network-share` streaming requirement achievable (ADR-0008).
 *
 * iOS's `ZipReader` mirrors this file. Both are asserted against the same corpus.
 */
class ZipReader private constructor(
    private val source: RandomAccessSource,
    val entries: List<ZipEntry>,
    /**
     * Whether the archive carries a comment. Kept because its presence is exactly
     * what breaks a reader that assumes the EOCD is the last 22 bytes.
     */
    val hasArchiveComment: Boolean,
    /**
     * True when the index was rebuilt by scanning rather than read from a central
     * directory. Sizes then come from local headers, which are less trustworthy —
     * so a caller that cares can say "recovered" rather than pretending.
     */
    val isRecovered: Boolean = false,
) {
    companion object {
        private const val EOCD_SIGNATURE = 0x06054B50
        private const val ZIP64_LOCATOR_SIGNATURE = 0x07064B50
        private const val ZIP64_EOCD_SIGNATURE = 0x06064B50
        private const val CENTRAL_ENTRY_SIGNATURE = 0x02014B50
        private const val LOCAL_HEADER_SIGNATURE = 0x04034B50

        /**
         * The EOCD is at most 22 bytes plus a comment of up to 65,535. Reading
         * 64 KB covers the overwhelming majority of real archives and usually
         * contains the whole central directory too, collapsing three reads into two.
         */
        const val TAIL_PROBE_SIZE = 64 * 1024

        /** Inflate cap: the size comes from the file, so it is attacker controlled. */
        private const val MAX_INFLATE_BYTES = 512 * 1024 * 1024

        suspend fun open(source: RandomAccessSource): ZipReader {
            val (tail, tailOffset) = source.readTail(TAIL_PROBE_SIZE + 22)
            val eocdIndex = lastIndexOf(EOCD_SIGNATURE, tail) ?: throw ZipException.NoCentralDirectory()

            val eocd = ByteReader(tail, eocdIndex)
            eocd.uint32()                    // signature
            eocd.skip(2 + 2 + 2)             // disk numbers, entries on this disk
            val entryCount16 = eocd.uint16()
            val cdSize32 = eocd.uint32()
            val cdOffset32 = eocd.uint32()
            val commentLength = eocd.uint16()

            var cdSize = cdSize32
            var cdOffset = cdOffset32

            // Any sentinel means the real values live in the Zip64 record.
            val needsZip64 = entryCount16 == 0xFFFF || cdSize32 == 0xFFFFFFFFL || cdOffset32 == 0xFFFFFFFFL
            if (needsZip64 || lastIndexOf(ZIP64_LOCATOR_SIGNATURE, tail) != null) {
                val zip64 = readZip64(tail, tailOffset, source)
                if (zip64 != null) {
                    cdSize = zip64.size
                    cdOffset = zip64.offset
                } else if (needsZip64) {
                    throw ZipException.Malformed("zip64 sentinel present but no zip64 record")
                }
            }

            if (cdOffset < 0 || cdSize < 0 || cdOffset + cdSize > source.length) {
                throw ZipException.Malformed("central directory outside the source")
            }

            // If the tail already covers the central directory, slice it rather
            // than issuing a second read. Most comic archives land here.
            val directory: ByteArray = if (cdOffset >= tailOffset) {
                val start = (cdOffset - tailOffset).toInt()
                val end = minOf(start + cdSize.toInt(), tail.size)
                if (start > end) throw ZipException.Malformed("central directory slice invalid")
                tail.copyOfRange(start, end)
            } else {
                source.readExactly(cdOffset, cdSize.toInt())
            }

            return ZipReader(source, parseCentralDirectory(directory), commentLength > 0)
        }

        private fun parseCentralDirectory(data: ByteArray): List<ZipEntry> {
            val reader = ByteReader(data)
            val parsed = mutableListOf<ZipEntry>()

            while (reader.remaining >= 46) {
                if (reader.uint32() != CENTRAL_ENTRY_SIGNATURE.toLong() and 0xFFFFFFFFL) {
                    // Ran off the end of the entries. Not an error: the directory
                    // may be followed by other records.
                    break
                }
                reader.skip(2 + 2)                       // versions
                val flags = reader.uint16()
                val method = reader.uint16()
                reader.skip(2 + 2 + 4)                   // mod time/date, crc
                var compressedSize = reader.uint32()
                var uncompressedSize = reader.uint32()
                val nameLength = reader.uint16()
                val extraLength = reader.uint16()
                val commentLength = reader.uint16()
                reader.skip(2 + 2 + 4)                   // disk start, attributes
                var localOffset = reader.uint32()

                val path = reader.string(nameLength, isUtf8 = flags and 0x0800 != 0)
                val extra = reader.bytes(extraLength)
                reader.skip(commentLength)

                // Zip64 extended information overrides whichever fields were maxed.
                val zip64 = parseZip64Extra(
                    extra,
                    needsUncompressed = uncompressedSize == 0xFFFFFFFFL,
                    needsCompressed = compressedSize == 0xFFFFFFFFL,
                    needsOffset = localOffset == 0xFFFFFFFFL,
                )
                if (zip64 != null) {
                    zip64.uncompressedSize?.let { uncompressedSize = it }
                    zip64.compressedSize?.let { compressedSize = it }
                    zip64.localOffset?.let { localOffset = it }
                }

                parsed += ZipEntry(
                    path = path,
                    compressedSize = compressedSize,
                    uncompressedSize = uncompressedSize,
                    localHeaderOffset = localOffset,
                    compressionMethod = method,
                    isEncrypted = flags and 0x0001 != 0,
                )
            }
            return parsed
        }

        private class Zip64Fields(
            val uncompressedSize: Long?,
            val compressedSize: Long?,
            val localOffset: Long?,
        )

        /**
         * Walks the extra-field blocks looking for header id 0x0001. Its payload
         * carries only the fields that were sentinel-valued, in a fixed order.
         */
        private fun parseZip64Extra(
            extra: ByteArray,
            needsUncompressed: Boolean,
            needsCompressed: Boolean,
            needsOffset: Boolean,
        ): Zip64Fields? {
            if (!needsUncompressed && !needsCompressed && !needsOffset) return null

            val reader = ByteReader(extra)
            while (reader.remaining >= 4) {
                val headerId = reader.uint16()
                val size = reader.uint16()
                if (reader.remaining < size) break
                if (headerId != 0x0001) {
                    reader.skip(size)
                    continue
                }
                var consumed = 0
                var uncompressed: Long? = null
                var compressed: Long? = null
                var offset: Long? = null
                if (needsUncompressed && size - consumed >= 8) {
                    uncompressed = reader.int64(); consumed += 8
                }
                if (needsCompressed && size - consumed >= 8) {
                    compressed = reader.int64(); consumed += 8
                }
                if (needsOffset && size - consumed >= 8) {
                    offset = reader.int64(); consumed += 8
                }
                return Zip64Fields(uncompressed, compressed, offset)
            }
            return null
        }

        private class Zip64Directory(val size: Long, val offset: Long)

        private suspend fun readZip64(
            tail: ByteArray,
            tailOffset: Long,
            source: RandomAccessSource,
        ): Zip64Directory? {
            val locatorIndex = lastIndexOf(ZIP64_LOCATOR_SIGNATURE, tail) ?: return null
            val locator = ByteReader(tail, locatorIndex)
            locator.uint32()          // signature
            locator.skip(4)           // disk holding the zip64 EOCD
            val recordOffset = locator.int64()

            if (recordOffset < 0 || recordOffset + 56 > source.length) {
                throw ZipException.Malformed("zip64 EOCD offset outside the source")
            }

            val record: ByteArray = if (recordOffset >= tailOffset) {
                val start = (recordOffset - tailOffset).toInt()
                tail.copyOfRange(start, minOf(start + 56, tail.size))
            } else {
                source.readExactly(recordOffset, 56)
            }

            val reader = ByteReader(record)
            if (reader.uint32() != ZIP64_EOCD_SIGNATURE.toLong() and 0xFFFFFFFFL) {
                throw ZipException.Malformed("zip64 EOCD signature missing")
            }
            reader.skip(8 + 2 + 2 + 4 + 4)   // record size, versions, disk numbers
            reader.skip(8)                   // entries on this disk
            reader.int64()                   // total entries
            val size = reader.int64()
            val offset = reader.int64()
            return Zip64Directory(size, offset)
        }

        /**
         * Scans backwards for a four-byte little-endian signature.
         *
         * Backwards and by signature, not at a fixed offset: an archive comment
         * pushes the EOCD arbitrarily far from the tail, and `archive-comment.cbz`
         * in the corpus exists to catch a reader that forgets.
         */
        private fun lastIndexOf(signature: Int, data: ByteArray): Int? {
            val pattern = byteArrayOf(
                (signature and 0xFF).toByte(),
                ((signature shr 8) and 0xFF).toByte(),
                ((signature shr 16) and 0xFF).toByte(),
                ((signature shr 24) and 0xFF).toByte(),
            )
            if (data.size < pattern.size) return null
            for (index in data.size - pattern.size downTo 0) {
                if (data[index] == pattern[0] &&
                    data[index + 1] == pattern[1] &&
                    data[index + 2] == pattern[2] &&
                    data[index + 3] == pattern[3]
                ) {
                    return index
                }
            }
            return null
        }

        /**
         * Raw DEFLATE, via the platform. We parse the container; we do not
         * implement compression (ADR-0008).
         */
        fun inflate(compressed: ByteArray, expectedSize: Long): ByteArray {
            if (expectedSize < 0) throw ZipException.Malformed("negative uncompressed size")
            // Zero can mean two things. An entry that really is empty has no
            // compressed bytes either; an entry recovered from a local header with
            // a data descriptor has bytes and no declared size. Only the first is
            // empty.
            if (expectedSize == 0L && compressed.isEmpty()) return ByteArray(0)
            if (expectedSize == 0L) return inflateUnknownSize(compressed)

            val capacity = minOf(expectedSize, MAX_INFLATE_BYTES.toLong()).toInt()
            val output = ByteArray(capacity)
            // `true` selects raw DEFLATE — ZIP stores no zlib header.
            val inflater = Inflater(true)
            try {
                inflater.setInput(compressed)
                var written = 0
                while (written < capacity && !inflater.finished()) {
                    val produced = inflater.inflate(output, written, capacity - written)
                    if (produced == 0 && (inflater.needsInput() || inflater.needsDictionary())) break
                    written += produced
                }
                if (written == 0) throw ZipException.InflateFailed()
                return if (written == capacity) output else output.copyOf(written)
            } finally {
                inflater.end()
            }
        }

        /**
         * Inflates when the uncompressed size is not known.
         *
         * Only reachable through recovery: a local header that used a data
         * descriptor declares no size, and in recovery there is no central
         * directory to ask. The buffer starts at a generous multiple of the
         * compressed size and doubles while the result exactly fills it, which is
         * the signal that it was clipped.
         */
        private fun inflateUnknownSize(compressed: ByteArray): ByteArray {
            var capacity = maxOf(compressed.size * 8, 64 * 1024)
            while (true) {
                val output = ByteArray(capacity)
                val inflater = Inflater(true)
                val written = try {
                    inflater.setInput(compressed)
                    var produced = 0
                    while (produced < capacity && !inflater.finished()) {
                        val step = inflater.inflate(output, produced, capacity - produced)
                        if (step == 0 && (inflater.needsInput() || inflater.needsDictionary())) break
                        produced += step
                    }
                    produced
                } finally {
                    inflater.end()
                }
                if (written == 0) throw ZipException.InflateFailed()
                // A result that exactly fills the buffer may have been truncated,
                // so try again with more room — unless there is no more to give.
                if (written < capacity || capacity >= MAX_INFLATE_BYTES) {
                    return if (written == capacity) output else output.copyOf(written)
                }
                capacity = minOf(capacity * 2, MAX_INFLATE_BYTES)
            }
        }

        /**
         * Rebuilds an index by scanning for local file headers.
         *
         * For an archive whose central directory is gone — a truncated download, a
         * partial copy off a failing disk. `publication-formats` requires opening
         * whatever pages can be read and reporting what was skipped, rather than
         * refusing the publication, and ADR-0008 notes that owning the reader is
         * what makes this possible at all.
         *
         * It reads the archive **linearly**, which is inherent: recovery exists
         * precisely because there is no index to seek with. That is the one place
         * this reader gives up the ranged-read property, and why it is a separate
         * entry point rather than a silent fallback.
         *
         * Local headers are trusted here for sizes, which ADR-0008 otherwise
         * forbids — because in recovery there is nothing better. Where a header
         * declares no size, the entry runs to the next signature.
         */
        suspend fun recovering(source: RandomAccessSource): ZipReader {
            val found = mutableListOf<ZipEntry>()
            var offset = 0L
            // A comic has hundreds of entries. Tens of thousands is a crafted file.
            val entryLimit = 50_000
            // Read in windows with an overlap, so a signature straddling a boundary
            // is still seen whole.
            val window = 1 shl 20
            val overlap = 4
            var pending: Pair<ZipEntry, Long>? = null

            while (offset < source.length && found.size < entryLimit) {
                val count = minOf(window.toLong(), source.length - offset).toInt()
                val chunk = source.readExactly(offset, count)
                var index = 0
                var reachedDirectory = false

                while (index + 4 <= chunk.size) {
                    if (chunk[index] != 0x50.toByte() || chunk[index + 1] != 0x4B.toByte()) {
                        index++
                        continue
                    }
                    val at = offset + index
                    val third = chunk[index + 2].toInt() and 0xFF
                    val fourth = chunk[index + 3].toInt() and 0xFF

                    // A central-directory or EOCD signature ends the entry region.
                    if (third == 0x01 || third == 0x05 || third == 0x06) {
                        pending?.let { append(found, it, at, source) }
                        pending = null
                        reachedDirectory = true
                        break
                    }
                    if (third != 0x03 || fourth != 0x04) {
                        index++
                        continue
                    }

                    // A previous entry with no declared size ends where this starts.
                    pending?.let { append(found, it, at, source) }
                    pending = null

                    val parsed = runCatching { localEntry(at, source) }.getOrNull()
                    if (parsed == null) {
                        index++
                        continue
                    }
                    if (parsed.first.compressedSize > 0) {
                        append(found, parsed, null, source)
                    } else {
                        // Size unknown until the next signature is found.
                        pending = parsed
                    }
                    index += 4
                }

                if (reachedDirectory) break
                if (source.length - offset <= count) break
                offset += count - overlap
            }

            // The last entry runs to the end of what survived.
            pending?.let { append(found, it, source.length, source) }
            if (found.isEmpty()) throw ZipException.NoCentralDirectory()
            return ZipReader(source, found, hasArchiveComment = false, isRecovered = true)
        }

        /**
         * Adds an entry, dropping it when its data does not fit in what survived.
         *
         * A truncated archive's final entry is the common case: its header is
         * intact and its bytes are not. Dropping it is what makes "opened 10,
         * skipped 2" truthful rather than a promise the reader cannot keep.
         */
        private fun append(
            found: MutableList<ZipEntry>,
            parsed: Pair<ZipEntry, Long>,
            end: Long?,
            source: RandomAccessSource,
        ) {
            val (entry, dataOffset) = parsed
            val sized = if (end == null) {
                entry
            } else {
                val available = end - dataOffset
                if (available <= 0) return
                entry.copy(compressedSize = available)
            }
            if (dataOffset + sized.compressedSize > source.length) return
            found += sized
        }

        /** Parses one local file header, returning the entry and its data offset. */
        private suspend fun localEntry(
            offset: Long,
            source: RandomAccessSource,
        ): Pair<ZipEntry, Long> {
            val header = source.readExactly(offset, minOf(30L, source.length - offset).toInt())
            val reader = ByteReader(header)
            if (reader.uint32() != (LOCAL_HEADER_SIGNATURE.toLong() and 0xFFFFFFFFL)) {
                throw ZipException.Malformed("not a local header")
            }
            reader.skip(2)                    // version needed
            val flags = reader.uint16()
            val method = reader.uint16()
            reader.skip(2 + 2 + 4)            // time, date, crc
            val compressed = reader.uint32()
            val uncompressed = reader.uint32()
            val nameLength = reader.uint16()
            val extraLength = reader.uint16()

            if (nameLength <= 0 || nameLength > 4096) {
                throw ZipException.Malformed("implausible name length")
            }
            val nameBytes = source.readExactly(offset + 30, nameLength)
            val path = String(
                nameBytes,
                if (flags and 0x0800 != 0) Charsets.UTF_8 else Charsets.ISO_8859_1,
            )

            val dataOffset = offset + 30 + nameLength + extraLength
            if (dataOffset > source.length) {
                throw ZipException.Malformed("local header runs past the source")
            }
            return ZipEntry(
                path = path,
                compressedSize = compressed,
                uncompressedSize = uncompressed,
                localHeaderOffset = offset,
                compressionMethod = method,
                isEncrypted = flags and 0x0001 != 0,
            ) to dataOffset
        }
    }

    /** The uncompressed bytes of one entry. */
    suspend fun data(entry: ZipEntry): ByteArray {
        if (entry.isEncrypted) throw ZipException.Encrypted()

        // The local header's own name and extra lengths tell us where the data
        // starts. Its size fields are ignored — see ZipEntry.
        val probeSize = minOf(30L, source.length - entry.localHeaderOffset).toInt()
        val headerProbe = source.readExactly(entry.localHeaderOffset, probeSize)
        val reader = ByteReader(headerProbe)
        if (reader.uint32() != LOCAL_HEADER_SIGNATURE.toLong() and 0xFFFFFFFFL) {
            throw ZipException.Malformed("local header signature missing")
        }
        reader.skip(2 + 2 + 2 + 2 + 2 + 4 + 4 + 4)  // version…sizes, all untrusted
        val nameLength = reader.uint16()
        val extraLength = reader.uint16()

        val dataOffset = entry.localHeaderOffset + 30 + nameLength + extraLength
        if (dataOffset + entry.compressedSize > source.length) {
            throw ZipException.Malformed("entry data outside the source")
        }

        val compressed = source.readExactly(dataOffset, entry.compressedSize.toInt())
        if (entry.isStored) return compressed
        if (!entry.isDeflated) throw ZipException.UnsupportedCompression(entry.compressionMethod)
        return inflate(compressed, entry.uncompressedSize)
    }

    fun entry(path: String): ZipEntry? = entries.firstOrNull { it.path == path }
}
