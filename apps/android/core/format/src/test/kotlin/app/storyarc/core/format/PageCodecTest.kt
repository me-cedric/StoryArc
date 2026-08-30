package app.storyarc.core.format

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * What a page's bytes say they are.
 *
 * `publication-formats`: "a page in an unsupported codec displays a placeholder naming
 * the codec, and does not break pagination". The naming is what this covers, and the
 * cases are chosen for the ways a sniffer goes wrong: two families whose signature is
 * not at offset zero, one whose brand is the only difference from another, and a name
 * that lies about its contents.
 *
 * iOS's `PageCodecTests` asserts the same table, case for case.
 */
class PageCodecTest {

    /** A prefix long enough to sniff, padded so a short-array guard cannot pass by luck. */
    private fun prefix(bytes: List<Int>): ByteArray {
        val padded = bytes + List(maxOf(0, 16 - bytes.size)) { 0 }
        return ByteArray(padded.size) { padded[it].toByte() }
    }

    private fun prefix(text: String): ByteArray = prefix(text.map { it.code })

    private fun ftyp(brand: String): ByteArray =
        prefix(listOf(0, 0, 0, 0x18) + "ftyp".map { it.code } + brand.map { it.code })

    @Test
    fun `the fixed signatures are read from the head of the file`() {
        assertEquals(PageCodec.JPEG, PageCodec.of(prefix(listOf(0xFF, 0xD8, 0xFF, 0xE0))))
        assertEquals(
            PageCodec.PNG,
            PageCodec.of(prefix(listOf(0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A))),
        )
        assertEquals(PageCodec.GIF, PageCodec.of(prefix("GIF89a")))
        assertEquals(PageCodec.BMP, PageCodec.of(prefix("BM")))
        assertEquals(PageCodec.TIFF, PageCodec.of(prefix(listOf(0x49, 0x49, 0x2A, 0x00))))
        assertEquals(PageCodec.TIFF, PageCodec.of(prefix(listOf(0x4D, 0x4D, 0x00, 0x2A))))
    }

    @Test
    fun `webp is a RIFF container, so the four length bytes in the middle are skipped`() {
        val riff = "RIFF".map { it.code } + listOf(0x2A, 0x13, 0x00, 0x00) + "WEBP".map { it.code }
        assertEquals(PageCodec.WEBP, PageCodec.of(prefix(riff)))
        // A RIFF that is not WebP — a WAV, say — is not a page codec.
        val wave = "RIFF".map { it.code } + listOf(0x2A, 0x13, 0x00, 0x00) + "WAVE".map { it.code }
        assertNull(PageCodec.of(prefix(wave)))
    }

    @Test
    fun `avif and heic are the same container, told apart by the brand alone`() {
        assertEquals(PageCodec.AVIF, PageCodec.of(ftyp("avif")))
        assertEquals(PageCodec.AVIF, PageCodec.of(ftyp("avis")))
        assertEquals(PageCodec.HEIC, PageCodec.of(ftyp("heic")))
        assertEquals(PageCodec.HEIC, PageCodec.of(ftyp("mif1")))
        // A brand this app knows nothing about is not guessed at.
        assertNull(PageCodec.of(ftyp("qt  ")))
    }

    @Test
    fun `jpeg xl is recognised in both of its two shapes`() {
        assertEquals(PageCodec.JPEG_XL, PageCodec.of(prefix(listOf(0xFF, 0x0A))))
        assertEquals(
            PageCodec.JPEG_XL,
            PageCodec.of(
                prefix(
                    listOf(0x00, 0x00, 0x00, 0x0C, 0x4A, 0x58, 0x4C, 0x20, 0x0D, 0x0A, 0x87, 0x0A),
                ),
            ),
        )
    }

    @Test
    fun `bytes that are not an image name nothing`() {
        assertNull(PageCodec.of(prefix("not an image at all")))
        assertNull(PageCodec.of(ByteArray(0)))
    }

    @Test
    fun `the name comes from the bytes, not from a file name that disagrees`() {
        assertEquals("AVIF", PageCodec.nameOf(ftyp("avif"), "pages/001.jpg"))
    }

    @Test
    fun `with no bytes to read, the extension is the best that can be said`() {
        assertEquals("JPEG XL", PageCodec.nameOf(null, "pages/001.jxl"))
        assertEquals("HEIC", PageCodec.nameOf(null, "pages/001.HEIF"))
    }

    @Test
    fun `a page nothing can be said about is named nothing, rather than guessed at`() {
        assertNull(PageCodec.nameOf(null, "pages/001"))
        assertNull(PageCodec.nameOf(byteArrayOf(0x00, 0x01), "pages/001.xyz"))
    }

    @Test
    fun `every codec has a name a reader would recognise`() {
        for (codec in PageCodec.entries) {
            assertTrue(codec.name, codec.displayName.isNotEmpty())
        }
    }
}
