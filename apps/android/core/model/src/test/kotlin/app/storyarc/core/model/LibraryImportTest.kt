package app.storyarc.core.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.UUID

/**
 * `library-portability` / *Import merges*, row by row.
 *
 * iOS's `LibraryImportTests` asserts the same rows against the same library, so neither
 * platform can privately decide what a merge means.
 */
class LibraryImportTest {

    private val document = LibraryExport.document(
        LibraryDocumentFixture.snapshot,
        LibraryDocumentFixture.APP_VERSION,
        LibraryDocumentFixture.WRITTEN_AT,
    )

    /**
     * A device that has been used: one of the three sources already, the collection with one
     * of its two members, and this device's own reading further on than the document's.
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
            // Never synchronised with anything, which is the case task 1.4 fixed and the case
            // every new phone is in.
            ReadingProgress(
                identity = PublicationIdentity(contentDigest = "d1", normalizedPath = "/a.cbz"),
                position = ReadingPosition.Page(30, 40),
                updatedAtEpochMillis = 1_767_200_000_000L,
            ),
        ),
    )

    // The preview.

    @Test
    fun `the plan states what will be added, what will be merged and what needs a sign-in`() {
        val plan = LibraryImport.plan(document, device)

        assertEquals(listOf("Comics NAS", "Kavita"), plan.sourcesToAdd)
        assertEquals(listOf("Comics NAS", "Kavita"), plan.sourcesNeedingSignIn)
        assertEquals(listOf("Crossover"), plan.shelvesToAdd)
        assertEquals(listOf(ImportedShelf("Image Comics", 1)), plan.shelvesToMerge)
        assertEquals(2, plan.progressToAdd)
        assertEquals(1, plan.progressToMerge)
        assertTrue(plan.settingsWillChange)
        assertEquals(2, plan.themeEntriesToAdd)
    }

    @Test
    fun `planning changes nothing on the device`() {
        val before = device.copy()
        LibraryImport.plan(document, before)

        assertEquals(device, before)
    }

    // Sources.

    @Test
    fun `an imported source arrives without a secret and is listed as needing one`() {
        val merged = LibraryImport.merging(document, device).snapshot
        val arrived = merged.sources.sources
            .firstOrNull { it.id == LibraryDocumentFixture.networkShareId }

        assertEquals("Comics NAS", arrived?.displayName)
        // `sources` keeps the library browsable while a source is unreachable, so the source
        // is listed with no secret rather than withheld until one is supplied.
        assertNull(arrived?.credentialReference)
        assertEquals("smb://reader@nas.local/comics", arrived?.locator)
    }

    @Test
    fun `a document an iPhone wrote names this device's own sources, in upper case`() {
        // Swift renders a `UUID` in upper case and Java renders one in lower case, so every
        // identifier in a document an iPhone wrote arrives in the spelling this device never
        // writes. Compared as text, each source, collection and list reads as a new one.
        //
        // The committed fixtures cannot catch this: every identifier in them is digits, which
        // spells the same in both cases. This builds the same document with the same
        // identifiers in the case Swift writes.
        val fromIphone = upperCased(document)
        val holder = holdingLettered(device)

        val plan = LibraryImport.plan(fromIphone, holder)

        assertTrue(
            "A source this device holds was planned as an arrival: " + plan.sourcesToAdd,
            plan.sourcesToAdd.none { it == "Shelf" },
        )
        assertTrue(
            "A collection this device holds was planned as an arrival: " + plan.shelvesToAdd,
            plan.shelvesToAdd.none { it == "Image Comics" },
        )
        assertEquals(
            holder.sources.sources.size + 2,
            LibraryImport.merging(fromIphone, holder).snapshot.sources.sources.size,
        )
    }

    /**
     * The same document, with the two identifiers this device also holds spelled the way
     * Swift spells one.
     *
     * The identifiers are re-made with hex letters in them first. Every identifier in
     * `LibraryDocumentFixture` is digits, and a digit spells the same in either case, so
     * upper-casing the fixture's own identifiers changes nothing and proves nothing.
     */
    private fun upperCased(document: LibraryDocument): LibraryDocument {
        val library = document.library
        return document.copy(
            library = library.copy(
                sources = library.sources.map {
                    if (it.id == LibraryDocumentFixture.folderId.toString()) {
                        it.copy(id = LETTERED_FOLDER.toString().uppercase())
                    } else {
                        it
                    }
                },
                collections = library.collections.map {
                    if (it.id == LibraryDocumentFixture.collectionId.toString()) {
                        it.copy(id = LETTERED_COLLECTION.toString().uppercase())
                    } else {
                        it
                    }
                },
            ),
        )
    }

