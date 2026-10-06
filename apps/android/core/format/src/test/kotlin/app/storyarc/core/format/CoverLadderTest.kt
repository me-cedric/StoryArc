package app.storyarc.core.format

import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import java.io.File
import kotlin.io.path.createTempDirectory
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The ladder, rung by rung, and the key a chosen cover is filed under.
 *
 * `cover-art`'s *The cover ladder* orders the sources cheapest first and requires that the
 * first one to answer wins. What is asserted here is which rung answers and what it answers
 * with, which is the whole of the rule; decoding a `Bitmap` needs a device, and
 * `CoverLoaderInstrumentedTest` is where that already happens. iOS's `CoverLadderTests.swift`
 * is the twin of this file, case for case.
 */
class CoverLadderTest {

    // --------------------------------------------------------- Rung 2, a loose image beside

    @Test
    fun `a cover image beside the file is the one the ladder reaches for`() {
        val folder = temporaryFolder()
        val book = File(folder, "Book 03.m4b").apply { writeBytes(byteArrayOf(1, 2, 3)) }
        File(folder, "cover.jpg").writeBytes(byteArrayOf(9))

        val ladder = CoverLadder(CoverOverrideStore(File(folder, "overrides")))

        assertEquals("cover.jpg", ladder.coverFile(audiobook(book), book.path)?.name)
    }

    @Test
    fun `a poster image counts, and a cover image is preferred to it`() {
        val folder = temporaryFolder()
        File(folder, "poster.png").writeBytes(byteArrayOf(1))
        assertEquals("poster.png", LooseCover.inFolder(folder)?.name)

        File(folder, "cover.png").writeBytes(byteArrayOf(1))
        assertEquals("cover.png", LooseCover.inFolder(folder)?.name)
    }

    @Test
    fun `a folder with no loose image answers nothing`() {
        val folder = temporaryFolder()
        File(folder, "notes.txt").writeText("x")
        assertNull(LooseCover.inFolder(folder))
    }

    @Test
    fun `a loose cover is found beside a file and inside a folder alike`() {
        val folder = temporaryFolder()
        val book = File(folder, "Book 03.m4b").apply { writeBytes(byteArrayOf(1)) }
        File(folder, "folder.jpeg").writeBytes(byteArrayOf(1))

        assertEquals("folder.jpeg", LooseCover.beside(book)?.name)
        assertEquals("folder.jpeg", LooseCover.beside(folder)?.name)
    }

    @Test
    fun `a Storage Access Framework listing names its own loose cover`() {
        val listed = listOf("01 - Chapter.mp3", "Poster.PNG", "notes.txt")
        assertEquals("Poster.PNG", LooseCover.named(listed))
        assertNull(LooseCover.named(listOf("01 - Chapter.mp3", "notes.txt")))
    }

    // ---------------------------------------------------- Rung 1, the reader's own picture

    @Test
    fun `a chosen cover is reached before the one beside the file`() {
        val folder = temporaryFolder()
        val book = File(folder, "Book 03.m4b").apply { writeBytes(byteArrayOf(1)) }
        File(folder, "cover.jpg").writeBytes(byteArrayOf(9))

        val overrides = CoverOverrideStore(File(folder, "overrides"))
        val publication = audiobook(book)
        val chosen = overrides.store(byteArrayOf(7), publication)
        assertNotNull(chosen)

        assertEquals(
            chosen?.path,
            CoverLadder(overrides).coverFile(publication, book.path)?.path,
        )
    }

    @Test
    fun `removing a chosen cover falls back to the rung below, and deletes the image`() {
        val folder = temporaryFolder()
        val book = File(folder, "Book 03.m4b").apply { writeBytes(byteArrayOf(1)) }
        File(folder, "cover.jpg").writeBytes(byteArrayOf(9))

        val overrides = CoverOverrideStore(File(folder, "overrides"))
        val publication = audiobook(book)
        val chosen = overrides.store(byteArrayOf(7), publication)
        assertNotNull(chosen)
        overrides.remove(publication)

        assertFalse(chosen!!.isFile)
        assertNull(overrides.file(publication))
        assertEquals(
            "cover.jpg",
            CoverLadder(overrides).coverFile(publication, book.path)?.name,
        )
    }

