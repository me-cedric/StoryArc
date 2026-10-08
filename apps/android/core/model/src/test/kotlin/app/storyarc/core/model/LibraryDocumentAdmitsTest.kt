package app.storyarc.core.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * `library-portability` task 6.5: the import screen refuses a file by the size the provider
 * reports, before it reads a byte. iOS's `LibraryDocumentAdmitsTests` asserts the same rows.
 */
class LibraryDocumentAdmitsTest {

    @Test
    fun `a file at the limit is admitted`() {
        assertNull(LibraryDocumentCoder.admits(LibraryDocumentCoder.MAXIMUM_BYTES))
    }

    @Test
    fun `a file one byte over is refused by name, with both sizes`() {
        val over = LibraryDocumentCoder.MAXIMUM_BYTES + 1

        assertEquals(
            LibraryDocumentFailure.TooLarge(over, LibraryDocumentCoder.MAXIMUM_BYTES),
            LibraryDocumentCoder.admits(over),
        )
    }

    @Test
    fun `the limit is injectable so a test need not allocate 64 MiB`() {
        assertEquals(LibraryDocumentFailure.TooLarge(11, 10), LibraryDocumentCoder.admits(11, limit = 10))
    }
}
