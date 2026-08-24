package app.storyarc.core.format

import java.io.File

/**
 * The container formats StoryArc can open.
 *
 * `publication-formats` requires format to be determined from a file's contents,
 * not its extension — a ZIP called `.cbr` still opens. The extension is only ever
 * a hint used to order the sniffing.
 */
enum class PublicationFormat {
    CBZ, CBR, CB7, CBT, EPUB, PDF, IMAGE_FOLDER,
    ;

    /**
     * Whether pages are images rather than reflowable text. Drives which reader
     * opens the publication, and whether a page curl needs a raster.
     */
    val isPagedImages: Boolean
        get() = when (this) {
            CBZ, CBR, CB7, CBT, IMAGE_FOLDER -> true
            EPUB, PDF -> false
        }
}

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
        ;

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
            }
    }

    private val ZIP = byteArrayOf(0x50, 0x4B)
    private val RAR4 = byteArrayOf(0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x00)
    private val RAR5 = byteArrayOf(0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x01, 0x00)
    private val SEVEN_ZIP = byteArrayOf(0x37, 0x7A, 0xBC.toByte(), 0xAF.toByte(), 0x27, 0x1C)
    private val PDF = byteArrayOf(0x25, 0x50, 0x44, 0x46)
    private val USTAR = byteArrayOf(0x75, 0x73, 0x74, 0x61, 0x72) // at offset 257, not 0

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
