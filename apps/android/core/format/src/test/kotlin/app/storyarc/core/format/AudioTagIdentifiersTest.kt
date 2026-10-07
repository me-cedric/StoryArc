package app.storyarc.core.format

import app.storyarc.core.model.CoverIdentifier
import java.io.ByteArrayOutputStream
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * The identifiers the cover lookup reads out of audio tags, container by container.
 *
 * Task 6.1 of `cover-for-every-publication`. Each container is built here byte by byte,
 * because the claim is about where in the container the reader looks. iOS's
 * `AudioTagIdentifiersTests` builds the same bytes and asserts the same answers.
 */
class AudioTagIdentifiersTest {

    private val releaseGroup = "6a6bd3a5-0b7c-4a37-9f2b-6b5d6e2d9e11"
    private val asin = "B08G9PRS1K"

    private fun read(bytes: ByteArray): CoverIdentifier? =
        runBlocking { AudioTagIdentifiers.identifier(DataSource(bytes)) }

    // ---------------------------------------------------------------------------------- ID3

    @Test
    fun `an ID3v2_3 TXXX frame names the release group`() {
        val tag = id3(3, frame("TSSE", 3, byteArrayOf(0) + "Lavf".toByteArray()),
            frame("TXXX", 3, txxx(0, "MusicBrainz Release Group Id", releaseGroup)))

        assertEquals(CoverIdentifier.MusicBrainzReleaseGroup(releaseGroup), read(tag))
    }

    @Test
    fun `an ID3v2_4 frame with a UTF-16 description and a syncsafe size is read`() {
        val tag = id3(4, frame("TXXX", 4, txxx(1, "ASIN", asin)))

        assertEquals(CoverIdentifier.AudibleAsin(asin), read(tag))
    }

    @Test
    fun `an ID3 tag that names neither identifier reads none`() {
        val tag = id3(3, frame("TXXX", 3, txxx(0, "ENCODEDBY", "someone")))

        assertNull(read(tag))
    }

    // ----------------------------------------------------------------------------------- MP4

    @Test
    fun `an iTunes freeform atom names the ASIN`() {
        val file = mp4(freeform("com.apple.iTunes", "ASIN", asin))

        assertEquals(CoverIdentifier.AudibleAsin(asin), read(file))
    }

    @Test
    fun `a QuickTime keys atom names the release group by the item's index`() {
        val file = mp4Keys(listOf("title", "MusicBrainz Release Group Id"), mapOf(2 to releaseGroup))

        assertEquals(CoverIdentifier.MusicBrainzReleaseGroup(releaseGroup), read(file))
    }

    @Test
    fun `a moov atom that comes after a large mdat is still found`() {
        val file = mp4(freeform("com.apple.iTunes", "ASIN", asin), mdatBytes = 200_000)

        assertEquals(CoverIdentifier.AudibleAsin(asin), read(file))
    }

    // ------------------------------------------------------------------------- FLAC and Ogg

    @Test
    fun `a FLAC Vorbis comment block after other blocks names the release group`() {
        val comment = vorbis("MUSICBRAINZ_RELEASEGROUPID=$releaseGroup", "ALBUM=x")
        val file = "fLaC".toByteArray() + block(0, ByteArray(34), last = false) +
            block(4, comment, last = true)

        assertEquals(CoverIdentifier.MusicBrainzReleaseGroup(releaseGroup), read(file))
    }

    @Test
    fun `an Ogg comment packet names the ASIN`() {
        val file = "OggS".toByteArray() + ByteArray(40) + "\u0003vorbis".toByteArray() +
            vorbis("ASIN=$asin")

        assertEquals(CoverIdentifier.AudibleAsin(asin), read(file))
    }

    // --------------------------------------------------------------------------- Precedence

    @Test
    fun `an ASIN wins over a release group where a file carries both`() {
        val tags = listOf(
            "MUSICBRAINZ_RELEASEGROUPID" to releaseGroup,
            "audible_asin" to asin,
        )

        assertEquals(CoverIdentifier.AudibleAsin(asin), AudioTagIdentifiers.fromTags(tags))
    }

    @Test
    fun `a value that is not an identifier is refused before it can reach a request`() {
        val tags = listOf("ASIN" to "../../etc/passwd", "MusicBrainz Release Group Id" to "nope")

        assertNull(AudioTagIdentifiers.fromTags(tags))
    }

