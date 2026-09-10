package app.storyarc.feature.library

import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Which answer a row keeps when the library meets the same publication twice.
 *
 * `sources` requires a refresh to update the view, and `AUTHORITATIVE` means the source owns
 * the answer. Before this, a row kept whatever it was first found as: chapters cached as
 * "-100000" stayed that way after the code producing them was fixed, because a re-read only
 * changed their attribution.
 */
class LibraryMergeTest {

    private val source = UUID.randomUUID()

    private fun publication(
        title: String,
        origin: MetadataOrigin,
        path: String? = null,
    ) = Publication(
        identity = PublicationIdentity(
            serverIdentifier = PublicationIdentity.ServerIdentifier(source, "chapter:1"),
            normalizedPath = path,
        ),
        format = PublicationFormat.CBZ,
        displayTitle = title,
        origin = origin,
    )

    @Test
    fun `a server's newer answer replaces a stale one`() {
        val merged = LibraryMerge.merged(
            existing = publication("-100000", MetadataOrigin.AUTHORITATIVE),
            found = publication("Green Lantern", MetadataOrigin.AUTHORITATIVE),
            sourceId = source,
            hasFile = false,
        )

        assertEquals("Green Lantern", merged.displayTitle)
    }

    @Test
    fun `the row keeps its own identity, so nothing stored against it moves`() {
        val existing = publication("old", MetadataOrigin.AUTHORITATIVE)

        val merged = LibraryMerge.merged(
            existing = existing,
            found = publication("new", MetadataOrigin.AUTHORITATIVE),
            sourceId = source,
            hasFile = false,
        )

        assertEquals(existing.identity, merged.identity)
        assertEquals(existing.id, merged.id)
    }

    @Test
    fun `a downloaded file's own metadata is not overwritten by a description of it`() {
        val merged = LibraryMerge.merged(
            existing = publication("From the file", MetadataOrigin.EMBEDDED, path = "/a.cbz"),
            found = publication("From the server", MetadataOrigin.AUTHORITATIVE),
            sourceId = source,
            hasFile = true,
        )

        assertEquals("From the file", merged.displayTitle)
    }

    @Test
    fun `a scanned file re-found is re-attributed and nothing else`() {
        val merged = LibraryMerge.merged(
            existing = publication("A comic", MetadataOrigin.EMBEDDED, path = "/a.cbz"),
            found = publication("A comic", MetadataOrigin.EMBEDDED, path = "/a.cbz"),
            sourceId = source,
            hasFile = true,
        )

        assertEquals("A comic", merged.displayTitle)
        assertEquals(source, merged.sourceId)
    }
}
