package app.storyarc.core.format

import app.storyarc.core.model.CoverIdentifier
import java.util.Locale

/**
 * The identifiers an audio file's tags carry, for the cover lookup (`cover-art`, task 6.1).
 *
 * `MediaMetadataRetriever` answers a fixed set of keys and none of them is a custom tag, so
 * the three containers are read here: ID3v2 `TXXX` frames (MP3), MP4 freeform `----` atoms
 * (M4B, M4A) and Vorbis comments (FLAC, Ogg). iOS reads the same tags through AVFoundation.
 *
 * An Audible ASIN wins over a MusicBrainz release group where a file carries both, because
 * it names the book and the release group names the album it was ripped from.
 */
object AudioTagIdentifiers {

    private const val MAX_TAG_BYTES = 16 * 1024 * 1024
    private const val OGG_HEAD_BYTES = 256 * 1024

    private val asinNames = setOf("asin", "audibleasin", "cdek")
    private const val RELEASE_GROUP_NAME = "musicbrainzreleasegroupid"
    private val oggComment =
        Regex("""(?i)(MUSICBRAINZ_RELEASEGROUPID|AUDIBLE_ASIN|ASIN)=([\x21-\x7e]{1,64})""")

    /** The identifier a file's tags name, or null. Reads only the tag area, never the audio. */
    suspend fun identifier(source: RandomAccessSource): CoverIdentifier? = runCatching {
        val head = source.read(0, 12)
        fromTags(
            when {
                head.startsWith("ID3") -> id3(source)
                head.size >= 8 && String(head, 4, 4, Charsets.ISO_8859_1) == "ftyp" -> mp4(source)
                head.startsWith("fLaC") -> flac(source)
                head.startsWith("OggS") -> ogg(source)
                else -> emptyList()
            },
        )
    }.getOrNull()

    /** Tag name and value pairs to an identifier. Names are compared without case or separators. */
    internal fun fromTags(tags: List<Pair<String, String>>): CoverIdentifier? {
        val named = tags.map { (name, value) -> normalised(name) to value.trim('\u0000', ' ') }
        named.firstOrNull { it.first in asinNames }
            ?.let { CoverIdentifier.asin(it.second) }?.let { return it }
        return named.firstOrNull { it.first == RELEASE_GROUP_NAME }
            ?.let { CoverIdentifier.musicBrainz(it.second) }
    }

    private fun normalised(name: String): String =
        name.substringAfterLast(':').lowercase(Locale.ROOT).filter { it.isLetterOrDigit() }

    private fun ByteArray.startsWith(text: String): Boolean =
        size >= text.length && text.indices.all { this[it] == text[it].code.toByte() }

    // ------------------------------------------------------------------------------- ID3v2

    private suspend fun id3(source: RandomAccessSource): List<Pair<String, String>> {
        val header = source.readExactly(0, 10)
        val major = header[3].toInt()
        val size = syncsafe(header, 6)
        if (size > MAX_TAG_BYTES || major !in 2..4) return emptyList()
        val tag = source.read(10, minOf(size.toLong(), source.length - 10).toInt())
        var at = 0
        if (major >= 3 && header[5].toInt() and 0x40 != 0 && tag.size >= 4) {
            at = if (major == 4) syncsafe(tag, 0) else 4 + beInt(tag, 0)
        }
        val idLength = if (major == 2) 3 else 4
        val frameHeader = if (major == 2) 6 else 10
        val found = mutableListOf<Pair<String, String>>()
        while (at + frameHeader <= tag.size && tag[at].toInt() != 0) {
            val id = String(tag, at, idLength, Charsets.ISO_8859_1)
            val length = when (major) {
                2 -> (tag[at + 3].toInt() and 0xff shl 16) or (tag[at + 4].toInt() and 0xff shl 8) or
                    (tag[at + 5].toInt() and 0xff)
                4 -> syncsafe(tag, at + 4)
                else -> beInt(tag, at + 4)
            }
            val body = at + frameHeader
            if (length < 0 || body + length > tag.size) break
            if (id == "TXXX" || id == "TXX") txxx(tag, body, body + length)?.let { found += it }
            at = body + length
        }
        return found
    }

    private fun txxx(tag: ByteArray, from: Int, to: Int): Pair<String, String>? {
        if (to - from < 2) return null
        val encoding = tag[from].toInt()
        val charset = when (encoding) {
            1 -> Charsets.UTF_16
            2 -> Charsets.UTF_16BE
            3 -> Charsets.UTF_8
            else -> Charsets.ISO_8859_1
        }
        val wide = encoding == 1 || encoding == 2
        val end = terminator(tag, from + 1, to, wide)
        if (end < 0) return null
        val after = end + if (wide) 2 else 1
        return String(tag, from + 1, end - from - 1, charset) to
            String(tag, after, (to - after).coerceAtLeast(0), charset)
    }

    private fun terminator(bytes: ByteArray, from: Int, to: Int, wide: Boolean): Int {
        var i = from
        while (i < to) {
            if (!wide && bytes[i].toInt() == 0) return i
            if (wide && i + 1 < to && bytes[i].toInt() == 0 && bytes[i + 1].toInt() == 0) return i
            i += if (wide) 2 else 1
        }
        return -1
    }

    private fun syncsafe(bytes: ByteArray, at: Int): Int =
        (0 until 4).fold(0) { acc, i -> (acc shl 7) or (bytes[at + i].toInt() and 0x7f) }

