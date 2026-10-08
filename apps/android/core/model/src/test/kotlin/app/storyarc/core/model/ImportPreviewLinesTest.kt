package app.storyarc.core.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * `library-portability` tasks 2.3, 3.3 and 6.8: what the import preview tells the reader.
 *
 * The screen is a loop over [previewLines], so what the reader is told is what this list holds.
 * iOS's `LibraryImportPreviewTests` asserts the same rows.
 */
class ImportPreviewLinesTest {

    private val document = LibraryExport.document(
        LibraryDocumentFixture.snapshot,
        LibraryDocumentFixture.APP_VERSION,
        LibraryDocumentFixture.WRITTEN_AT,
    )

    /**
     * A used device: the folder, the collection with one of its two members, a position of its
     * own, and no pin and no cover.
     */
    private val device = LibrarySnapshot(
        sources = SourceRegistry(
            sources = listOf(
                Source(
                    id = LibraryDocumentFixture.folderId,
                    displayName = "Shelf",
                    kind = SourceKind.LOCAL_FOLDER,
                    locator = "/Books/Shelf",
                ),
            ),
        ),
        shelves = Shelves(
            collections = listOf(
                PublicationCollection(
                    id = LibraryDocumentFixture.collectionId,
                    name = "Image Comics",
                    members = setOf("path:/a.cbz"),
                ),
            ),
        ),
        progress = listOf(
            ReadingProgress(
                identity = PublicationIdentity(contentDigest = "d1", normalizedPath = "/a.cbz"),
                position = ReadingPosition.Page(30, 40),
                updatedAtEpochMillis = 1_767_200_000_000L,
            ),
        ),
    )

    private val pin = CertificatePinNotice("nas.local", "Comics NAS")

    @Test
    fun `every change is a line, and the change to what the app trusts comes first`() {
        val lines = LibraryImport.plan(document, device).previewLines()

        assertEquals(
            listOf(
                ImportPreviewLine.CertificatePins(listOf(pin)),
                ImportPreviewLine.SourcesToAdd(listOf("Comics NAS", "Kavita")),
                ImportPreviewLine.SourcesNeedingSignIn(listOf("Comics NAS", "Kavita")),
                ImportPreviewLine.ShelvesToAdd(listOf("Crossover")),
                ImportPreviewLine.ShelvesMerged(listOf(ImportedShelf("Image Comics", 1))),
                ImportPreviewLine.Progress(add = 2, merge = 1),
                ImportPreviewLine.Themes(2),
                ImportPreviewLine.Covers(1),
                ImportPreviewLine.SettingsChange,
            ),
            lines,
        )
    }

    @Test
    fun `the pin line names the host and the source it arrived with`() {
        val pins = LibraryImport.plan(document, device).previewLines()
            .filterIsInstance<ImportPreviewLine.CertificatePins>()

        assertEquals(listOf(ImportPreviewLine.CertificatePins(listOf(pin))), pins)
    }

    @Test
    fun `a pin the device already holds is not a line`() {
        val pinned = device.copy(certificatePins = mapOf("nas.local" to setOf("AB:CD:EF:01")))

        val lines = LibraryImport.plan(document, pinned).previewLines()

        assertFalse(lines.any { it is ImportPreviewLine.CertificatePins })
    }

    @Test
    fun `the merge line states how many members each shelf gains`() {
        val lines = LibraryImport.plan(document, device).previewLines()

        assertTrue(
            lines.contains(ImportPreviewLine.ShelvesMerged(listOf(ImportedShelf("Image Comics", 1)))),
        )
    }

    @Test
    fun `a plan with nothing in it says so instead of showing an empty list`() {
        assertEquals(listOf(ImportPreviewLine.NothingNew), LibraryImportPlan().previewLines())
    }

    @Test
    fun `a count of zero is not a line`() {
        val plan = LibraryImportPlan(progressToAdd = 0, progressToMerge = 3, themeEntriesToAdd = 0)

        assertEquals(listOf(ImportPreviewLine.Progress(add = 0, merge = 3)), plan.previewLines())
    }
}
