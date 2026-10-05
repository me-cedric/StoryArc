package app.storyarc.feature.library

import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * What a shelf's download confirmation counts.
 *
 * `collections-and-reading-lists` has the app state "the item count and total size before
 * starting". It counted every member this device did not already hold, and
 * [LibraryViewModel.keepOffline] then copied fewer: a folder of images has no single file to
 * take, a publication no decoder opens has nothing worth fetching, and a network share row has
 * no road at all. The reader was told a number and a size that the action did not deliver, and
 * was told nothing about the difference. iOS's `ShelfDownloadCountTests` asks the same.
 */
class ShelfDownloadCountTest {

    private fun publication(
        path: String,
        format: PublicationFormat = PublicationFormat.CBZ,
    ) = Publication(
        identity = PublicationIdentity(normalizedPath = path),
        format = format,
        displayTitle = path,
        origin = MetadataOrigin.INFERRED,
    )

    @Test
    fun `a member the rule refuses is left out of the count`() {
        val kept = publication("/comics/one.cbz")
        val refused = publication("/comics/two.cbz")

        val wanted = downloadableMembers(setOf(kept.id, refused.id), listOf(kept, refused)) {
            it.id == kept.id
        }

        assertEquals(setOf(kept.id), wanted)
    }

    @Test
    fun `a member the shelf names and the library no longer holds is left out`() {
        val held = publication("/comics/one.cbz")

        val wanted = downloadableMembers(setOf(held.id, "path:/comics/gone.cbz"), listOf(held)) { true }

        assertEquals(setOf(held.id), wanted)
    }

    /**
     * The real rule, not a stub: the three kinds of member the count used to overstate, asked
     * of [PublicationActions.canCopy] itself. Every one of them has a location the library can
     * place, which is what makes the refusals about the member and not about a missing file.
     */
    @Test
    fun `a folder of images is out, and an ordinary comic and a share row are in`() {
        val comic = publication("/comics/one.cbz")
        val folder = publication("/comics/loose", format = PublicationFormat.IMAGE_FOLDER)
        val share = publication("smb://nas/comics/one.cbz")
        val locations = mapOf(
            comic.id to "/comics/one.cbz",
            folder.id to "/comics/loose",
            share.id to "smb://nas/comics/one.cbz",
        )

        val wanted = downloadableMembers(locations.keys, listOf(comic, folder, share)) {
            PublicationActions.canCopy(
                it,
                isLocalFile = isOnDevice(locations[it.id]),
                isQueueableRemote = PublicationActions.isQueueableRemote(it),
                isShare = isShareLocation(locations[it.id]),
            )
        }

        assertEquals(setOf(comic.id, share.id), wanted)
    }

    /**
     * Task 7.7's second half, from the side the first half could not state.
     *
     * Wave 8 narrowed the stated count to what one tap copies, and a share member was out of
     * it because [KeepOffline] had no road for one. It has the chunked copy now, so the member
     * belongs in the count again -- and this fails if the road is taken away without the count
     * being narrowed with it.
     */
    @Test
    fun `a share row is a member a bulk download now copies`() {
        val share = publication("smb://nas/comics/one.cbz")

        assertTrue(
            "A share member is skipped silently again -- task 7.7's own defect.",
            PublicationActions.canCopy(
                share,
                isLocalFile = false,
                isQueueableRemote = false,
                isShare = isShareLocation("smb://nas/comics/one.cbz"),
            ),
        )
    }
}
