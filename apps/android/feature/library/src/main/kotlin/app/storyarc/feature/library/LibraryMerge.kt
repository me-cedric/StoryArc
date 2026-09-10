package app.storyarc.feature.library

import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.Source
import app.storyarc.core.model.SourcePrecedence
import java.util.UUID

/**
 * What a row becomes when the library meets the same publication again.
 *
 * The old answer was "the same row, re-attributed": only the source changed, and every other
 * field stayed as first found. That is right for a file, whose metadata is read out of the
 * file itself and does not change unless the file does. It is wrong for a server.
 *
 * `sources` requires a refresh to "re-fetch the catalogue" and "update the view
 * incrementally", and `MetadataOrigin.AUTHORITATIVE` means the server owns the answer. A row
 * a server supplied must therefore take the server's newer answer -- otherwise a title
 * corrected on the server, or by a bug fixed in this app, is stuck in the library cache
 * until a reader clears it by hand. That is exactly what happened: chapters cached as
 * "-100000" stayed "-100000" after the code that produced them was fixed.
 *
 * **A downloaded file still wins over a server's description of it.** A row with something
 * on disk keeps what was read from the file, because that is the publication the reader
 * opens; only a row with nothing on disk is re-described.
 */
internal object LibraryMerge {

    /**
     * The row to keep: [existing] re-attributed, or [found] where a source owns the answer.
     *
     * [hasFile] is whether the library holds a local path for the existing row.
     */
    fun merged(
        existing: Publication,
        found: Publication,
        sourceId: UUID?,
        hasFile: Boolean,
    ): Publication = if (found.origin == MetadataOrigin.AUTHORITATIVE && !hasFile) {
        // The server's description, kept under the row's own identity so nothing stored
        // against it moves -- `PublicationIdentity.key` must not change.
        found.copy(identity = existing.identity, sourceId = sourceId)
    } else {
        existing.copy(sourceId = sourceId)
    }

    /**
     * Whether a find replaces the row already on the shelf.
     *
     * [SourcePrecedence] answers the question this started as: two sources hold the same
     * publication, and the registry's order decides whose copy the row is. It answers
     * *strictly*, which is right for that question and wrong for the other one -- a source
     * re-read is not a different source, so it lost every comparison with itself and a
     * refresh could never correct anything it had already written.
     */
    fun replaces(found: UUID?, existing: UUID?, sources: List<Source>): Boolean =
        found == existing || SourcePrecedence.prefers(found, existing, sources)
}
