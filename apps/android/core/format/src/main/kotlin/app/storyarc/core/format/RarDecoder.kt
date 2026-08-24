package app.storyarc.core.format

import java.io.File

/**
 * Decompresses RAR entries, and nothing else.
 *
 * This is the whole of libarchive's job in StoryArc. [RarReader] already answers
 * every question the library asks — entry names, sizes, the cover, solid,
 * encrypted — from headers alone, and reads stored entries directly. What it
 * cannot do is undo RAR's LZ and PPMd coding, which is a real codec and the one
 * thing worth a C dependency (ADR-0005).
 *
 * So the seam is deliberately narrow: a path in, entry bytes out. Nothing above
 * this object knows libarchive exists, which is what makes the dependency
 * replaceable and keeps the untrusted-input surface to a single call. iOS's
 * `RarDecoder` has the same shape for the same reason.
 *
 * ponytail: takes a [File] rather than a [RandomAccessSource]. Decompressing an
 * entry is sequential by nature, and a remote publication is downloaded before it
 * is read anyway — [RarReader] is what makes *indexing* a remote CBR cheap. Wire
 * libarchive's callback API through JNI if streaming a compressed remote CBR ever
 * becomes a real requirement.
 */
object RarDecoder {
    /** Whether the native library loaded. False on a host JVM, where there is none. */
    val isAvailable: Boolean = runCatching { System.loadLibrary("storyarc_rar") }.isSuccess

    /** One entry, as libarchive reports it. */
    data class NativeEntry(val path: String, val size: Long)

    /**
     * Unpacked bytes for one entry, found by its path inside the archive.
     *
     * @throws RarException.NeedsDecoder when the native library is absent, which
     *   is a build or packaging problem rather than a bad archive.
     * @throws RarException.Malformed when libarchive could not produce the entry.
     */
    fun data(archive: File, entryName: String): ByteArray {
        require()
        return nativeEntryData(archive.absolutePath, entryName)
            ?: throw RarException.Malformed(
                "libarchive could not read '$entryName' from ${archive.name}",
            )
    }

    /**
     * Every named entry's unpacked bytes in one pass over the archive.
     *
     * One pass rather than one open per page. A solid archive makes this the only
     * affordable shape: reading page 30 there means decompressing 1 to 29, so
     * asking page by page would be quadratic. Entries libarchive could not
     * produce are absent from the result rather than present and empty.
     */
    fun data(archive: File, entryNames: Collection<String>): Map<String, ByteArray> {
        require()
        if (entryNames.isEmpty()) return emptyMap()
        val names = entryNames.toList()
        val blocks = nativeEntriesData(archive.absolutePath, names.toTypedArray())
            ?: throw RarException.Malformed("libarchive could not open ${archive.name}")
        return names.indices.mapNotNull { index ->
            blocks.getOrNull(index)?.let { names[index] to it }
        }.toMap()
    }

    /**
     * Entry names and sizes as *libarchive* sees them.
     *
     * Not used for indexing — [RarReader] does that without a C library. This
     * exists so a test can assert the two agree, which is the only way to know the
     * header parser and the decoder are looking at the same archive.
     */
    fun entryNames(archive: File): List<NativeEntry> {
        require()
        val rows = nativeEntryNames(archive.absolutePath)
            ?: throw RarException.Malformed("libarchive could not open ${archive.name}")
        return rows.mapNotNull { row ->
            val tab = row.lastIndexOf('\t')
            if (tab <= 0) null else NativeEntry(row.take(tab), row.substring(tab + 1).toLong())
        }
    }

    private fun require() {
        if (!isAvailable) {
            throw RarException.NeedsDecoder(
                // -2 rather than a method number: the archive is fine and the
                // library is missing, which is a different problem entirely.
                method = -2,
            )
        }
    }

    private external fun nativeEntryNames(archivePath: String): Array<String>?

    private external fun nativeEntryData(archivePath: String, entryName: String): ByteArray?

    private external fun nativeEntriesData(
        archivePath: String,
        entryNames: Array<String>,
    ): Array<ByteArray?>?
}
