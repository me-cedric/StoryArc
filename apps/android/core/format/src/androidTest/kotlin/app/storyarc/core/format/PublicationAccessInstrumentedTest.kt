package app.storyarc.core.format

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

/**
 * [PublicationAccess.anyCover] routed a registered remote scheme nowhere: [openArchive]
 * already checked the registry first, and `anyCover` fell straight to `File(path)` for
 * anything that was not a `content://` document -- which a share's `smb://` row always
 * was. A cover for a row nobody had downloaded was a path to nothing on the device, and
 * [CoverLoader] decoded no bytes from it.
 *
 * This asserts the fix at the one seam that matters: a path the registry owns reaches the
 * opener, not the filesystem.
 */
@RunWith(AndroidJUnit4::class)
class PublicationAccessInstrumentedTest {

    private fun fixture(name: String): File {
        val context = InstrumentationRegistry.getInstrumentation().context
        val target = File(context.cacheDir, name.substringAfterLast('/'))
        if (!target.exists()) {
            context.assets.open(name).use { input ->
                target.outputStream().use(input::copyTo)
            }
        }
        return target
    }

    @Test
    fun aCoverForARegisteredRemoteSchemeComesFromItsOpenerNotTheFilesystem() = runBlocking {
        val file = fixture("comics/natural-sort.cbz")
        val publication = PublicationIndexer.index(file)
        val resolver = InstrumentationRegistry.getInstrumentation().targetContext.contentResolver

        PublicationAccess.register("storyarc-test") { FileSource(file) }

        val fromRegistry = PublicationAccess.anyCover(
            resolver,
            publication,
            "storyarc-test://nas.local/Comics/natural-sort.cbz",
            200,
        )
        val fromFile = CoverLoader.anyCover(publication, file, 200)

        assertEquals(fromFile.width, fromRegistry.width)
        assertEquals(fromFile.height, fromRegistry.height)
    }
}