    @Test
    fun `an audiobook's extracted artwork is reached when nothing is beside it`() {
        val folder = temporaryFolder()
        val book = File(folder, "Book 03.m4b").apply { writeBytes(byteArrayOf(1)) }
        val extracted = File(folder, "extracted").apply { writeBytes(byteArrayOf(5)) }

        val publication = audiobook(book).copy(coverPath = extracted.path)
        val ladder = CoverLadder(CoverOverrideStore(File(folder, "overrides")))

        assertEquals(extracted.path, ladder.coverFile(publication, book.path)?.path)
    }

    @Test
    fun `a comic's cover is an archive entry and has no file of its own`() {
        val folder = temporaryFolder()
        val book = File(folder, "Book 03.cbz").apply { writeBytes(byteArrayOf(1)) }
        val publication = Publication(
            identity = PublicationIdentity(normalizedPath = book.path),
            format = PublicationFormat.CBZ,
            displayTitle = "Book 03",
            origin = MetadataOrigin.INFERRED,
            coverPath = "pages/001.jpg",
        )
        val ladder = CoverLadder(CoverOverrideStore(File(folder, "overrides")))

        assertNull(ladder.coverFile(publication, book.path))
    }

    // ------------------------------------------------- The key the override is filed under

    @Test
    fun `a chosen cover outlives a rename, because the key is the content digest`() {
        val overrides = CoverOverrideStore(File(temporaryFolder(), "overrides"))
        val before = Publication(
            identity = PublicationIdentity(contentDigest = "abc123", normalizedPath = "/a/a.m4b"),
            format = PublicationFormat.M4B,
            displayTitle = "Before",
            origin = MetadataOrigin.INFERRED,
        )
        val after = before.copy(
            identity = PublicationIdentity(
                contentDigest = "abc123",
                normalizedPath = "/somewhere/else/b.m4b",
            ),
        )

        overrides.store(byteArrayOf(7), before)

        assertNotNull(overrides.file(after))
        assertEquals(CoverOverrideStore.Key.CONTENT_DIGEST, overrides.keyKind(after))
    }

    @Test
    fun `a publication with no digest is filed under its stable identifier, and says so`() {
        val overrides = CoverOverrideStore(File(temporaryFolder(), "overrides"))
        val here = Publication(
            identity = PublicationIdentity(normalizedPath = "/pictures/Book"),
            format = PublicationFormat.IMAGE_FOLDER,
            displayTitle = "Folder",
            origin = MetadataOrigin.INFERRED,
        )
        val moved = here.copy(
            identity = PublicationIdentity(normalizedPath = "/elsewhere/Book"),
        )

        overrides.store(byteArrayOf(7), here)

        assertEquals(CoverOverrideStore.Key.STABLE_IDENTIFIER, overrides.keyKind(here))
        assertNotNull(overrides.file(here))
        assertNull(overrides.file(moved))
    }

    // ------------------------------------------- The shape a chosen picture is stored in

    @Test
    fun `a square photograph is cropped to the cover shape`() {
        // Cut down, never stretched out: a square loses its sides rather than growing a
        // third of its height out of nothing.
        val crop = CoverArtwork.crop(400, 400)

        assertEquals(267, crop.width)
        assertEquals(400, crop.height)
        assertEquals(66, crop.x)
        assertEquals(0, crop.y)
    }

    @Test
    fun `a wide photograph is cropped from the middle`() {
        val crop = CoverArtwork.crop(900, 300)

        assertEquals(200, crop.width)
        assertEquals(300, crop.height)
        assertEquals(350, crop.x)
        assertEquals(0, crop.y)
    }

    @Test
    fun `a picture already the cover shape is left alone`() {
        val crop = CoverArtwork.crop(400, 600)

        assertEquals(400, crop.width)
        assertEquals(600, crop.height)
        assertEquals(0, crop.x)
        assertEquals(0, crop.y)
    }

    // ------------------------------------------------- Task 2.5, outside the cache directory

