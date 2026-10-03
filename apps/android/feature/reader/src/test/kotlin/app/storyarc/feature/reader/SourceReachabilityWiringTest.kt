package app.storyarc.feature.reader

import java.io.File
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * That [ReaderViewModel] actually calls [reportIfUnreachable] from both places an archive can
 * fail to open, not only that the function itself is correct -- [SourceReachabilityReportTest]
 * already covers the function. Read as source, the way `LocalNetworkPermissionWiringTest`
 * reads `SmbConnection`: driving a real `SmbError.HostUnreachable` out of
 * `PublicationAccess.openArchive`/`openPdf` would need a registered remote scheme and a fake
 * server, for a claim that is only ever "this call site is still there".
 */
class SourceReachabilityWiringTest {

    private fun read(path: String): String {
        val module = System.getProperty(MODULE_DIRECTORY)?.let(::File)
            ?: error("$MODULE_DIRECTORY is unset. Run this test through Gradle.")
        val file = File(module, path)
        if (!file.isFile) error("$path is not under ${module.absolutePath} — has it moved?")
        return file.readText()
    }

    @Test
    fun `both open paths report a network failure, not only the generic one`() {
        val source = read("src/main/kotlin/app/storyarc/feature/reader/ReaderViewModel.kt")
        val calls = Regex("reportIfUnreachable\\(cause\\)").findAll(source).count()
        assertTrue(
            "ReaderViewModel.kt calls reportIfUnreachable(cause) $calls time(s); expected 2" +
                " (the archive open catch and the PDF open catch).",
            calls == 2,
        )
    }

    private companion object {
        /** Set by this module's `build.gradle.kts`, from its own `projectDir`. */
        const val MODULE_DIRECTORY = "storyarc.reader.projectDir"
    }
}
