package app.storyarc.core.persistence

import android.net.Uri
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * 10.10: Android's own half of what `FolderBookmarks` keeps for a handed-over file on iOS.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class RememberedFilesTest {

    private fun uri(name: String): Uri = Uri.parse("content://com.example.documents/$name")

    @Test
    fun `a remembered file comes back`() {
        val files = RememberedFiles(FakePreferences())

        files.remember(uri("Comics.cbz"))

        assertEquals(listOf(uri("Comics.cbz")), files.all())
    }

    @Test
    fun `remembering the same file twice keeps one entry, most recent first`() {
        val files = RememberedFiles(FakePreferences())

        files.remember(uri("Comics.cbz"))
        files.remember(uri("Manga.cbz"))
        files.remember(uri("Comics.cbz"))

        assertEquals(listOf(uri("Comics.cbz"), uri("Manga.cbz")), files.all())
    }

    @Test
    fun `past the limit, the file remembered longest ago falls off`() {
        val files = RememberedFiles(FakePreferences())

        (1..RememberedFiles.LIMIT + 1).forEach { files.remember(uri("$it.cbz")) }

        assertEquals(RememberedFiles.LIMIT, files.all().size)
        assertEquals(uri("${RememberedFiles.LIMIT + 1}.cbz"), files.all().first())
        assertEquals(false, files.all().contains(uri("1.cbz")))
    }

    @Test
    fun `forgetting a file drops only that one`() {
        val files = RememberedFiles(FakePreferences())
        files.remember(uri("Comics.cbz"))
        files.remember(uri("Manga.cbz"))

        files.forget(uri("Comics.cbz"))

        assertEquals(listOf(uri("Manga.cbz")), files.all())
    }
}
