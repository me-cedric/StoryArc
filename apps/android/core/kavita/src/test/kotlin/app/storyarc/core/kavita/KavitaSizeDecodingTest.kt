package app.storyarc.core.kavita

import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * What a chapter and a reading-list entry say about how large their file is.
 *
 * Task 7.8 of `close-the-audited-gaps`: a whole-shelf download states its size before it
 * starts, so the size has to come off the wire. Both numbers are in the payloads a live Kavita
 * 0.9.1.4 answers with -- `ReadingListItemDto.fileSize` and `ChapterDto.files[].bytes` -- and
 * both were dropped on the way in. A server that states none reads as zero, which the shelf
 * download treats as "not stated" and never as an empty file. iOS's `KavitaSizeDecodingTests`
 * makes the same three claims.
 */
class KavitaSizeDecodingTest {

    private val json = Json { ignoreUnknownKeys = true }

    @Test
    fun `an entry states the size of its file`() {
        val entry = json.decodeFromString(
            ListSerializer(KavitaReadingListItem.serializer()),
            """[{"id":1,"order":0,"chapterId":3103,"seriesId":312,"pagesTotal":22,"fileSize":41943040}]""",
        ).single()

        assertEquals(41_943_040L, entry.fileSize)
    }

    @Test
    fun `an entry that states no size reads as zero`() {
        val entry = json.decodeFromString(
            ListSerializer(KavitaReadingListItem.serializer()),
            """[{"id":1,"order":0,"chapterId":3103,"seriesId":312}]""",
        ).single()

        assertEquals(0L, entry.fileSize)
    }

    @Test
    fun `a chapter's size is the sum of its files`() {
        val chapter = json.decodeFromString(
            KavitaChapter.serializer(),
            """{"id":3103,"pages":22,"files":[{"id":1,"bytes":1000,"pages":10},{"id":2,"bytes":2500,"pages":12}]}""",
        )

        assertEquals(3_500L, chapter.sizeBytes)
    }

    @Test
    fun `a chapter with no files states no size`() {
        assertEquals(0L, json.decodeFromString(KavitaChapter.serializer(), """{"id":3103}""").sizeBytes)
    }
}
