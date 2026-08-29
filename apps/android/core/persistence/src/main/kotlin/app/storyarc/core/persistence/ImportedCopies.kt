package app.storyarc.core.persistence

import android.content.ContentResolver
import android.net.Uri
import android.provider.OpenableColumns
import app.storyarc.core.model.Download
import app.storyarc.core.model.DownloadLibrary
import app.storyarc.core.model.PublicationFormat
import java.io.File
import java.io.IOException
import java.io.InputStream
import java.util.UUID

/**
 * A publication copied into storage the app owns.
 *
 * `local-library`: the app "SHALL let a user import a publication into app-managed storage,
 * so that the copy survives the original being moved or deleted". The bytes go where
 * downloaded bytes already go. [DownloadStore] owns a directory that is made once, kept out
 * of backups, and totalled from the disk rather than from a record — a second store for the
 * same job would be a second place for the list and the files to disagree, which is the
 * failure that store exists to prevent.
 *
 * What makes a copy an *import* is the source it is attributed to, not where it sits. So the
 * identifier of the "On this device" source is fixed rather than generated: the source has
 * to be the same one on the next launch, and a new identifier every launch would leave a
 * reader with a row of empty sources. iOS's `ImportedCopies` holds the same value.
 */
object ImportedCopies {
    /** The identity of the "On this device" source. */
    val SOURCE_ID: UUID = UUID.fromString("9e0d1cef-0000-4000-8000-000000000001")

    /**
     * Whether a record describes a copy the reader imported rather than one fetched from a
     * source.
     *
     * Asked in three places that must treat the two differently: an import is never swept
     * away by "remove downloads after finishing", it is attributed to a source the reader
     * did not configure, and its removal says something a download's does not.
     */
    fun isImported(download: Download): Boolean = download.sourceId == SOURCE_ID

    /**
     * What an imported copy is called in the record.
     *
     * The original's name and its size, so importing the same file twice is one copy rather
     * than two rows of the same book. Deliberately not the original's `Uri`: a provider
     * hands the same file over under a different one each time, and the requirement is that
     * the copy survives the original "being moved or deleted".
     */
    fun identity(name: String, bytes: Long): String = "imported:$name:$bytes"

    /** Why an import did not happen. */
    sealed class ImportException(message: String) : Exception(message) {
        /**
         * The file is not in a format StoryArc reads. Carries the format's own name,
         * because `local-library` forbids a refusal that does not say what it refused.
         */
        class Unsupported(val format: String) : ImportException("unsupported format: $format")

        /** The bytes could not be read, or could not be written. */
        class Unreadable(reason: String) : ImportException(reason)
    }
}

/**
 * What an import produced: the new record, the file it landed in, and the library holding
 * it. All three together because they are one act — a record without its file is a library
 * that lost a book, and a file without its record is bytes nothing can find.
 */
data class ImportedCopy(
    val library: DownloadLibrary,
    val download: Download,
    val file: File,
) {
    /** What the copy weighs, which is what `local-library` asks the app to report. */
    val bytes: Long get() = download.downloadedBytes
}

/**
 * Copies a publication the reader picked into app storage and records it.
 *
 * The `Uri` overload of the one below. Android hands a picked file over as a provider `Uri`
 * with no path behind it, so this is the only way in from the picker — and splitting the
 * stream out is what lets the copying itself be tested without a device.
 */
fun DownloadStore.importing(
    resolver: ContentResolver,
    original: Uri,
    library: DownloadLibrary,
): ImportedCopy = importing(
    name = documentNameOf(resolver, original),
    origin = original.toString(),
    library = library,
) {
    resolver.openInputStream(original)
        ?: throw ImportedCopies.ImportException.Unreadable("the file could not be opened")
}