    @Test
    fun `bytes that are no audio container read none rather than throw`() {
        assertNull(read(ByteArray(64) { it.toByte() }))
        assertNull(read(ByteArray(0)))
        assertNull(read("ID3".toByteArray() + byteArrayOf(3, 0, 0, 0x7f, 0x7f, 0x7f, 0x7f)))
    }

    // ------------------------------------------------------------------------------ Builders

    private fun be(value: Int) = byteArrayOf(
        (value ushr 24).toByte(), (value ushr 16).toByte(), (value ushr 8).toByte(), value.toByte(),
    )

    private fun syncsafe(value: Int) = byteArrayOf(
        (value ushr 21 and 0x7f).toByte(), (value ushr 14 and 0x7f).toByte(),
        (value ushr 7 and 0x7f).toByte(), (value and 0x7f).toByte(),
    )

    private fun txxx(encoding: Int, description: String, value: String): ByteArray = when (encoding) {
        1 -> byteArrayOf(1, 0xff.toByte(), 0xfe.toByte()) +
            description.toByteArray(Charsets.UTF_16LE) + byteArrayOf(0, 0, 0xff.toByte(), 0xfe.toByte()) +
            value.toByteArray(Charsets.UTF_16LE)
        else -> byteArrayOf(encoding.toByte()) + description.toByteArray(Charsets.ISO_8859_1) +
            byteArrayOf(0) + value.toByteArray(Charsets.ISO_8859_1)
    }

    private fun frame(id: String, version: Int, body: ByteArray): ByteArray =
        id.toByteArray() + (if (version == 4) syncsafe(body.size) else be(body.size)) +
            byteArrayOf(0, 0) + body

    private fun id3(version: Int, vararg frames: ByteArray): ByteArray {
        val body = frames.fold(ByteArray(0)) { acc, next -> acc + next }
        return "ID3".toByteArray() + byteArrayOf(version.toByte(), 0, 0) + syncsafe(body.size) + body
    }

    private fun box(type: String, vararg parts: ByteArray): ByteArray {
        val payload = parts.fold(ByteArray(0)) { acc, next -> acc + next }
        return be(8 + payload.size) + type.toByteArray(Charsets.ISO_8859_1) + payload
    }

    private fun data(value: String) = box("data", be(1), be(0), value.toByteArray())

    private fun freeform(mean: String, name: String, value: String): ByteArray =
        box("----", box("mean", be(0), mean.toByteArray()), box("name", be(0), name.toByteArray()), data(value))

    private fun mp4(item: ByteArray, mdatBytes: Int = 16): ByteArray {
        val meta = box("meta", be(0), box("hdlr", ByteArray(24)), box("ilst", item))
        return box("ftyp", "M4B ".toByteArray(), be(0)) + box("mdat", ByteArray(mdatBytes)) +
            box("moov", box("mvhd", ByteArray(100)), box("udta", meta))
    }

    private fun mp4Keys(names: List<String>, values: Map<Int, String>): ByteArray {
        val keys = box(
            "keys",
            be(0),
            be(names.size),
            *names.map { box("mdta", it.toByteArray()) }.toTypedArray(),
        )
        val ilst = ByteArrayOutputStream()
        values.entries.forEach { (index, value) ->
            ilst.write(be(8 + data(value).size))
            ilst.write(be(index))
            ilst.write(data(value))
        }
        val meta = box("meta", be(0), box("hdlr", ByteArray(24)), keys, box("ilst", ilst.toByteArray()))
        return box("ftyp", "M4B ".toByteArray(), be(0)) + box("moov", box("udta", meta))
    }

    private fun le(value: Int) = byteArrayOf(
        value.toByte(), (value ushr 8).toByte(), (value ushr 16).toByte(), (value ushr 24).toByte(),
    )

    private fun vorbis(vararg entries: String): ByteArray {
        val vendor = "test".toByteArray()
        return le(vendor.size) + vendor + le(entries.size) +
            entries.fold(ByteArray(0)) { acc, e -> acc + le(e.length) + e.toByteArray() }
    }

    private fun block(type: Int, body: ByteArray, last: Boolean): ByteArray =
        byteArrayOf(
            (type or if (last) 0x80 else 0).toByte(),
            (body.size ushr 16).toByte(), (body.size ushr 8).toByte(), body.size.toByte(),
        ) + body
}
