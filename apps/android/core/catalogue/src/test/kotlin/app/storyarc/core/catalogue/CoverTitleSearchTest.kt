package app.storyarc.core.catalogue

import app.storyarc.core.model.CoverTitleProvider
import java.io.File
import kotlin.io.path.createTempDirectory
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * How a title is asked about, and how each of the three answers is read.
 *
 * iOS's `CoverTitleSearchTests` makes the same claims about the same three providers.
 */
class CoverTitleSearchTest {

    @Test
    fun `Open Library is asked by title and author, for three fields`() {
        val request = CoverTitleSearch.request(
            CoverTitleProvider.OPEN_LIBRARY,
            title = "Fine Print",
            author = "Ada",
        )!!

        assertTrue(request.url.contains("title=Fine+Print"))
        assertTrue(request.url.contains("author=Ada"))
        assertTrue(request.url.contains("fields=title%2Cauthor_name%2Ccover_i"))
    }

    @Test
    fun `AniList and MangaUpdates are asked by POST, with the title in the body`() {
        for (provider in listOf(CoverTitleProvider.ANILIST, CoverTitleProvider.MANGA_UPDATES)) {
            val request = CoverTitleSearch.request(provider, title = "Nausicaa")!!
            assertEquals("POST", request.method)
            assertTrue(request.url.contains(provider.host))
            assertTrue(request.body!!.contains("Nausicaa"))
        }
    }

    @Test
    fun `an empty title asks nobody`() {
        for (provider in CoverTitleProvider.entries) {
            assertNull(CoverTitleSearch.request(provider, title = " "))
        }
    }

    @Test
    fun `Open Library's documents become candidates, and a coverless one does not`() {
        // A document with no `cover_i` has no picture, so it is not a candidate however well
        // its title matches.
        val body = """
            {"docs":[{"title":"Fine Print","author_name":["Ada"],"cover_i":42},
                     {"title":"Fine Print, again","author_name":["Ada"]}]}
        """.trimIndent()

        val found = CoverTitleSearch.candidates(
            body.toByteArray(),
            CoverTitleProvider.OPEN_LIBRARY,
        )

        assertEquals(1, found.size)
        assertEquals("Fine Print", found.first().title)
        assertEquals("Ada", found.first().subtitle)
        assertEquals("https://covers.openlibrary.org/b/id/42-L.jpg", found.first().imageUrl)
    }

    @Test
    fun `AniList's media become candidates, English title first`() {
        val body = """
            {"data":{"Page":{"media":[
              {"title":{"romaji":"Kaze no Tani","english":"Valley of the Wind"},
               "coverImage":{"large":"https://art.example/1.jpg"}}]}}}
        """.trimIndent()

        val found = CoverTitleSearch.candidates(body.toByteArray(), CoverTitleProvider.ANILIST)

        assertEquals(1, found.size)
        assertEquals("Valley of the Wind", found.first().title)
        assertEquals(CoverTitleProvider.ANILIST, found.first().provider)
    }

    @Test
    fun `MangaUpdates' records become candidates`() {
        val body = """
            {"results":[{"record":{"title":"Nausicaa",
              "image":{"url":{"original":"https://art.example/2.jpg"}}}}]}
        """.trimIndent()

        val found = CoverTitleSearch.candidates(
            body.toByteArray(),
            CoverTitleProvider.MANGA_UPDATES,
        )

        assertEquals(1, found.size)
        assertEquals("https://art.example/2.jpg", found.first().imageUrl)
    }

    @Test
    fun `a nonsense answer reads as no candidates rather than as an error`() {
        // A provider that answers nonsense has not answered, and `cover-art` says an
        // unanswered lookup leaves the publication with the cover it had.
        for (provider in CoverTitleProvider.entries) {
            assertTrue(CoverTitleSearch.candidates("not json".toByteArray(), provider).isEmpty())
        }
    }

    @Test
    fun `every title provider states a name and a host`() {
        for (provider in CoverTitleProvider.entries) {
            assertTrue(provider.displayName.isNotEmpty())
            assertTrue(provider.host.contains("."))
        }
    }

    @Test
    fun `a JSON null is no title, not the word null, and does not empty the list`() {
        // `content` reads a JSON null as "null", and `int` throws on one -- which emptied the
        // whole answer, so one coverless document cost the reader every candidate.
        val aniList = """
            {"data":{"Page":{"media":[
              {"title":{"romaji":"Kaze no Tani","english":null},
               "coverImage":{"large":"https://s4.anilist.co/1.jpg"}}]}}}
        """.trimIndent()
        assertEquals(
            "Kaze no Tani",
            CoverTitleSearch.candidates(aniList.toByteArray(), CoverTitleProvider.ANILIST)
                .single().title,
        )

        val openLibrary = """
            {"docs":[{"title":"Fine Print","cover_i":null},
                     {"title":"Fine Print","author_name":[null],"cover_i":42}]}
        """.trimIndent()
        val found = CoverTitleSearch.candidates(
            openLibrary.toByteArray(),
            CoverTitleProvider.OPEN_LIBRARY,
        )
        assertEquals(1, found.size)
        assertNull(found.single().subtitle)
    }

    @Test
    fun `one picture is one candidate, and a picture off the listed hosts is none`() = runBlocking {
        val body = """
            {"data":{"Page":{"media":[
              {"title":{"romaji":"A"},"coverImage":{"large":"https://s4.anilist.co/1.jpg"}},
              {"title":{"romaji":"B"},"coverImage":{"large":"https://s4.anilist.co/1.jpg"}},
              {"title":{"romaji":"C"},"coverImage":{"large":"https://tracker.example/2.jpg"}}]}}}
        """.trimIndent()
        val client = client { CoverFetched(200, body.toByteArray(), it.url) }

        val found = client.candidates("Kaze", providers = listOf(CoverTitleProvider.ANILIST))

        assertEquals(listOf("https://s4.anilist.co/1.jpg"), found.map { it.imageUrl })
    }

    @Test
    fun `a title search is asked once and then read from the cache`() = runBlocking {
        var asked = 0
        val client = client {
            asked++
            CoverFetched(200, "{\"docs\":[]}".toByteArray(), it.url)
        }

        client.candidates("Fine Print", "Ada", listOf(CoverTitleProvider.OPEN_LIBRARY))
        client.candidates("Fine Print", "Ada", listOf(CoverTitleProvider.OPEN_LIBRARY))

        assertEquals(1, asked)
    }

    private fun client(transport: CoverTransport) = CoverLookupClient(
        isEnabled = { true },
        cache = CoverLookupCache(
            File(createTempDirectory("title-search").toFile(), "cover-lookups.json"),
        ),
        transport = transport,
    )
}

