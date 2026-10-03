package app.storyarc.feature.library

import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.smb.SmbAddress
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * `network-share`'s *Network changes*: a reader opened from a share's own browser has to know
 * which source it reads from, or it cannot say which one went when the path moves.
 */
class SmbPageFilingTest {

    private val share = UUID.randomUUID()
    private val page = SmbPage(share.toString(), "Office NAS", SmbAddress(host = "nas", share = "Comics"))

    private fun publication(sourceId: UUID? = null) = Publication(
        identity = PublicationIdentity(normalizedPath = "smb://nas/Comics/a.cbz"),
        format = PublicationFormat.CBZ,
        displayTitle = "a.cbz",
        origin = MetadataOrigin.INFERRED,
        sourceId = sourceId,
    )

    @Test
    fun `a publication opened from the browser is filed under the share`() {
        assertEquals(share, page.filing(publication()).sourceId)
    }

    @Test
    fun `a publication already filed keeps its own source`() {
        val own = UUID.randomUUID()
        assertEquals(own, page.filing(publication(sourceId = own)).sourceId)
    }
}
