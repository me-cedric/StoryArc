package app.storyarc.core.model

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** `library-portability` / *One versioned document*, row by row. */
class LibraryDocumentTest {

    private fun document() = LibraryExport.document(
        LibraryDocumentFixture.snapshot,
        LibraryDocumentFixture.APP_VERSION,
        LibraryDocumentFixture.WRITTEN_AT,
    )

    @Test
    fun `the document declares a version, an app version, a platform and a moment`() {
        val written = document()

        assertEquals(1, written.formatVersion)
        assertEquals("10.14.0", written.appVersion)
        assertEquals("android", written.writtenBy)
        assertEquals("2026-01-01T00:04:05Z", written.writtenAt)
        // Reserved and never filled: see `LibraryDocument.secrets` and design.md.
        assertNull(written.secrets)
    }

    @Test
    fun `this platform still writes the document committed under packages test-fixtures`() {
        // The wire is pinned here rather than inferred from the Kotlin types, because every
        // enum in the body is written through `toWireCase` — so a rename nobody thought of as
        // a wire change would change every file this app has written, and nothing else would
        // notice. iOS reads this exact file.
        assertEquals(
            LibraryDocumentFixture.document("written-by-android.json"),
            LibraryDocumentCoder.encode(document()),
        )
    }

    @Test
    fun `a document this platform wrote reads back as the library that went in`() {
        val written = LibraryDocumentCoder.encode(document())

        assertEquals(document(), LibraryDocumentCoder.decode(written).getOrThrow())
    }

    @Test
    fun `a field this version does not know is ignored and the rest is imported`() {
        val parsed = parse(LibraryDocumentCoder.encode(document()))
        val library = parsed["library"] as JsonObject
        val extended = JsonObject(
            parsed + mapOf(
                "somethingTheNextVersionAdded" to buildJsonObject { put("a", JsonPrimitive(1)) },
                "library" to JsonObject(
                    library + mapOf(
                        "aStoreThisBuildHasNever" to buildJsonArray { add(JsonPrimitive("x")) },
                    ),
                ),
            ),
        )

        val read = LibraryDocumentCoder.decode(extended.toString()).getOrThrow()

        assertEquals(document(), read)
    }

    @Test
    fun `a document written by a platform this build has never heard of still reads and imports`() {
        val parsed = parse(LibraryDocumentCoder.encode(document()))
        val foreign = JsonObject(parsed + ("writtenBy" to JsonPrimitive("windows")))

        val read = LibraryDocumentCoder.decode(foreign.toString()).getOrThrow()
        val landed = LibraryImport.merging(read, LibrarySnapshot()).snapshot

        assertEquals("windows", read.writtenBy)
        assertEquals(LibraryDocumentFixture.snapshot.sources.sources.size, landed.sources.sources.size)
    }

    @Test
    fun `a document over the size limit is refused by name and one at the limit reads`() {
        val text = LibraryDocumentCoder.encode(document())
        val size = text.toByteArray().size.toLong()

        assertEquals(
            LibraryDocumentFailure.TooLarge(size, size - 1),
            refusal(LibraryDocumentCoder.decode(text, limit = size - 1)),
        )
        assertEquals(document(), LibraryDocumentCoder.decode(text, limit = size).getOrThrow())
    }

    @Test
    fun `the size counts bytes as UTF-8 holds them, so a wide character is not one byte`() {
        val wide = LibraryDocumentCoder.encode(document().copy(appVersion = "10.14.0 \u00e9\u4e16\ud83d\ude00"))
        val size = wide.toByteArray().size.toLong()

        assertEquals(
            LibraryDocumentFailure.TooLarge(size, size - 1),
            refusal(LibraryDocumentCoder.decode(wide, limit = size - 1)),
        )
        assertEquals(
            "10.14.0 \u00e9\u4e16\ud83d\ude00",
            LibraryDocumentCoder.decode(wide, limit = size).getOrThrow().appVersion,
        )
    }

    @Test
    fun `the size is checked before the parse so text that is not JSON is named too large`() {
        val oversized = " ".repeat((LibraryDocumentCoder.MAXIMUM_BYTES + 1).toInt())

        assertEquals(
            LibraryDocumentFailure.TooLarge(
                LibraryDocumentCoder.MAXIMUM_BYTES + 1,
                LibraryDocumentCoder.MAXIMUM_BYTES,
            ),
            refusal(LibraryDocumentCoder.decode(oversized)),
        )
        assertNull(LibraryDocumentCoder.declaredVersion(oversized))
    }

