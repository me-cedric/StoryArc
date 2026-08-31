package app.storyarc.core.format

import java.io.File

// `PublicationFormat` used to live here. It moved to `:core:model`: the library
// sorts, filters and explains by format, and none of that should require the
// parser. This file keeps the sniffer, which is genuinely format-layer work.

/** What a file's leading bytes say it is, regardless of its name. */
object FormatSniffer {
    /**
     * Longest signature we need to see.
     *
     * TAR sets the floor: its `ustar` magic sits at offset 257, where every
     * other container announces itself in the first eight bytes. 265 bytes is
     * still one round trip on an SMB share, which is the cost that matters —
     * reading 8 instead would save nothing and lose CBT detection.
     */
    const val PROBE_LENGTH = 265

    enum class Container {
        ZIP, RAR, SEVEN_ZIP, PDF, TAR,
        MP4, MP3, FLAC, OGG,

        /**
         * An MPEG-4 file whose brand declares a store's content protection.
         *
         * Its own entry, because `publication-formats` requires the refusal to be
         * "distinct from an unsupported container": the format is supported and
         * this particular file is locked, and those two need different words.
         */
        PROTECTED_AUDIOBOOK,
        ;

        /**
         * Whether a player rather than a reader opens this.
         *
         * Asked here rather than at each call site, because a `when` repeated at
         * three call sites is how two of them end up disagreeing. Protected audio
         * answers `true`: it is refused for being locked, not for being the wrong
         * kind of file, and a caller that routed it to a comic reader would produce
         * the unsupported-container message this spec forbids for it.
         */
        val isAudio: Boolean
            get() = when (this) {
                MP4, MP3, FLAC, OGG, PROTECTED_AUDIOBOOK -> true
                ZIP, RAR, SEVEN_ZIP, PDF, TAR -> false
            }

        /**
         * How the container is named to the user when StoryArc refuses it.
         *
         * `publication-formats` forbids a generic parse failure: someone handed
         * a 7-Zip comic to a comic reader and deserves to be told that, not that
         * the file is broken. These are format names rather than prose, so the
         * localised string wraps them.
         */
        val displayName: String
            get() = when (this) {
                ZIP -> "ZIP"
                RAR -> "RAR"
                SEVEN_ZIP -> "7-Zip"
                PDF -> "PDF"
                TAR -> "TAR"
                MP4 -> "MPEG-4 audio"
                MP3 -> "MP3"
                FLAC -> "FLAC"
                OGG -> "Ogg"
                PROTECTED_AUDIOBOOK -> "protected audiobook"
            }
    }

    private val ZIP = byteArrayOf(0x50, 0x4B)
    private val RAR4 = byteArrayOf(0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x00)
    private val RAR5 = byteArrayOf(0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x01, 0x00)
    private val SEVEN_ZIP = byteArrayOf(0x37, 0x7A, 0xBC.toByte(), 0xAF.toByte(), 0x27, 0x1C)
    private val PDF = byteArrayOf(0x25, 0x50, 0x44, 0x46)
    private val USTAR = byteArrayOf(0x75, 0x73, 0x74, 0x61, 0x72) // at offset 257, not 0
    private val ID3 = byteArrayOf(0x49, 0x44, 0x33)
    private val FLAC = byteArrayOf(0x66, 0x4C, 0x61, 0x43)
    private val OGG_S = byteArrayOf(0x4F, 0x67, 0x67, 0x53)
    private val FTYP = byteArrayOf(0x66, 0x74, 0x79, 0x70) // at offset 4, not 0

    /** Where an MPEG-4 file states its brand: the four bytes after `ftyp`. */
    private const val BRAND_OFFSET = 8

    /**
     * The brands that mean a store's content protection rather than a format.
     *
     * Audible's two. They are checked as brands rather than as file extensions
     * because `publication-formats` says the contents are the fact — a `.m4b`
     * renamed from an `.aax` is still locked, and refusing on the extension alone
     * would let it through to a decoder that then reports a damaged file.
     */
    private val PROTECTED_BRANDS = setOf("aax ", "aaxc")

    /**
     * The container a byte prefix identifies, or `null` when nothing matches.
     *
     * EPUB and CBZ are both ZIP; distinguishing them needs the archive's
     * contents, which is why this returns [Container.ZIP] and the caller
     * resolves it.
     */
    fun container(prefix: ByteArray): Container? {
        fun startsWith(signature: ByteArray): Boolean =
            prefix.size >= signature.size &&
                signature.indices.all { prefix[it] == signature[it] }

        return when {
            startsWith(RAR5) || startsWith(RAR4) -> Container.RAR
            startsWith(SEVEN_ZIP) -> Container.SEVEN_ZIP
            startsWith(PDF) -> Container.PDF
            startsWith(ZIP) -> Container.ZIP
            startsWith(FLAC) -> Container.FLAC
            startsWith(OGG_S) -> Container.OGG
            // MPEG-4 announces itself at offset 4, and its *brand* at offset 8 is
            // what separates an audiobook from a locked one.
            prefix.size >= BRAND_OFFSET + 4 &&
                FTYP.indices.all { prefix[4 + it] == FTYP[it] } -> {
                val brand = String(prefix, BRAND_OFFSET, 4, Charsets.US_ASCII)
                if (brand in PROTECTED_BRANDS) Container.PROTECTED_AUDIOBOOK else Container.MP4
            }

            startsWith(ID3) -> Container.MP3
            // A bare MPEG frame: eleven sync bits, and a layer field that is not the
            // reserved `00`. Without the layer check every byte pair from 0xFFE0 up
            // matches, and a truncated ZIP happens to contain plenty of those.
            prefix.size >= 2 &&
                prefix[0] == 0xFF.toByte() &&
                prefix[1].toInt() and 0xE0 == 0xE0 &&
                prefix[1].toInt() and 0x06 != 0 -> Container.MP3
            // TAR announces itself at offset 257 rather than at the start, so it
            // is checked last and only when the probe reached that far.
            prefix.size >= TarReader.MAGIC_OFFSET + USTAR.size &&
                USTAR.indices.all { prefix[TarReader.MAGIC_OFFSET + it] == USTAR[it] } ->
                Container.TAR

            else -> null
        }
    }

    /** Reads only [PROBE_LENGTH] bytes from the head of a file. */
    fun container(file: File): Container? = file.inputStream().use { stream ->
        val head = ByteArray(PROBE_LENGTH)
        val read = stream.read(head)
        if (read <= 0) null else container(head.copyOf(read))
    }
}