    private fun beInt(bytes: ByteArray, at: Int): Int =
        (0 until 4).fold(0) { acc, i -> (acc shl 8) or (bytes[at + i].toInt() and 0xff) }

    // -------------------------------------------------------------------------------- MP4

    private suspend fun mp4(source: RandomAccessSource): List<Pair<String, String>> {
        var at = 0L
        while (at + 8 <= source.length) {
            val header = source.readExactly(at, 8)
            var size = beInt(header, 0).toLong() and 0xffffffffL
            var headerSize = 8
            if (size == 1L) {
                val wide = source.readExactly(at + 8, 8)
                size = (beInt(wide, 0).toLong() shl 32) or (beInt(wide, 4).toLong() and 0xffffffffL)
                headerSize = 16
            } else if (size == 0L) {
                size = source.length - at
            }
            if (size < headerSize || size > source.length - at) return emptyList()
            if (String(header, 4, 4, Charsets.ISO_8859_1) == "moov") {
                val payload = size - headerSize
                if (payload > MAX_TAG_BYTES) return emptyList()
                return ilst(source.read(at + headerSize, payload.toInt()))
            }
            at += size
        }
        return emptyList()
    }

    private class Box(val type: String, val from: Int, val to: Int)

    private fun boxes(bytes: ByteArray, from: Int, to: Int): List<Box> {
        val found = mutableListOf<Box>()
        var at = from
        while (at + 8 <= to) {
            val size = beInt(bytes, at)
            if (size < 8 || at + size > to) break
            found += Box(String(bytes, at + 4, 4, Charsets.ISO_8859_1), at + 8, at + size)
            at += size
        }
        return found
    }

    private fun ilst(moov: ByteArray): List<Pair<String, String>> {
        val udta = boxes(moov, 0, moov.size).firstOrNull { it.type == "udta" } ?: return emptyList()
        val meta = boxes(moov, udta.from, udta.to).firstOrNull { it.type == "meta" }
            ?: return emptyList()
        // `meta` is a full box: four bytes of version and flags come before its children.
        val inner = boxes(moov, meta.from + 4, meta.to)
        val list = inner.firstOrNull { it.type == "ilst" } ?: return emptyList()
        val keys = inner.firstOrNull { it.type == "keys" }?.let { mdtaKeys(moov, it) }.orEmpty()
        return boxes(moov, list.from, list.to).mapNotNull { item ->
            val children = boxes(moov, item.from, item.to)
            val data = children.firstOrNull { it.type == "data" } ?: return@mapNotNull null
            if (data.to - data.from < 8) return@mapNotNull null
            // iTunes names a custom tag in a `name` atom; the QuickTime form numbers the
            // item and lists the names once in `keys`.
            val name = children.firstOrNull { it.type == "name" && item.type == "----" }
                ?.takeIf { it.to - it.from >= 4 }
                ?.let { String(moov, it.from + 4, it.to - it.from - 4, Charsets.UTF_8) }
                ?: keys.getOrNull(beInt(moov, item.from - 4) - 1)
                ?: return@mapNotNull null
            name to String(moov, data.from + 8, data.to - data.from - 8, Charsets.UTF_8)
        }
    }

    /** The names a QuickTime `keys` atom lists in order: each is a size, a namespace, a name. */
    private fun mdtaKeys(moov: ByteArray, keys: Box): List<String> {
        val names = mutableListOf<String>()
        var at = keys.from + 8
        while (at + 8 <= keys.to) {
            val size = beInt(moov, at)
            if (size < 8 || at + size > keys.to) break
            names += String(moov, at + 8, size - 8, Charsets.UTF_8)
            at += size
        }
        return names
    }

    // ------------------------------------------------------------------------ FLAC and Ogg

    private suspend fun flac(source: RandomAccessSource): List<Pair<String, String>> {
        var at = 4L
        while (at + 4 <= source.length) {
            val header = source.readExactly(at, 4)
            val length = (header[1].toInt() and 0xff shl 16) or (header[2].toInt() and 0xff shl 8) or
                (header[3].toInt() and 0xff)
            if (header[0].toInt() and 0x7f == 4) {
                if (length > MAX_TAG_BYTES) return emptyList()
                return vorbisComments(source.read(at + 4, length))
            }
            if (header[0].toInt() and 0x80 != 0) break
            at += 4 + length
        }
        return emptyList()
    }

    private fun vorbisComments(block: ByteArray): List<Pair<String, String>> {
        fun le(at: Int) =
            (0 until 4).fold(0) { acc, i -> acc or ((block[at + i].toInt() and 0xff) shl (8 * i)) }
        if (block.size < 8) return emptyList()
        var at = 4 + le(0)
        if (at + 4 > block.size) return emptyList()
        val count = le(at)
        at += 4
        val found = mutableListOf<Pair<String, String>>()
        repeat(count) {
            if (at + 4 > block.size) return found
            val length = le(at)
            at += 4
            if (length < 0 || at + length > block.size) return found
            val entry = String(block, at, length, Charsets.UTF_8)
            at += length
            entry.indexOf('=').takeIf { it > 0 }
                ?.let { found += entry.substring(0, it) to entry.substring(it + 1) }
        }
        return found
    }

    private suspend fun ogg(source: RandomAccessSource): List<Pair<String, String>> {
        val bytes = source.read(0, minOf(source.length, OGG_HEAD_BYTES.toLong()).toInt())
        val head = String(bytes, Charsets.ISO_8859_1)
        return oggComment.findAll(head).map { it.groupValues[1] to it.groupValues[2] }.toList()
    }
}
