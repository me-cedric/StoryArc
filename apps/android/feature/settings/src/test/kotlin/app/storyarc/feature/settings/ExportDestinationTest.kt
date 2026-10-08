package app.storyarc.feature.settings

import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.OutputStream
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * `library-portability` task 2.5: the bytes go only to the place the reader picked. iOS's
 * `LibraryExportSheetTests` asserts the picker receives exactly the prepared bytes.
 */
class ExportDestinationTest {

    @Test
    fun `the bytes are written to the picked destination, whole`() {
        val picked = ByteArrayOutputStream()

        val written = ExportDestination.deliver(byteArrayOf(1, 2, 3)) { picked }

        assertTrue(written)
        assertArrayEquals(byteArrayOf(1, 2, 3), picked.toByteArray())
    }

    @Test
    fun `a reader who closes the picker without choosing writes nothing and opens nothing`() {
        assertFalse(ExportDestination.deliver(byteArrayOf(1, 2, 3), open = null))
    }

    @Test
    fun `a destination that cannot be opened writes nothing`() {
        assertFalse(ExportDestination.deliver(byteArrayOf(1)) { null })
    }

    @Test
    fun `a destination that fails while writing is reported, not thrown`() {
        val failing = object : OutputStream() {
            override fun write(b: Int) = throw IOException("disk full")
        }

        assertFalse(ExportDestination.deliver(byteArrayOf(1)) { failing })
    }

    @Test
    fun `the destination is closed once the bytes are written`() {
        var closed = 0
        val stream = object : ByteArrayOutputStream() {
            override fun close() {
                closed += 1
            }
        }

        ExportDestination.deliver(byteArrayOf(1)) { stream }

        assertEquals(1, closed)
    }
}