    @Test
    fun `a newer document is refused by name and nothing is read out of it`() {
        val parsed = parse(LibraryDocumentCoder.encode(document()))
        val newer = JsonObject(parsed + ("formatVersion" to JsonPrimitive(99)))

        assertEquals(
            LibraryDocumentFailure.NewerThanThisApp(99, 1),
            refusal(LibraryDocumentCoder.decode(newer.toString())),
        )
    }

    @Test
    fun `bytes that are not a library document are refused as such`() {
        assertEquals(
            LibraryDocumentFailure.NotALibraryDocument,
            refusal(LibraryDocumentCoder.decode("""{"hello":1}""")),
        )
    }

    @Test
    fun `an older document is migrated through each transform in order`() {
        // A fake version 0, proving the chain runs. The shipped chain is empty — version 1 is
        // the first — so without an injected transform there would be nothing to assert and
        // the second version would be the first to find out whether this worked.
        val parsed = parse(LibraryDocumentCoder.encode(document()))
        val older = JsonObject(
            parsed + mapOf(
                "formatVersion" to JsonPrimitive(0),
                "appVersion" to JsonPrimitive("before the transform"),
            ),
        )

        val read = LibraryDocumentCoder.decode(
            older.toString(),
            transforms = listOf(
                LibraryDocumentTransform(from = 0) { document ->
                    JsonObject(
                        document + ("appVersion" to JsonPrimitive("after the transform")),
                    )
                },
            ),
        ).getOrThrow()

        assertEquals(1, read.formatVersion)
        assertEquals("after the transform", read.appVersion)
    }

    @Test
    fun `an older document with no transform to reach this version is refused`() {
        val parsed = parse(LibraryDocumentCoder.encode(document()))
        val older = JsonObject(parsed + ("formatVersion" to JsonPrimitive(0)))

        assertEquals(
            LibraryDocumentFailure.NoMigrationPath(0),
            refusal(LibraryDocumentCoder.decode(older.toString())),
        )
    }

    @Test
    fun `the version is readable without decoding the document`() {
        assertEquals(1, LibraryDocumentCoder.declaredVersion(LibraryDocumentCoder.encode(document())))
        assertNull(LibraryDocumentCoder.declaredVersion("not json"))
    }

    private fun parse(text: String) = Json.parseToJsonElement(text) as JsonObject

    private fun refusal(result: Result<LibraryDocument>): LibraryDocumentFailure? =
        (result.exceptionOrNull() as? LibraryDocumentRefusal)?.reason
}

/**
 * design.md's table: the five records whose stores disagree on the wire.
 *
 * Written by iOS's encoder and read by this one. The file under
 * `packages/test-fixtures/library/` is the only thing the two suites share, which is the
 * point — neither platform can privately redefine what the document says.
 */
class LibraryDocumentBoundaryTest {

    private fun readIosDocument() =
        LibraryDocumentCoder.decode(LibraryDocumentFixture.document("written-by-ios.json"))
            .getOrThrow()

    @Test
    fun `a source timestamp iOS wrote as a Date arrives as epoch millis`() {
        val source = readIosDocument().library.sources
            .first { it.id == LibraryDocumentFixture.networkShareId.toString() }

        assertEquals(1_767_139_445_000L, epochMillis(source.lastSuccessfulSync))
    }

    @Test
    fun `a source kind iOS wrote as localFolder arrives as a kind this build knows`() {
        val kinds = readIosDocument().library.sources.map { it.kind }

        assertEquals(listOf("networkShare", "localFolder", "kavitaServer"), kinds)
        assertTrue(kinds.all { wireEnumOrNull<SourceKind>(it) != null })
    }

    @Test
    fun `a shelf cover arrives under the one key both platforms agreed`() {
        assertEquals("path:/b.cbz", readIosDocument().library.collections.first().coverMemberId)
    }

    @Test
    fun `a reading position iOS wrote as one blob arrives as all three kinds`() {
        val positions = readIosDocument().library.progress.map { it.position.position() }

        assertEquals(
            listOf(
                ReadingPosition.Page(12, 40),
                ReadingPosition.Reflowable(0.375, """{"href":"ch3"}"""),
                ReadingPosition.Listening(2, 9, 61_500L, 600_000L),
            ),
            positions,
        )
    }

