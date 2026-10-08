package app.storyarc.core.model

import java.io.File

/**
 * The folder a [ReadingSnapshot] and its cover live in.
 *
 * The app writes, the widget reads. A file and not a database, so the widget's read is one
 * file read (ADR-0011). The folder is under the app's files, not its cache: the system may
 * empty a cache between the app's last run and the widget's next draw. iOS's
 * `ReadingSnapshotStore` mirrors it.
 */
class ReadingSnapshotStore(val folder: File) {

    private val snapshotFile get() = File(folder, SNAPSHOT_FILE)

    /** The stored snapshot, or null when there is none or it cannot be read. */
    fun read(): ReadingSnapshot? =
        runCatching { snapshotFile.readText() }.getOrNull()?.let(ReadingSnapshot::decoded)

    /** The cover of a snapshot's own publication, or null when the app has not written one. */
    fun cover(snapshot: ReadingSnapshot): File? = File(folder, snapshot.coverFile).takeIf { it.isFile }

    /**
     * Stores what the widget is to show, and says whether anything changed.
     *
     * [cover] is asked only when this publication has no cover file yet, because decoding a
     * cover costs far more than this write. A null snapshot removes everything, so a widget
     * never names a book the library no longer offers. Covers of other publications are
     * removed in every case.
     *
     * False means the stored state is already this one, so there is no reason to redraw.
     */
    suspend fun write(snapshot: ReadingSnapshot?, cover: suspend () -> ByteArray?): Boolean {
        var changed = false
        if (snapshot != null) {
            folder.mkdirs()
            if (cover(snapshot) == null) {
                cover()?.let {
                    File(folder, snapshot.coverFile).writeAtomically(it)
                    changed = true
                }
            }
            if (read() != snapshot) {
                snapshotFile.writeAtomically(snapshot.encoded().encodeToByteArray())
                changed = true
            }
        } else if (snapshotFile.delete()) {
            changed = true
        }

        val kept = snapshot?.coverFile
        folder.listFiles { file -> file.name.startsWith("cover-") && file.name != kept }
            ?.forEach { if (it.delete()) changed = true }
        return changed
    }

    /** Through a temporary file and a rename, so the widget never reads half a file. */
    private fun File.writeAtomically(bytes: ByteArray) {
        val temporary = File(parentFile, ".$name.tmp")
        temporary.writeBytes(bytes)
        check(temporary.renameTo(this)) { "Could not replace $name" }
    }

    companion object {
        const val SNAPSHOT_FILE = "reading-snapshot.json"
    }
}
