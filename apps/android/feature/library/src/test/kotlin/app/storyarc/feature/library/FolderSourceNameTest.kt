package app.storyarc.feature.library

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** The folder called `primary:Audiobooks`, and the three ways it stops being called that. */
class FolderSourceNameTest {

    private val tree = "content://com.android.externalstorage.documents/tree/primary%3AAudiobooks"

    @Test
    fun theProvidersOwnNameWins() {
        assertEquals(
            "Audiobooks",
            FolderSourceName.of("Audiobooks", "primary:Audiobooks", tree),
        )
    }

    @Test
    fun aDocumentIdLosesItsVolume() {
        // The defect. `substringAfterLast('/')` alone left the whole id, because a tree
        // `Uri`'s last segment has no slash in it at all.
        assertEquals("Audiobooks", FolderSourceName.of(null, "primary:Audiobooks", tree))
    }

    @Test
    fun aNestedDocumentIdLosesBothSeparators() {
        assertEquals("Comics", FolderSourceName.of(null, "primary:Books/Comics", tree))
    }

    @Test
    fun aProviderThatSaysNothingUsefulIsIgnored() {
        assertEquals("Audiobooks", FolderSourceName.of("   ", "primary:Audiobooks", tree))
    }

    @Test
    fun aSourceIsNeverNameless() {
        assertEquals(tree, FolderSourceName.of(null, null, tree))
        assertEquals(tree, FolderSourceName.of(null, "primary:", tree))
    }

    @Test
    fun aFolderNamedBeforeThisIsHealedAndARenamedOneIsNot() {
        assertTrue(FolderSourceName.isRawDocumentId("primary:Audiobooks", "primary:Audiobooks"))
        // A reader's own name, and the correct derivation, are both left alone.
        assertFalse(FolderSourceName.isRawDocumentId("Bedtime", "primary:Audiobooks"))
        assertFalse(FolderSourceName.isRawDocumentId("Audiobooks", "Audiobooks"))
    }
}
