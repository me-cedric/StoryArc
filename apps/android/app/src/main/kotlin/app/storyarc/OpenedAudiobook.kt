package app.storyarc

import android.content.ContentResolver
import android.net.Uri
import android.provider.DocumentsContract
import androidx.core.net.toUri
import app.storyarc.core.format.AudiobookFolder
import app.storyarc.core.format.SafTree
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.playback.Audiobook
import java.io.File

/**
 * A publication the library holds, turned into something the player can open.
 *
 * The seam between the format layer and `:core:playback`, and it lives in the app for the
 * reason every seam like it does: `:core:format` reads containers and knows nothing about a
 * decoder, `:core:playback` decodes and knows nothing about a library, and the app is the
 * one layer entitled to know both exist.
 *
 * **A folder is walked here rather than in the player.** The parts, their order and their
 * names are `AudiobookFolder`'s answer — the same natural sort that makes a folder of
 * images one comic — and handing the player a list rather than a directory keeps
 * `:core:playback` free of a filesystem it has no business reading.
 */
internal object OpenedAudiobook {

    /**
     * The audiobook a publication is, or null when it is not one.
     *
     * Null rather than an exception: the caller is a routing decision — reader or player —
     * and "this is not an audiobook" is one of its two ordinary answers.
     *
     * @param path where the publication's bytes are, as the library recorded it.
     */
    fun of(publication: Publication, path: String, resolver: ContentResolver? = null): Audiobook? {
        if (!publication.format.isAudio) return null

        val sources = when (publication.format) {
            PublicationFormat.AUDIO_FOLDER ->
                if (path.startsWith("content://") && resolver != null) {
                    documentParts(resolver, path)
                } else {
                    folderParts(path)
                }
            // A single file, chaptered or not. Its parts are the container's own chapter
            // marks, which the player reads when it opens the file — see `AudiobookSource`.
            // Indexing deliberately does not, because an extractor per file would cost a
            // library of five hundred audiobooks a decode pass per scan.
            else -> listOf(Audiobook.AudioPart(uri = uriOf(path), title = publication.displayTitle))
        }
        if (sources.isEmpty()) return null

        return Audiobook(
            id = publication.id,
            title = publication.displayTitle,
            author = publication.authors.firstOrNull(),
            sources = sources,
            skippedPartCount = publication.skippedPageCount,
        )
    }

    /**
     * The parts of a folder picked through the Storage Access Framework.
     *
     * A document tree has no path to walk, so the folder is listed again here and
     * `AudiobookFolder` is asked the same question it is asked of a `File` — what is a
     * part, in what order, and what is it called. Listing twice is the cost of a provider
     * that hands back a `Uri` rather than a directory; the alternative is a `Publication`
     * carrying a list of document ids, which is a copy of the folder that goes stale.
     */
    private fun documentParts(resolver: ContentResolver, folder: String): List<Audiobook.AudioPart> {
        val uri = folder.toUri()
        val documentId = runCatching { DocumentsContract.getDocumentId(uri) }.getOrNull()
            ?: return emptyList()
        // The tree the document belongs to. A document `Uri` built from a tree carries
        // both ids, and `children` needs the tree to build its own children's URIs.
        val tree = runCatching { DocumentsContract.buildTreeDocumentUri(uri.authority, DocumentsContract.getTreeDocumentId(uri)) }
            .getOrNull() ?: return emptyList()

        val entries = runCatching { SafTree.children(resolver, tree, documentId) }.getOrElse {
            return emptyList()
        }
        val byName = entries.filterNot { it.isDirectory }.associateBy { it.name }
        return AudiobookFolder
            .of(entries.filterNot { it.isDirectory }.map { AudiobookFolder.Candidate(it.name, it.size) })
            .parts
            .mapNotNull { part ->
                val entry = byName[part.path] ?: return@mapNotNull null
                Audiobook.AudioPart(
                    uri = SafTree.documentUri(tree, entry.documentId).toString(),
                    title = part.title,
                )
            }
    }

    private fun folderParts(path: String): List<Audiobook.AudioPart> {
        val root = File(path)
        if (!root.isDirectory) return emptyList()
        return AudiobookFolder.open(root).parts.map { part ->
            Audiobook.AudioPart(
                uri = uriOf(File(root, part.path).absolutePath),
                title = part.title,
            )
        }
    }

    /**
     * A path or a content URI, as media3's data source wants it.
     *
     * A `content://` or `file://` string is already a URI and is left alone; a bare path is
     * not, and handing one to `MediaItem.fromUri` unparsed is how a book with a `#` or a
     * `?` in its name silently fails to open.
     */
    private fun uriOf(path: String): String =
        if (path.startsWith("content://") || path.startsWith("file://")) {
            path
        } else {
            Uri.fromFile(File(path)).toString()
        }
}