    /** The same device, holding those two under the same identifiers. */
    private fun holdingLettered(device: LibrarySnapshot): LibrarySnapshot = device.copy(
        sources = SourceRegistry(
            sources = device.sources.sources.map {
                if (it.id == LibraryDocumentFixture.folderId) it.copy(id = LETTERED_FOLDER) else it
            },
        ),
        shelves = device.shelves.copy(
            collections = device.shelves.collections.map {
                if (it.id == LibraryDocumentFixture.collectionId) {
                    it.copy(id = LETTERED_COLLECTION)
                } else {
                    it
                }
            },
        ),
    )

    private companion object {
        val LETTERED_FOLDER: UUID = UUID.fromString("aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")
        val LETTERED_COLLECTION: UUID = UUID.fromString("ffffffff-aaaa-bbbb-cccc-dddddddddddd")
    }

    @Test
    fun `a setting the writing platform cannot express is kept, not turned off`() {
        // iOS has no volume-button page turn, so a document an iPhone writes carries no such
        // field. Decoding that absence as `false` does not ignore the field, it turns the
        // setting off — and the reader is never told. They would find the buttons dead.
        val fromIphone = document.copy(
            library = document.library.copy(
                settings = document.library.settings.copy(turnPagesWithVolumeButtons = null),
            ),
        )
        val holder = device.copy(settings = AppSettings(turnPagesWithVolumeButtons = true))

        val merged = LibraryImport.merging(fromIphone, holder).snapshot

        assertTrue(
            "An import from a platform without this setting turned it off.",
            merged.settings.turnPagesWithVolumeButtons,
        )
    }

    @Test
    fun `a setting the document does carry still wins`() {
        val off = document.copy(
            library = document.library.copy(
                settings = document.library.settings.copy(turnPagesWithVolumeButtons = false),
            ),
        )
        val holder = device.copy(settings = AppSettings(turnPagesWithVolumeButtons = true))

        assertEquals(
            false,
            LibraryImport.merging(off, holder).snapshot.settings.turnPagesWithVolumeButtons,
        )
    }

    @Test
    fun `a pin notice names the host's own source, not one whose address merely contains it`() {
        // `nas.local` is a substring of `evil-nas.local`. A notice that asks the reader to
        // accept a fingerprint must not put a trusted name next to a stranger's.
        val lookalike = document.copy(
            library = document.library.copy(
                sources = listOf(
                    DocumentSource(
                        id = UUID.randomUUID().toString(),
                        displayName = "Not my NAS",
                        kind = SourceKind.NETWORK_SHARE.name.toWireCase(),
                        locator = "smb://evil-nas.local/comics",
                    ),
                ) + document.library.sources,
            ),
        )

        val named = LibraryImport.plan(lookalike, device).certificatePinsToAdd
            .firstOrNull { it.host == "nas.local" }

        assertEquals("Comics NAS", named?.sourceName)
    }

    @Test
    fun `a source the device already has is left exactly as it was`() {
        val merged = LibraryImport.merging(document, device).snapshot

        assertEquals(
            device.sources.sources.first(),
            merged.sources.sources.firstOrNull { it.id == LibraryDocumentFixture.folderId },
        )
    }

    @Test
    fun `a source this device is already signed in to is not listed as needing a sign-in`() {
        val signedIn = device.copy(
            sources = device.sources.adding(
                Source(
                    id = LibraryDocumentFixture.networkShareId,
                    displayName = "Comics NAS",
                    kind = SourceKind.NETWORK_SHARE,
                    credentialReference = "keystore:already-here",
                ),
            ),
        )

        assertEquals(listOf("Kavita"), LibraryImport.plan(document, signedIn).sourcesNeedingSignIn)
    }

    // Certificate pins.

    @Test
    fun `a pin is named with the source it arrived with rather than applied silently`() {
        assertEquals(
            listOf(CertificatePinNotice("nas.local", "Comics NAS")),
            LibraryImport.plan(document, device).certificatePinsToAdd,
        )
    }

    @Test
    fun `a pin the device already holds is not announced again`() {
        val pinned = device.copy(certificatePins = mapOf("nas.local" to setOf("AB:CD:EF:01")))

        assertTrue(LibraryImport.plan(document, pinned).certificatePinsToAdd.isEmpty())
    }

    @Test
    fun `pins merge rather than replace, so a pin accepted here survives the import`() {
        val pinned = device.copy(certificatePins = mapOf("nas.local" to setOf("99:88")))

        val merged = LibraryImport.merging(document, pinned).snapshot

        assertEquals(setOf("99:88", "AB:CD:EF:01"), merged.certificatePins["nas.local"])
    }

    // Shelves.

    @Test
    fun `a collection on both sides merges its members and keeps the device's cover choice`() {
        val merged = LibraryImport.merging(document, device).snapshot
        val collection = merged.shelves.collections
            .firstOrNull { it.id == LibraryDocumentFixture.collectionId }

        assertEquals(setOf("path:/a.cbz", "path:/b.cbz"), collection?.members)
        // The device had chosen no cover, so the document's choice fills the gap.
        assertEquals("path:/b.cbz", collection?.coverMemberId)
    }