    @Test
    fun `chosen covers live under the data directory and never under a cache directory`() {
        val data = File("/data/user/0/app.storyarc/files")
        val cache = File("/data/user/0/app.storyarc/cache")

        val directory = CoverOverrideStore.directoryIn(data)

        assertTrue(directory.path.startsWith(data.path))
        assertFalse(directory.path.startsWith(cache.path))
    }

    @Test
    fun `a replacement that fails to write leaves the earlier choice whole`() {
        val folder = temporaryFolder()
        val publication = audiobook(File(folder, "Book 03.m4b"))
        val overrides = CoverOverrideStore(File(folder, "overrides"))
        val first = overrides.store(byteArrayOf(1, 2, 3), publication)!!
        // A directory where the half-written copy goes makes the next write fail.
        File(first.parentFile, "${first.name}.partial").mkdirs()

        assertNull(overrides.store(byteArrayOf(9, 9, 9, 9), publication))
        assertEquals(listOf<Byte>(1, 2, 3), overrides.bytes(publication)?.toList())
    }

    private fun audiobook(file: File) = Publication(
        identity = PublicationIdentity(contentDigest = file.path, normalizedPath = file.path),
        format = PublicationFormat.M4B,
        displayTitle = file.name,
        origin = MetadataOrigin.INFERRED,
    )

    private fun temporaryFolder(): File =
        createTempDirectory("cover-ladder").toFile().also { it.deleteOnExit() }

    @Test
    fun `a picked photograph is decoded at a fraction of its size, never whole`() {
        // A 48-megapixel phone photograph is 8000 by 6000. Decoded whole it is 192 MB of
        // pixels for a cover the page draws at 900.
        assertEquals(4, CoverArtwork.sampleSize(8000, 6000))
        assertTrue(8000 / CoverArtwork.sampleSize(8000, 6000) >= CoverArtwork.MAX_SIDE)
        // A picture already near the cover's size is decoded as it is.
        assertEquals(1, CoverArtwork.sampleSize(1200, 1800))
        assertEquals(1, CoverArtwork.sampleSize(3199, 2000))
    }

    @Test
    fun `every EXIF orientation is turned upright`() {
        // A phone writes a portrait photograph as a landscape bitmap plus this tag. Ignored,
        // the reader's cover is stored lying on its side. Raw tag values, so this reads the
        // EXIF standard rather than the constants it is checking.
        val upright = CoverArtwork.Orientation(0f, mirrored = false)
        assertEquals(upright, CoverArtwork.orientation(1))
        assertEquals(CoverArtwork.Orientation(0f, mirrored = true), CoverArtwork.orientation(2))
        assertEquals(CoverArtwork.Orientation(180f, mirrored = false), CoverArtwork.orientation(3))
        assertEquals(CoverArtwork.Orientation(180f, mirrored = true), CoverArtwork.orientation(4))
        assertEquals(CoverArtwork.Orientation(90f, mirrored = true), CoverArtwork.orientation(5))
        assertEquals(CoverArtwork.Orientation(90f, mirrored = false), CoverArtwork.orientation(6))
        assertEquals(CoverArtwork.Orientation(270f, mirrored = true), CoverArtwork.orientation(7))
        assertEquals(CoverArtwork.Orientation(270f, mirrored = false), CoverArtwork.orientation(8))
        // A tag this code does not know leaves the picture as it is.
        assertEquals(upright, CoverArtwork.orientation(0))
    }

    @Test
    fun `a picture larger than the ceiling is refused before it is decoded`() {
        assertNull(CoverArtwork.coverShaped(ByteArray(CoverArtwork.MAX_BYTES + 1)))
    }

    @Test
    fun `a document's folder is the one before it on its trail from the root`() {
        // `findDocumentPath` names every document from the tree's root down to this one.
        val trail = listOf("primary:Books", "primary:Books/Shelf", "primary:Books/Shelf/Tide.epub")

        assertEquals("primary:Books/Shelf", LooseCover.folderOf(trail))
        // The tree's root has no folder above it inside the tree.
        assertNull(LooseCover.folderOf(listOf("primary:Books")))
        assertNull(LooseCover.folderOf(emptyList()))
    }
}
