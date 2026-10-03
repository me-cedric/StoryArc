package app.storyarc.feature.reader

import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import java.io.File
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

/**
 * What the reader says when an archive reaches it and will not open, driven through
 * [ReaderViewModel.open] with real fixture bytes.
 *
 * `publication-formats` names each typed refusal. The reader used to show one generic
 * sentence for all of them, because a file that no index checked first meets these errors
 * here. `ReaderFailureSaysNothingInternalTest` guards the other half: every sentence is a
 * string resource and no exception text reaches the screen. iOS's `ReaderModelFailureTests`
 * makes the same claims.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class ReaderViewModelFailureTest {

    private fun fixture(name: String): File {
        val module = System.getProperty(MODULE_DIRECTORY)?.let(::File)
            ?: error("$MODULE_DIRECTORY is unset. Run this test through Gradle.")
        val file = File(module, "$CORPUS/$name").canonicalFile
        if (!file.isFile) error("$name is not under ${module.absolutePath}/$CORPUS -- has it moved?")
        return file
    }

    private fun failureOpening(file: File, format: PublicationFormat): ReaderFailure? = runBlocking {
        val model = ReaderViewModel(
            publication = Publication(
                identity = PublicationIdentity(normalizedPath = file.absolutePath),
                format = format,
                displayTitle = file.name,
                origin = MetadataOrigin.INFERRED,
            ),
            resolver = RuntimeEnvironment.getApplication().contentResolver,
            path = file.absolutePath,
        )
        model.open(256)
        model.failure.value
    }

    @Test
    fun `a password-protected archive is named as protected`() {
        assertEquals(
            ReaderFailure(R.string.reader_password_protected),
            failureOpening(fixture("password-protected.cbz"), PublicationFormat.CBZ),
        )
    }

    @Test
    fun `a solid rar4 is named by its compression`() {
        assertEquals(
            ReaderFailure(R.string.reader_solid_archive),
            failureOpening(fixture("rar4-solid.cbr"), PublicationFormat.CBR),
        )
    }

    @Test
    fun `a cb7 is named as a format StoryArc does not read`() {
        // Open-in names the container it detected, and the reader names it too.
        val failure = failureOpening(fixture("refused.cb7"), PublicationFormat.CB7)
        assertEquals(ReaderFailure(R.string.reader_unsupported, listOf("7-Zip")), failure)
        // "States which formats it does support", per `publication-formats`: a bare "not a
        // format StoryArc reads" is the generic failure that scenario forbids.
        val sentence = RuntimeEnvironment.getApplication()
            .getString(R.string.reader_unsupported, *failure!!.args.toTypedArray())
        assertTrue("reader_unsupported names no format: $sentence", sentence.contains("CBZ"))
        assertTrue("reader_unsupported names no container: $sentence", sentence.contains("7-Zip"))
    }

    @Test
    fun `a damaged archive is named as damaged`() {
        // A RAR signature with nothing readable behind it: the container is recognised and
        // the file is too broken to open.
        val damaged = File.createTempFile("damaged", ".cbr").apply {
            deleteOnExit()
            writeBytes(byteArrayOf(0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x00, 0x00))
        }
        assertEquals(ReaderFailure(R.string.reader_damaged), failureOpening(damaged, PublicationFormat.CBR))
    }

    private companion object {
        /** Set by this module's `build.gradle.kts`, from its own `projectDir`. */
        const val MODULE_DIRECTORY = "storyarc.reader.projectDir"
        const val CORPUS = "../../../../packages/test-fixtures/comics"
    }
}