    @Test
    fun `a reading list the device does not have arrives whole, in its own order`() {
        val merged = LibraryImport.merging(document, device).snapshot

        assertEquals(listOf("path:/b.cbz", "path:/a.cbz"), merged.shelves.lists.first().entries)
    }

    @Test
    fun `a pin on a shelf survives alongside the device's own pins`() {
        val merged = LibraryImport.merging(document, device).snapshot

        assertEquals(
            LibraryDocumentFixture.snapshot.pinnedShelves.tokens.toSet(),
            merged.pinnedShelves.tokens.toSet(),
        )
    }

    // Reading progress.

    @Test
    fun `on a device that never synced, the furthest position wins and nothing is flagged`() {
        val result = LibraryImport.merging(document, device)
        val record = result.snapshot.progress
            .firstOrNull { it.identity.matches(PublicationIdentity(contentDigest = "d1")) }

        // The device read to page 30 and the document stopped at 12. Without task 1.4 this
        // took the conflict branch and told the reader about a disagreement that was not one.
        assertEquals(ReadingPosition.Page(30, 40), record?.position)
        assertTrue(result.conflicts.isEmpty())
    }

    @Test
    fun `a document further on than the device wins, on a device that never synced`() {
        val behind = device.copy(
            progress = listOf(
                ReadingProgress(
                    identity = PublicationIdentity(contentDigest = "d1", normalizedPath = "/a.cbz"),
                    position = ReadingPosition.Page(2, 40),
                    updatedAtEpochMillis = 1_767_200_000_000L,
                ),
            ),
        )

        val result = LibraryImport.merging(document, behind)
        val record = result.snapshot.progress
            .firstOrNull { it.identity.matches(PublicationIdentity(contentDigest = "d1")) }

        assertEquals(ReadingPosition.Page(12, 40), record?.position)
        assertTrue(result.conflicts.isEmpty())
    }

    @Test
    fun `finished stays finished`() {
        val merged = LibraryImport.merging(document, device).snapshot
        val record = merged.progress
            .firstOrNull { it.identity.matches(PublicationIdentity(contentDigest = "d2")) }

        assertEquals(true, record?.isFinished)
    }

    @Test
    fun `a position the device does not hold at all arrives`() {
        assertEquals(3, LibraryImport.merging(document, device).snapshot.progress.size)
    }

    @Test
    fun `an imported record carries no watermark, because the document carries none`() {
        val merged = LibraryImport.merging(document, device).snapshot
        val record = merged.progress
            .firstOrNull { it.identity.matches(PublicationIdentity(contentDigest = "d2")) }

        // A watermark says what *this* device last exchanged with a server. Carrying one in
        // would tell the device it had synchronised when it never had.
        assertNull(record?.syncedPosition)
    }

    @Test
    fun `both sides moved since a real watermark, so the reader is told once`() {
        val synced = device.copy(
            progress = listOf(
                ReadingProgress(
                    identity = PublicationIdentity(contentDigest = "d1", normalizedPath = "/a.cbz"),
                    position = ReadingPosition.Page(30, 40),
                    updatedAtEpochMillis = 1_767_200_000_000L,
                    syncedPosition = ReadingPosition.Page(1, 40),
                ),
            ),
        )

        val result = LibraryImport.merging(document, synced)

        assertEquals(1, result.conflicts.size)
        assertEquals(ReadingPosition.Page(30, 40), result.conflicts.first().resolved.position)
        assertEquals(ReadingPosition.Page(12, 40), result.conflicts.first().discarded)
    }

    // Themes.

    @Test
    fun `a theme the device has chosen stands and one it has never chosen arrives`() {
        val themed = device.copy(
            themes = ShelfMemory().settingDefault(
                ShelfSettings(theme = ReadingTheme(preset = ThemePreset.BOLD)),
                ThemeScope.REFLOWABLE,
            ),
        )

        val merged = LibraryImport.merging(document, themed).snapshot

        assertEquals(ThemePreset.BOLD, merged.themes.default(ThemeScope.REFLOWABLE).theme.preset)
        assertTrue(merged.themes.remembers(ThemeScope.FIXED_LAYOUT, "Bone"))
        assertEquals(PageFit.WIDTH, merged.themes.theme(ThemeScope.FIXED_LAYOUT, "Bone").fit)
    }

    @Test
    fun `the reader's own palette survives an import that carries another`() {
        val themed = device.copy(
            themes = ShelfMemory().copy(
                customPalette = ReaderPalette("Mine", "#FFFFFF", "#000000"),
            ),
        )

        val merged = LibraryImport.merging(document, themed).snapshot

        assertEquals("Mine", merged.themes.customPalette?.name)
    }
}
