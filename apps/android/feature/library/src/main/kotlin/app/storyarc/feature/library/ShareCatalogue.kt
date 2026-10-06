package app.storyarc.feature.library

import app.storyarc.core.format.PublicationAccess
import app.storyarc.core.format.PublicationIndexer
import app.storyarc.core.format.RandomAccessSource
import app.storyarc.core.model.Publication
import kotlinx.coroutines.flow.update
import java.net.URLDecoder

/**
 * What a share row learns once its own headers are read.
 *
 * [SmbContributor] builds a row from a file name and nothing else: the format is the
 * extension's claim, the streaming state is the optimistic default, and there is no page
 * count and no recorded cover. That is deliberate while a shelf is being filled -- fifty
 * archives pulled over a network to draw one screen is the cost that bounded walk exists to
 * avoid -- but it leaves every share row stating things that are merely plausible, and a
 * `.cbr` that is really a ZIP is catalogued as a RAR until somebody taps it.
 *
 * D28 is the other half of that bargain. When a row nears the viewport, read *that one
 * file's* headers over the share and merge what they say into it. A header read is ranged and
 * decompresses nothing, which is exactly what `publication-formats`' *A remote publication is
 * catalogued without being transferred* requires -- so the shelf learns the real format, the
 * page count, the cover path and the streaming state for the rows a reader is actually
 * looking at, and for no others.
 *
 * iOS keeps the same pair in `ShareCatalogue.swift`.
 */
internal object ShareCatalogue {

    /**
     * The scheme a share row's address carries. `LibraryMerge` recognises a share by the same
     * prefix, for the same reason: a share row is the one kind whose normalised path is an
     * address rather than a file.
     */
    private const val SHARE_SCHEME = "smb://"

    /**
     * Whether this row is still the name-only one [SmbContributor] built.
     *
     * **The digest is the mark, not the page count.** [PublicationIndexer.index] records one
     * on every row it builds, while a PDF or an audiobook read from a source legitimately
     * comes back with no page count -- keying on that would ask the share for those rows'
     * headers again on every redraw. A row whose share did not answer keeps its absent digest
     * and is asked once more the next time it appears, which is what *offline is a normal
     * state* asks for.
     *
     * A row that is already refused is left alone: a `.cb7` is named from its extension
     * before any read ([SmbContributor]), and there is nothing a header could add to a
     * container the app does not open.
     */
    fun needsCataloguing(publication: Publication): Boolean =
        publication.isOpenable &&
            publication.identity.contentDigest == null &&
            publication.identity.normalizedPath?.startsWith(SHARE_SCHEME) == true

    /**
     * The row, with what a ranged index of its own headers found merged into it.
     *
     * [indexed] is the base rather than [row], because it carries the four facts D28 asks for
     * *and* the embedded metadata that outranks a filename guess -- which is the whole of
     * [app.storyarc.core.model.MetadataOrigin]'s precedence, and the same way round
     * [LibraryMerge] already settles a downloaded file against the row that stood for it.
     *
     * What only the walk knew is put back: which source listed the file, what the share's own
     * directory entry said it weighs, and the marks a reader has already put on the row. The
     * identity is not: [indexed] carries the row's own identity with the digest this read
     * established, and `PublicationIdentity.stableId` prefers the path, so the row keeps the
     * id every shelf, list and progress record already files it under.
     */
    fun merged(row: Publication, indexed: Publication): Publication = indexed.copy(
        sourceId = row.sourceId,
        fileSize = row.fileSize,
        status = row.status,
        addedAtEpochMillis = row.addedAtEpochMillis,
        modifiedAtEpochMillis = row.modifiedAtEpochMillis,
    )

    /**
     * One ranged read of a row's own headers, or null when there is nothing to learn.
     *
     * [open] defaults to [PublicationAccess.remoteSource] rather than a share client of its
     * own: that registry is already how the reader opens a share, so the one registration
     * `AppDependencies` makes serves the opener and the shelf alike. It is a parameter for
     * [SmbContributor.page]'s reason -- a share cannot be faked without a real SMB server, and
     * what this decides has nothing to do with the protocol underneath it, so
     * `ShareCatalogueTest` stands a fixture behind it instead of claiming the one registered
     * scheme out from under another suite.
     *
     * A share that does not answer, and a container that refuses to be read at all, both give
     * null: the row stays as the walk left it rather than becoming an error a reader has to
     * dismiss. `network-share` is explicit that an unreachable share is a normal state, and
     * the share browser is where a refusal is named when a reader asks for one.
     */
    suspend fun catalogued(
        row: Publication,
        open: suspend (String) -> RandomAccessSource? = { PublicationAccess.remoteSource(it) },
    ): Publication? {
        if (!needsCataloguing(row)) return null
        val path = row.identity.normalizedPath ?: return null
        val indexed = runCatching {
            val source = open(path) ?: return null
            PublicationIndexer.index(
                source = source,
                name = decoded(path.substringAfterLast('/')),
                identity = row.identity,
                seriesHint = seriesHint(path),
            )
        }.getOrNull() ?: return null
        return merged(row, indexed)
    }

    /**
     * The folder this file sits in, as [SmbContributor] passed it to the filename reader.
     *
     * Re-derived from the address rather than carried on the row, because the row does not
     * keep it -- and losing it here would make a catalogued row's series worse than the one
     * the walk gave it, for a publication whose archive carries no metadata of its own.
     */
    private fun seriesHint(path: String): String? =
        path.substringBeforeLast('/', "").substringAfterLast('/', "")
            .takeIf { it.isNotEmpty() }
            ?.let(::decoded)

    /**
     * A path component as the share named it. An address escapes a space as `%20`, and the
     * filename reader is reading a title, not a URL.
     */
    private fun decoded(component: String): String =
        runCatching { URLDecoder.decode(component, Charsets.UTF_8.name()) }.getOrDefault(component)
}

/**
 * Catalogues a share row from its own headers, and keeps what came back.
 *
 * Called from [LibraryViewModel.cover], which is the hook a cell already fires as it appears.
 * `publication-formats` puts cover extraction there for the reason D28 puts this there, and
 * doing both on the one appearance keeps a share row to a single round of reads instead of
 * two.
 *
 * Returns the row to draw, so the caller reads the cover out of what was just learned rather
 * than out of the name-only row it was handed. An extension rather than a method because
 * `LibraryViewModel.kt` is over its line cap and may not grow -- the same reason
 * [ServerLibrary.cachedCover] sits outside it.
 */
internal suspend fun LibraryViewModel.catalogueIfOnShare(publication: Publication): Publication {
    val found = ShareCatalogue.catalogued(publication) ?: return publication
    _publications.update { rows -> rows.map { if (it.id == found.id) found else it } }
    // The shelf draws from the arranged list, not from `_publications` -- without this the
    // row keeps the format and the refusal its file name implied until the next rearrange.
    rebuild()
    return found
}
