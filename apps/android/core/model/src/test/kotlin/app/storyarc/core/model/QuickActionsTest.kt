package app.storyarc.core.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * The home-screen menu, asserted against the same table as iOS's `QuickActionsTests`.
 *
 * `native-experience` asks for quick actions on both platforms, and two independent
 * implementations (ADR-0001) only stay honest if the same cases are put to both. Add a case
 * here, add it there.
 *
 * The identifiers are asserted by name at the end. They are the one part of this the two
 * platforms *share* rather than mirror: a menu already on a reader's home screen carries
 * them, so a rename is a change to stored data, not to a constant.
 */
class QuickActionsTest {

    private fun publication(title: String) = Publication(
        identity = PublicationIdentity(normalizedPath = "/library/$title"),
        format = PublicationFormat.CBZ,
        displayTitle = title,
        origin = MetadataOrigin.INFERRED,
    )

    @Test
    fun `nothing in progress and nothing downloaded leaves the library alone`() {
        assertEquals(
            listOf(QuickAction.Library),
            QuickActions.offered(continuing = null, hasDownloads = false),
        )
    }

    @Test
    fun `downloads appear once there is something in them`() {
        assertEquals(
            listOf(QuickAction.Library, QuickAction.Downloads),
            QuickActions.offered(continuing = null, hasDownloads = true),
        )
    }

    @Test
    fun `a publication in progress is offered, and named`() {
        val bone = publication("Bone 1")
        val offered = QuickActions.offered(bone, hasDownloads = false)

        assertEquals(2, offered.size)
        // The publication's own stable key, not its path: the entry outlives the launch
        // that published it, and the key is what the library can still be asked for.
        assertEquals(QuickAction.ContinueReading(bone.id, "Bone 1"), offered.first())
    }

    @Test
    fun `continue comes first, because it is why the icon was held down`() {
        val offered = QuickActions.offered(publication("Bone 1"), hasDownloads = true)

        assertEquals(
            listOf(
                QuickAction.CONTINUE_ID,
                QuickAction.LIBRARY_ID,
                QuickAction.DOWNLOADS_ID,
            ),
            offered.map { it.id },
        )
    }

    @Test
    fun `a publication with nothing to call it is not offered`() {
        // The entry's whole job is to name the book. A row headed by a blank line is one a
        // reader cannot read, and `offline-downloads` has already met such a title.
        assertEquals(
            listOf(QuickAction.Library),
            QuickActions.offered(publication("   "), hasDownloads = false),
        )
    }

    @Test
    fun `a request is read back from the identifier the system stored`() {
        assertEquals(QuickActionRequest.Library, QuickActionRequest.of(QuickAction.LIBRARY_ID))
        assertEquals(QuickActionRequest.Downloads, QuickActionRequest.of(QuickAction.DOWNLOADS_ID))
        assertEquals(
            QuickActionRequest.ContinueReading("abc"),
            QuickActionRequest.of(QuickAction.CONTINUE_ID, "abc"),
        )
    }

    @Test
    fun `a continue entry carrying no publication is refused rather than guessed at`() {
        assertNull(QuickActionRequest.of(QuickAction.CONTINUE_ID))
        assertNull(QuickActionRequest.of(QuickAction.CONTINUE_ID, ""))
    }

    @Test
    fun `an entry from an older menu is refused rather than treated as the library`() {
        // A menu on a home screen can outlive the app that published it.
        assertNull(QuickActionRequest.of("app.storyarc.quickaction.widget"))
        assertNull(QuickActionRequest.of(""))
        assertNull(QuickActionRequest.of(null))
    }

    @Test
    fun `the three identifiers are the strings both platforms store`() {
        assertEquals("app.storyarc.quickaction.continue", QuickAction.CONTINUE_ID)
        assertEquals("app.storyarc.quickaction.library", QuickAction.LIBRARY_ID)
        assertEquals("app.storyarc.quickaction.downloads", QuickAction.DOWNLOADS_ID)
    }

    @Test
    fun `each entry answers with its own identifier`() {
        assertEquals(
            QuickAction.CONTINUE_ID,
            QuickAction.ContinueReading("x", "Bone 1").id,
        )
        assertEquals(QuickAction.LIBRARY_ID, QuickAction.Library.id)
        assertEquals(QuickAction.DOWNLOADS_ID, QuickAction.Downloads.id)
    }
}
