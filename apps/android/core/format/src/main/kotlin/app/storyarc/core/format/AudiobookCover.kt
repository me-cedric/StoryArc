package app.storyarc.core.format

import android.media.MediaMetadataRetriever
import java.io.File

/**
 * Where an audiobook's own artwork comes from, read once at index time.
 *
 * Task 16.9, `audio-playback`'s *The full player*: no audiobook cover was ever extracted, so
 * the shelf, the player and the lock screen all drew the coverless well for every audiobook —
 * even one whose file carries its own picture. Two ways in:
 *
 * - **A single file's embedded artwork.** `MediaMetadataRetriever.getEmbeddedPicture()` reads
 *   an MP4 `covr` atom or an ID3 `APIC` frame under the one call — Android's own framework
 *   already does the container-specific work, the same way iOS's `AVAsset.commonMetadata`
 *   does under `.commonIdentifierArtwork`.
 * - **A folder's own loose cover image**, for the one shape with no single file to embed one
 *   in: the names a media server's own `folder.jpg` convention already uses.
 *
 * What this does *not* do is decode anything. [CoverLoader] already owns "bytes in, a sized
 * `Bitmap` out" for every other format, and an audiobook's cover is bytes exactly like a
 * comic page's — this only has to find them once and say where they are.
 */
object AudiobookCover {

    /**
     * The names a folder's own cover is looked for by, in the order they are tried.
     *
     * [LooseCover.fileNames] since task 1.2: the same question is now asked for every format
     * rather than for audiobooks alone, so one list answers it. The audio names this held
     * before are the first six of that list, in the same order, and `poster` — which a media
     * server writes and which this did not know — is found now too.
     */
    val folderCoverNames = LooseCover.fileNames

    /**
     * A single audio file's own embedded artwork, or `null` where it carries none or
     * [path] cannot be opened at all.
     *
     * `path` rather than a `Uri`: this is reached only where a real path already exists —
     * the file itself, or the `/proc/self/fd/N` a content `Uri` can offer — the same
     * narrowing `comicFromSource`'s own `decoderPath` already accepts for libarchive. A
     * source with neither reads no embedded cover, the same honest degradation a compressed
     * CBR over such a source already accepts for its own pages.
     */
    fun embedded(path: String): ByteArray? {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(path)
            retriever.embeddedPicture
        } catch (_: Exception) {
            null
        } finally {
            retriever.release()
        }
    }

    /**
     * A loose cover image beside a folder's own tracks, by the first of
     * [folderCoverNames] that exists.
     */
    fun inFolder(folder: File): File? = LooseCover.inFolder(folder)
}

/**
 * Where embedded artwork is written once it has been read out of its container.
 *
 * A single file's cover has no path of its own the way a folder's loose image or a comic's
 * archive entry does — the bytes exist only inside the container until something reads them
 * out — so this is the one place in the audio path that writes rather than only locates.
 * `Publication.coverPath` carries the file this writes, and [CoverLoader] reads it back
 * exactly as it reads a comic's cover page or an EPUB's href.
 */
class AudiobookCoverStore(private val directory: File) {

    /**
     * Writes [data] under a name derived from [source]'s own path, replacing whatever was
     * written for it before, and returns the file's own path.
     *
     * Failure is silent and correct, the same rule [CoverCache.store] follows: a device with
     * no room left should index the book, not refuse to.
     */
    fun write(data: ByteArray, source: File): String? = write(data, source.path)

    /**
     * The same, for a container that has no path on this device.
     *
     * Task 1.1: a Storage Access Framework folder is reached by a document `Uri` and never by
     * a path, so its own artwork is keyed by that `Uri`'s own string instead. The two cases
     * share one hash and one directory, because what a key has to do is tell one publication
     * from another and both strings already do.
     */
    fun write(data: ByteArray, key: String): String? = runCatching {
        directory.mkdirs()
        val file = file(key)
        file.writeBytes(data)
        file.path
    }.getOrNull()

    /**
     * Keyed by a hash of the source path rather than the path itself, for the reason
     * [CoverCache.file] already gives: a path carries separators, and a file name is not a
     * place to find that out.
     */
    private fun file(key: String): File {
        var hash = -0x340d631b7bdddcdbL // FNV-1a offset basis
        key.toByteArray().forEach { byte ->
            hash = (hash xor byte.toLong()) * 0x100000001b3L
        }
        return File(directory, hash.toString(36))
    }
}