    @Test
    fun `pinned shelves arrive as a list of the tokens both platforms already shared`() {
        val pins = readIosDocument().library.pinnedShelves.mapNotNull(ShelfPin::of).toSet()

        assertEquals(
            setOf(
                ShelfPin.Collection(LibraryDocumentFixture.collectionId),
                ShelfPin.ReadingListPin(LibraryDocumentFixture.listId),
            ),
            pins,
        )
    }

    @Test
    fun `every other record iOS wrote is the library this platform would have written`() {
        val theirs = readIosDocument()
        val mine = LibraryExport.document(
            LibraryDocumentFixture.snapshot,
            LibraryDocumentFixture.APP_VERSION,
            LibraryDocumentFixture.WRITTEN_AT,
        )

        // The envelope differs by the platform that wrote it, and by nothing else.
        assertEquals("ios", theirs.writtenBy)
        assertEquals(mine.library.certificatePins, theirs.library.certificatePins)
        assertEquals(mine.library.collections, theirs.library.collections)
        assertEquals(mine.library.readingLists, theirs.library.readingLists)
        assertEquals(mine.library.readingThemes, theirs.library.readingThemes)
        assertEquals(mine.library.progress, theirs.library.progress)
        assertEquals(mine.library.covers, theirs.library.covers)
        // iOS has no volume-button setting, so its document does not carry the field and this
        // one reads it back as null — "the document says nothing", not "the reader turned it
        // off". `LibraryImport` answers a null with the value this device already holds.
        assertEquals(
            mine.library.settings.copy(turnPagesWithVolumeButtons = null),
            theirs.library.settings,
        )
    }

    @Test
    fun `a document iOS wrote imports onto an empty device, record kind by record kind`() {
        // Task 4.1's round trip, in the direction this platform can assert: iOS's encoder
        // wrote the file, this decoder read it, and this importer landed it.
        val landed = LibraryImport.merging(readIosDocument(), LibrarySnapshot()).snapshot

        assertEquals(
            listOf(SourceKind.NETWORK_SHARE, SourceKind.LOCAL_FOLDER, SourceKind.KAVITA_SERVER),
            landed.sources.sources.map { it.kind },
        )
        assertEquals(
            1_767_139_445_000L,
            landed.sources.sources.first().lastSuccessfulSyncEpochMillis,
        )
        assertEquals(mapOf("nas.local" to setOf("AB:CD:EF:01")), landed.certificatePins)
        assertEquals("path:/b.cbz", landed.shelves.collections.first().coverMemberId)
        assertEquals(listOf("path:/b.cbz", "path:/a.cbz"), landed.shelves.lists.first().entries)
        assertEquals(
            LibraryDocumentFixture.snapshot.pinnedShelves.tokens.toSet(),
            landed.pinnedShelves.tokens.toSet(),
        )
        // iOS has no volume-button setting, so its document does not carry the field.
        assertEquals(
            LibraryDocumentFixture.snapshot.settings.copy(turnPagesWithVolumeButtons = false),
            landed.settings,
        )
        assertEquals(
            FontSizeStep.LARGE,
            landed.themes.default(ThemeScope.REFLOWABLE).values.fontSize,
        )
        assertEquals(PageFit.WIDTH, landed.themes.theme(ThemeScope.FIXED_LAYOUT, "Bone").fit)
        assertEquals("Midnight", landed.themes.customPalette?.name)
        assertEquals(
            listOf(
                ReadingPosition.Page(12, 40),
                ReadingPosition.Reflowable(0.375, """{"href":"ch3"}"""),
                ReadingPosition.Listening(2, 9, 61_500L, 600_000L),
            ),
            landed.progress.map { it.position },
        )
        // Every source that held a secret arrives without one and asks for it.
        assertTrue(landed.sources.sources.all { it.credentialReference == null })
        // The cover iOS's reader chose arrives as the same bytes, under the same key.
        assertEquals(
            listOf(ChosenCover(LibraryDocumentFixture.COVER_KEY, LibraryDocumentFixture.coverImage)),
            landed.covers,
        )
    }
}
