package app.storyarc

import android.app.Application
import android.net.Uri
import androidx.test.core.app.ApplicationProvider
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.io.File

/**
 * What [OpenedFile.index] says about a handed-over file, by outcome.
 *
 * `publication-formats` requires a password-protected archive and a damaged one to carry
 * their own, distinct refusals -- and a publication whose streaming is REFUSED (a solid
 * RAR4) to be refused *before* the reader opens it, because Open-in has no library row to
 * list it in and say why. iOS's `RefusedFileWordingTests` pins the wording side of the same
 * three outcomes; this pins the mapping itself, which a text tripwire cannot reach because
 * this module has a real JVM test target.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class OpenedFileOutcomeTest {

    private val application: Application get() = ApplicationProvider.getApplicationContext()

    /** Finds the shared fixture corpus the same way `core:format`'s `FixtureCorpus` does. */
    private fun corpusFile(relative: String): File {
        var dir: File? = File("").absoluteFile
        while (dir != null) {
            val candidate = File(dir, "packages/test-fixtures/$relative")
            if (candidate.isFile) return candidate
            dir = dir.parentFile
        }
        error("fixture corpus not found above ${File("").absolutePath} -- expected packages/test-fixtures")
    }

    /** A content `Uri` over a copy of `relative`'s bytes, named `name`. */
    private fun uriCopying(relative: String, name: String): Uri {
        val target = File(application.cacheDir, "opened-file-outcome-$name")
        corpusFile(relative).copyTo(target, overwrite = true)
        return Uri.fromFile(target)
    }

    @Test
    fun `a password-protected archive is its own outcome, naming the file`() = runTest {
        val uri = uriCopying("comics/password-protected.cbz", "Password.cbz")

        val outcome = OpenedFile.index(application, uri)

        assertTrue("expected PasswordProtected, got $outcome", outcome is OpenedFile.Outcome.PasswordProtected)
        assertTrue((outcome as OpenedFile.Outcome.PasswordProtected).name.isNotEmpty())
    }

    @Test
    fun `a solid RAR4 is refused before the reader opens it, not opened`() = runTest {
        // The indexer returns an *opened* record for this one -- streaming REFUSED, not a
        // thrown IndexException -- which is exactly the gap `publication-formats` names:
        // Open-in has no library row to show it in, so the outcome has to name it here.
        val uri = uriCopying("comics/rar4-solid.cbr", "Solid.cbr")

        val outcome = OpenedFile.index(application, uri)

        assertTrue("expected SolidArchive, got $outcome", outcome is OpenedFile.Outcome.SolidArchive)
    }

    @Test
    fun `a damaged archive is its own outcome, not the unsupported one`() = runTest {
        // A RAR signature with nothing readable behind it: the container is recognised and
        // the file is too broken to open, which is a different claim from "not a format
        // StoryArc reads" and owes a sentence that names neither a format nor a conversion.
        val target = File(application.cacheDir, "opened-file-outcome-Damaged.cbr")
        target.writeBytes(byteArrayOf(0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x00, 0x00))
        val uri = Uri.fromFile(target)

        val outcome = OpenedFile.index(application, uri)

        assertTrue("expected Damaged, got $outcome", outcome is OpenedFile.Outcome.Damaged)
    }

    @Test
    fun `a readable comic still opens, outcomes do not foreclose the happy path`() = runTest {
        val uri = uriCopying("comics/natural-sort.cbz", "Readable.cbz")

        val outcome = OpenedFile.index(application, uri)

        assertTrue("expected Opened, got $outcome", outcome is OpenedFile.Outcome.Opened)
    }
}