/**
 * Copies a publication into app storage and records it.
 *
 * Importing the same file twice is one copy: the record is keyed on the original's name and
 * size, and [DownloadLibrary.queueing] already refuses a second row for an identifier it
 * holds. A reader who taps Import on a comic they imported last week gets the copy they
 * already have rather than a second one beside it.
 *
 * The bytes are counted as they are written rather than asked of the provider. A provider
 * may report no size at all, and `local-library` asks the app to report the space used — a
 * number that was never measured is not a report.
 *
 * @param open how to reach the original. Read once, never held: the copy can only outlive
 *   the original if it never owned it.
 */
fun DownloadStore.importing(
    name: String,
    origin: String,
    library: DownloadLibrary,
    open: () -> InputStream,
): ImportedCopy {
    val extension = name.substringAfterLast('.', "").lowercase()
    val format = PublicationFormat.entries.firstOrNull { it.name.lowercase() == extension }
    val mediaType = format?.mediaType
        ?: throw ImportedCopies.ImportException.Unsupported(
            extension.uppercase().ifEmpty { name },
        )

    prepare()
    // Written to one side first, because the identity the copy is filed under is its size
    // and the size is only known once every byte has arrived.
    val staging = File(directory, "importing-${UUID.randomUUID()}")
    val bytes = try {
        open().use { input -> staging.outputStream().use { output -> input.copyTo(output) } }
    } catch (cause: IOException) {
        staging.delete()
        throw ImportedCopies.ImportException.Unreadable(cause.message ?: "the file could not be read")
    }

    val id = ImportedCopies.identity(name, bytes)
    val stem = name.substringBeforeLast('.')
    val file = location(id, extension, stem)

    val existing = library[id]
    if (existing != null && file.exists()) {
        // Already here, so the copy is the one the reader already has.
        staging.delete()
        return ImportedCopy(library, existing, file)
    }

    prepare(file)
    file.delete()
    if (!staging.renameTo(file)) {
        staging.delete()
        throw ImportedCopies.ImportException.Unreadable("the copy could not be put in place")
    }

    val record = Download(
        id = id,
        sourceId = ImportedCopies.SOURCE_ID,
        title = stem,
        // Where it came from, so a record can say what was imported. Never read back to
        // fetch anything: an import has nothing to retry.
        remote = origin,
        mediaType = mediaType,
        expectedBytes = bytes,
        downloadedBytes = bytes,
    )
    // Finished through the library's own vocabulary rather than by constructing the state
    // here, so the copy carries a completion date like every other row does.
    val saved = library.queueing(record).marking(id, Download.State.Finished)
    save(saved)
    val stored = saved[id]
        ?: throw ImportedCopies.ImportException.Unreadable("the copy could not be recorded")
    return ImportedCopy(saved, stored, file)
}

/**
 * Every copy the reader imported, largest first.
 *
 * Largest first because that is the order the question "what can I delete" is asked in, and
 * it is the order the storage screen already lists what is on the device.
 */
fun DownloadStore.imports(library: DownloadLibrary): List<Download> =
    library.finished.filter(ImportedCopies::isImported).sortedByDescending { it.downloadedBytes }

/**
 * Where an imported copy's bytes are, from its record alone.
 *
 * The store chose the path when it wrote the file and has to choose the same one to find it
 * again, which is why [PublicationFormat.mediaType] has to be the inverse of the lookup that
 * put it there.
 */
fun DownloadStore.locationOf(download: Download): File = location(
    download.id,
    PublicationFormat.ofMediaType(download.mediaType)?.name?.lowercase() ?: "bin",
    download.title,
)

/**
 * The provider's own name for the file, which is the only name a reader recognises.
 *
 * Never throws: it is also what a refusal is worded with, and a refusal that could not name
 * the file would be the generic failure `local-library` forbids.
 */
fun documentNameOf(resolver: ContentResolver, uri: Uri): String {
    resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
        if (cursor.moveToFirst() && !cursor.isNull(0)) return cursor.getString(0)
    }
    return uri.lastPathSegment?.substringAfterLast('/') ?: uri.toString()
}
