package app.storyarc.core.format

import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assume
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.nio.file.FileSystemException
import java.nio.file.Files

/**
 * A plain folder has no container to parse, so its fixtures are built in a
 * temporary directory rather than committed — there would be nothing to pin. What
 * is asserted is that a folder behaves exactly like an archive: same page filter,
 * same natural sort, same skipped count. iOS's `ImageFolderArchiveTests` asserts
 * the same list.
 */
class ImageFolderArchiveTest {
    @get:Rule
    val temp = TemporaryFolder()

    /** A 2x3 PNG, the same shape every committed fixture page uses. */
    private val png = byteArrayOf(
        0x89.toByte(), 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
        0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
        0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00, 0x03,
        0x08, 0x02, 0x00, 0x00, 0x00, 0x8D.toByte(), 0x6F, 0x26,
        0xD5.toByte(), 0x00, 0x00, 0x00, 0x0C, 0x49, 0x44, 0x41,
        0x54, 0x08, 0xD7.toByte(), 0x63, 0xF8.toByte(), 0xCF.toByte(), 0xC0.toByte(), 0x00,
        0x00, 0x03, 0x01, 0x01, 0x00, 0x18, 0xDD.toByte(), 0x8D.toByte(),
        0xB0.toByte(), 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E,
        0x44, 0xAE.toByte(), 0x42, 0x60, 0x82.toByte(),
    )

    private fun folder(files: Map<String, ByteArray>): File {
        val root = temp.newFolder()
        for ((path, bytes) in files) {
            val file = File(root, path)
            file.parentFile?.mkdirs()
            file.writeBytes(bytes)
        }
        return root
    }

    @Test
    fun `pages sort naturally, so page10 follows page9`() {
        val root = folder((1..12).associate { "page$it.png" to png })
        val archive = ImageFolderArchive.open(root)
        assertEquals((1..12).map { "page$it.png" }, archive.pages.map { it.path })
    }

    @Test
    fun `chapter subdirectories order by full path, so ch10 follows ch2`() {
        val root = folder(
            mapOf(
                "ch1/p1.png" to png, "ch1/p2.png" to png, "ch1/p10.png" to png,
                "ch2/p1.png" to png, "ch10/p1.png" to png,
            ),
        )
        val archive = ImageFolderArchive.open(root)
        assertEquals(
            listOf("ch1/p1.png", "ch1/p2.png", "ch1/p10.png", "ch2/p1.png", "ch10/p1.png"),
            archive.pages.map { it.path },
        )
    }

    @Test
    fun `non-image files are excluded and ComicInfo xml is picked up`() {
        val comicInfo = "<ComicInfo><Series>Folder</Series></ComicInfo>".toByteArray()
        val root = folder(
            mapOf(
                "page1.png" to png,
                "ComicInfo.xml" to comicInfo,
                "notes.txt" to "not a page".toByteArray(),
                "Thumbs.db" to ByteArray(4),
                "__MACOSX/._page1.png" to "resource fork".toByteArray(),
            ),
        )
        val archive = ImageFolderArchive.open(root)
        assertEquals(listOf("page1.png"), archive.pages.map { it.path })
        assertArrayEquals(comicInfo, archive.comicInfoData)
    }

    @Test
    fun `a zero-length image counts as skipped rather than as a page`() {
        val root = folder(mapOf("page1.png" to png, "page2.png" to ByteArray(0)))
        val archive = ImageFolderArchive.open(root)
        assertEquals(listOf("page1.png"), archive.pages.map { it.path })
        assertEquals(1, archive.skippedPageCount)
    }

    @Test
    fun `a page's bytes come back verbatim`() = runTest {
        val root = folder(mapOf("page1.png" to png))
        val archive = ImageFolderArchive.open(root)
        assertArrayEquals(png, archive.data(archive.pages.first()))
    }

    @Test
    fun `a folder opens through the same opener as a file`() = runTest {
        val root = folder(mapOf("page1.png" to png, "page2.png" to png))
        val archive = ComicArchiveOpener.open(root)
        assertEquals(2, archive.pages.size)
        assertTrue(archive is ImageFolderArchive)
    }

    @Test
    fun `an empty folder reports zero pages rather than failing`() {
        val archive = ImageFolderArchive.open(temp.newFolder())
        assertTrue(archive.pages.isEmpty())
        assertEquals(0, archive.skippedPageCount)
    }

    @Test
    fun `a path that is not a directory is refused`() {
        val root = folder(mapOf("page1.png" to png))
        val failure = runCatching { ImageFolderArchive.open(File(root, "page1.png")) }
            .exceptionOrNull()
        assertTrue(
            "expected UnrecognisedContainer, got $failure",
            failure is ComicArchiveException.UnrecognisedContainer,
        )
    }

    @Test
    fun `a symlink is not followed, so a folder cannot reach outside itself`() {
        val secret = temp.newFile("secret.png")
        secret.writeBytes(png)
        val root = folder(mapOf("page1.png" to png))
        try {
            Files.createSymbolicLink(File(root, "page2.png").toPath(), secret.toPath())
        } catch (denied: FileSystemException) {
            // Windows grants symlink creation only to Developer Mode or an elevated
            // process. A test that cannot create its own fixture proves nothing
            // either way, so it skips rather than fails on such a machine.
            Assume.assumeNoException(denied)
        }

        val archive = ImageFolderArchive.open(root)
        // The link would otherwise read a file outside the publication. A folder
        // is chosen by the user, but it is still untrusted input.
        assertEquals(listOf("page1.png"), archive.pages.map { it.path })
    }
}
