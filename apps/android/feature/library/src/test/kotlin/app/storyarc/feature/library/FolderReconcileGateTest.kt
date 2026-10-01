package app.storyarc.feature.library

import app.storyarc.core.model.FolderSnapshot
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 10.4: a tree with no snapshot yet is one the running scan owns, not the reconcile.
 */
class FolderReconcileGateTest {

    @Test
    fun `a tree with no snapshot yet is left to the running scan`() {
        assertFalse(mayReconcile(null))
    }

    @Test
    fun `a tree with a snapshot, even an empty one, may be reconciled`() {
        assertTrue(mayReconcile(FolderSnapshot()))
    }
}
