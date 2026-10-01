package app.storyarc.feature.library

import android.app.Application
import android.net.Uri
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * 10.2: re-picking one of several missing folders used to empty the whole
 * `unavailableFolders` list ([LibraryViewModel.addFolder] set it to `emptyList()`
 * unconditionally), so the notice for a *second*, still-missing folder vanished too.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class AddFolderClearsOnlyItsOwnNameTest {

    @Test
    fun `re-picking a folder clears only its own name from the unavailable list`() {
        val library = LibraryViewModel(ApplicationProvider.getApplicationContext<Application>())
        library._unavailableFolders.value = listOf("Comics", "Manga")

        library.addFolder(Uri.parse("content://com.example.documents/tree/Comics"))

        assertEquals(listOf("Manga"), library.unavailableFolders.value)
    }
}
