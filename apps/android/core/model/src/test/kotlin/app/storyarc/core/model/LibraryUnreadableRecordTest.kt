package app.storyarc.core.model

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * `library-portability` / *A field this version does not know*: an unreadable record means one
 * thing on both platforms. It is dropped, the rest of the document imports, and the preview
 * counts only what lands. iOS's `LibraryUnreadableRecordTests` asserts the same rows.
 */
class LibraryUnreadableRecordTest {

    private val written = LibraryExport.document(
        LibraryDocumentFixture.snapshot,
        LibraryDocumentFixture.APP_VERSION,
        LibraryDocumentFixture.WRITTEN_AT,
    )

    /** The fixture document with its first position changed by [edit], read by the decoder. */
    private fun decoded(edit: (JsonObject) -> JsonObject): LibraryDocument {
        val parsed = Json.parseToJsonElement(LibraryDocumentCoder.encode(written)) as JsonObject
        val library = parsed["library"] as JsonObject
        val progress = (library["progress"] as JsonArray).toMutableList()
        val first = progress[0] as JsonObject
        progress[0] = JsonObject(first + ("position" to edit(first["position"] as JsonObject)))
        val edited = JsonObject(
            parsed + ("library" to JsonObject(library + ("progress" to JsonArray(progress)))),
        )
        return LibraryDocumentCoder.decode(edited.toString()).getOrThrow()
    }

    private fun unknownKind() = decoded { JsonObject(it + ("kind" to JsonPrimitive("hologram"))) }

    @Test
    fun `a position of a kind this build does not know is dropped and the others land`() {
        val landed = LibraryImport.merging(unknownKind(), LibrarySnapshot()).snapshot

        assertEquals(2, landed.progress.size)
        assertEquals(3, landed.sources.sources.size)
    }

    @Test
    fun `a known kind that lacks a field it needs is dropped the same way`() {
        val document = decoded { JsonObject(it - "index") }

        val landed = LibraryImport.merging(document, LibrarySnapshot()).snapshot

        assertEquals(2, landed.progress.size)
    }

    @Test
    fun `the preview counts the records the merge will keep, not the records that arrived`() {
        val whole = LibraryImport.plan(written, LibrarySnapshot())
        val dropped = LibraryImport.plan(unknownKind(), LibrarySnapshot())

        assertEquals(3, whole.progressToAdd + whole.progressToMerge)
        assertEquals(2, dropped.progressToAdd + dropped.progressToMerge)
    }
}
