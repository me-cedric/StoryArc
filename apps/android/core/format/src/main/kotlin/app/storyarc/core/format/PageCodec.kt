package app.storyarc.core.format

/**
 * What a page's bytes say they are encoded with.
 *
 * `publication-formats`: "a page in an unsupported codec displays a placeholder naming
 * the codec, and does not break pagination". Naming it is the whole job of this type,
 * and the name matters more than it looks: a placeholder that says nothing leaves a
 * reader unable to tell a file the app cannot read from a file that is broken. One page
 * saying "JPEG" among a hundred that decoded is a damaged entry; every page saying
 * "JPEG XL" is a format this device has no decoder for.
 *
 * Read from the bytes rather than the extension, for the reason [FormatSniffer] reads
 * containers that way: a page named `.jpg` that is really AVIF is common in files
 * converted in bulk, and a name is not evidence.
 *
 * iOS's `PageCodec` is the same table, sniffed in the same order.
 *
 * @property displayName how the codec is named to the reader. Format names rather than
 *   prose, so the localised sentence wraps them — exactly as
 *   `FormatSniffer.Container.displayName` does for a refused container.
 */
enum class PageCodec(val displayName: String) {
    JPEG("JPEG"),
    PNG("PNG"),
    GIF("GIF"),
    WEBP("WebP"),
    AVIF("AVIF"),
    HEIC("HEIC"),
    JPEG_XL("JPEG XL"),
    BMP("BMP"),
    TIFF("TIFF"),
    ;

    companion object {
        /**
         * Longest prefix any signature below needs. An ISO base-media brand sits at
         * offset 8, so twelve bytes covers every case.
         */
        const val PROBE_LENGTH = 12

        /**
         * The codec a byte prefix identifies, or null when nothing matches.
         *
         * Ordered so that the unambiguous fixed signatures answer first and the two
         * container-shaped families — RIFF and ISO base media — are reached only when
         * nothing shorter matched.
         */
        fun of(prefix: ByteArray): PageCodec? {
            fun startsWith(vararg signature: Int): Boolean {
                if (prefix.size < signature.size) return false
                return signature.withIndex().all { (index, byte) ->
                    prefix[index].toInt() and 0xFF == byte
                }
            }

            if (startsWith(0xFF, 0xD8, 0xFF)) return JPEG
            if (startsWith(0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A)) return PNG
            if (startsWith(0x47, 0x49, 0x46, 0x38)) return GIF // GIF8
            if (startsWith(0x42, 0x4D)) return BMP // BM
            if (startsWith(0x49, 0x49, 0x2A, 0x00) || startsWith(0x4D, 0x4D, 0x00, 0x2A)) {
                return TIFF
            }
            // A naked JPEG XL codestream, and the ISO-BMFF container form.
            if (startsWith(0xFF, 0x0A)) return JPEG_XL
            if (startsWith(0x00, 0x00, 0x00, 0x0C, 0x4A, 0x58, 0x4C, 0x20, 0x0D, 0x0A, 0x87, 0x0A)) {
                return JPEG_XL
            }
            // RIFF....WEBP: the four bytes between are the chunk length, which is not a
            // signature and must not be compared.
            if (startsWith(0x52, 0x49, 0x46, 0x46) && ascii(prefix, 8) == "WEBP") return WEBP
            // ISO base media: `ftyp` at offset 4, then the brand. AVIF and HEIC are the
            // same container with different brands, which is why one check answers both.
            if (ascii(prefix, 4) == "ftyp") {
                val brand = ascii(prefix, 8)
                if (brand in AVIF_BRANDS) return AVIF
                if (brand in HEIC_BRANDS) return HEIC
            }
            return null
        }

        /**
         * What to call a page that could not be decoded, given whatever is known about it.
         *
         * The bytes first, the extension second, and null when neither says anything —
         * because "this page could not be read" is a better sentence than a codec name
         * invented from a file name nobody chose.
         */
        fun nameOf(data: ByteArray?, path: String): String? {
            if (data != null) of(data)?.let { return it.displayName }
            val extension = path.substringAfterLast('.', "").lowercase()
            if (extension.isEmpty()) return null
            return BY_EXTENSION[extension]?.displayName
        }

        /** Four bytes at an offset, as ASCII, or null when the prefix is too short. */
        private fun ascii(bytes: ByteArray, offset: Int): String? {
            if (bytes.size < offset + 4) return null
            return String(bytes, offset, 4, Charsets.US_ASCII)
        }

        private val AVIF_BRANDS = setOf("avif", "avis")

        /**
         * `mif1` and `msf1` are the generic HEIF brands; the rest are HEVC-coded images.
         * All of them arrive from a phone camera and all of them are called HEIC by the
         * people who have one.
         */
        private val HEIC_BRANDS =
            setOf("heic", "heix", "hevc", "hevx", "heim", "heis", "mif1", "msf1")

        /** The extensions [PageOrdering] will attempt, mapped to what they claim to be. */
        private val BY_EXTENSION = mapOf(
            "jpg" to JPEG,
            "jpeg" to JPEG,
            "png" to PNG,
            "gif" to GIF,
            "webp" to WEBP,
            "avif" to AVIF,
            "heic" to HEIC,
            "heif" to HEIC,
            "jxl" to JPEG_XL,
            "bmp" to BMP,
            "tif" to TIFF,
            "tiff" to TIFF,
        )
    }
}
