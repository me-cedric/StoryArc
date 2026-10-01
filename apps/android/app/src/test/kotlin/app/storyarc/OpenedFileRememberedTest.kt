package app.storyarc

import android.app.Application
import android.content.Intent
import android.net.Uri
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.persistence.RememberedFiles
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * 10.10: a persistable hand-over grant is taken, and the file remembered -- the one case
 * `local-library`'s "is not kept" names as its own exception.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class OpenedFileRememberedTest {

    private val application: Application get() = ApplicationProvider.getApplicationContext()

    private fun uri(name: String): Uri = Uri.fromFile(
        java.io.File(application.cacheDir, "opened-file-remembered-$name").apply { writeBytes(ByteArray(0)) },
    )

    @Test
    fun `a persistable grant is taken and the file is remembered`() {
        val target = uri("Comics.cbz")
        val intent = Intent(Intent.ACTION_VIEW, target)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)

        OpenedFile.rememberIfPersistable(application, intent, target)

        assertTrue(application.contentResolver.persistedUriPermissions.any { it.uri == target })
        assertEquals(listOf(target), RememberedFiles.open(application).all())
    }

    @Test
    fun `past the limit, the file that falls off gives its grant back`() {
        val targets = (0..RememberedFiles.LIMIT).map { uri("Past-$it.cbz") }

        targets.forEach { target ->
            val intent = Intent(Intent.ACTION_VIEW, target)
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
            OpenedFile.rememberIfPersistable(application, intent, target)
        }

        val held = application.contentResolver.persistedUriPermissions.map { it.uri }
        assertTrue(targets.first() !in held)
        assertTrue(targets.drop(1).all { it in held })
    }

    @Test
    fun `no persistable grant offered, nothing is taken or remembered`() {
        val target = uri("Manga.cbz")
        val intent = Intent(Intent.ACTION_VIEW, target).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)

        OpenedFile.rememberIfPersistable(application, intent, target)

        assertTrue(application.contentResolver.persistedUriPermissions.none { it.uri == target })
        assertTrue(RememberedFiles.open(application).all().none { it == target })
    }
}
