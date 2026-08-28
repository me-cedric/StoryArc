package app.storyarc.core.catalogue

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.assertFalse
import org.junit.Test

/**
 * The two dialects, read from the shapes real servers send.
 *
 * The same fixtures iOS's `OpdsParsingTests` uses, so a difference between the platforms
 * is a failing test rather than a difference a reader finds.
 */
class OpdsParsingTest {

    private val base = "https://library.example/opds/"

    private val atomNavigation = """
    <?xml version="1.0" encoding="utf-8"?>
    <feed xmlns="http://www.w3.org/2005/Atom" xmlns:opds="http://opds-spec.org/2010/catalog">
      <title>Example Library</title>
      <link rel="self" href="/opds/" type="application/atom+xml;profile=opds-catalog"/>
      <link rel="start" href="/opds/" type="application/atom+xml;profile=opds-catalog"/>
      <link rel="search" href="/opds/search?q={searchTerms}" type="application/atom+xml"/>
      <link rel="subsection" href="unread" title="Unread" opds:count="12"
            type="application/atom+xml;profile=opds-catalog;kind=acquisition"/>
      <link rel="subsection" href="series" title="Series"
            type="application/atom+xml;profile=opds-catalog;kind=navigation"/>
    </feed>
    """.trimIndent()

    @Test
    fun atomNavigationFeedYieldsSections() {
        val feed = OpdsDocument.parse(atomNavigation.toByteArray(), baseUrl = base)
        assertEquals("Example Library", feed.title)
        assertTrue(feed.publications.isEmpty())
        assertEquals(listOf("Unread", "Series"), feed.navigation.map { it.title })
        assertEquals("https://library.example/opds/unread", feed.navigation.first().href)
        assertEquals("https://library.example/opds/search?q={searchTerms}", feed.searchTemplate)
    }

    @Test
    fun selfStartAndUpAreNotSections() {
        val feed = OpdsDocument.parse(atomNavigation.toByteArray(), baseUrl = base)
        assertEquals(2, feed.navigation.size)
    }

    @Test
    fun countIsReadWhenGivenAndAbsentOtherwise() {
        val feed = OpdsDocument.parse(atomNavigation.toByteArray(), baseUrl = base)
        assertEquals(12, feed.navigation[0].count)
        assertNull(feed.navigation[1].count)
    }

    private val atomAcquisition = """
    <?xml version="1.0" encoding="utf-8"?>
    <feed xmlns="http://www.w3.org/2005/Atom"
          xmlns:opds="http://opds-spec.org/2010/catalog"
          xmlns:thr="http://purl.org/syndication/thread/1.0">
      <title>Unread</title>
      <link rel="next" href="unread?page=2" type="application/atom+xml"/>
      <link rel="http://opds-spec.org/facet" href="?lang=en" title="English"
            opds:facetGroup="Language" opds:activeFacet="true" thr:count="40"/>
      <entry>
        <title>The Long Field</title>
        <id>urn:uuid:1</id>
        <updated>2026-08-01T10:00:00Z</updated>
        <author><name>Ada Lovelace</name></author>
        <summary>A field, at length.</summary>
        <link rel="http://opds-spec.org/image" href="cover/1.jpg" type="image/jpeg"/>
        <link rel="http://opds-spec.org/image/thumbnail" href="thumb/1.jpg" type="image/jpeg"/>
        <link rel="http://opds-spec.org/acquisition" href="download/1.epub"
              type="application/epub+zip"/>
        <link rel="http://opds-spec.org/acquisition" href="download/1.pdf"
              type="application/pdf"/>
      </entry>
      <entry>
        <title>Borrowed Only</title>
        <id>urn:uuid:2</id>
        <link rel="http://opds-spec.org/acquisition/borrow" href="borrow/2"
              type="application/epub+zip"/>
      </entry>
      <entry><id>urn:uuid:3</id></entry>
    </feed>
    """.trimIndent()

    @Test
    fun atomAcquisitionFeedYieldsEntries() {
        val feed = OpdsDocument.parse(atomAcquisition.toByteArray(), baseUrl = base)
        assertTrue(feed.isAcquisition)
        // The third entry has no title, so there is nothing to show and it is dropped.
        assertEquals(
            listOf("The Long Field", "Borrowed Only"),
            feed.publications.map { it.title },
        )
        assertEquals("https://library.example/opds/unread?page=2", feed.next)

        val first = feed.publications.first()
        assertEquals(listOf("Ada Lovelace"), first.authors)
        assertEquals("A field, at length.", first.summary)
        assertTrue(first.cover!!.endsWith("cover/1.jpg"))
        assertTrue(first.thumbnail!!.contains("thumb"))
        assertTrue(first.updated != null)
        assertEquals(
            listOf("application/epub+zip", "application/pdf"),
            first.acquisitions.map { it.mediaType },
        )
        assertTrue(first.acquisitions.all { it.kind == OpdsAcquisition.Kind.DIRECT })
    }

    @Test
    fun facetsCarryTheirGroupAndActiveState() {
        val feed = OpdsDocument.parse(atomAcquisition.toByteArray(), baseUrl = base)
        val facet = feed.facets.first()
        assertEquals("Language", facet.group)
        assertEquals("English", facet.title)
        assertTrue(facet.isActive)
    }

    @Test
    fun aBorrowLinkIsNamedRatherThanDropped() {
        val feed = OpdsDocument.parse(atomAcquisition.toByteArray(), baseUrl = base)
        val borrowed = feed.publications.last()
        assertEquals(
            listOf(OpdsAcquisition.Kind.BORROW),
            borrowed.acquisitions.map { it.kind },
        )
        // `opds-catalog`: an unsupported acquisition type is stated, not failed silently.
        assertTrue(borrowed.acquisitions.none { it.kind.isFetchable })
    }

    @Test
    fun openAccessIsDistinguishedFromPlainAcquisition() {
        val xml = """
        <feed xmlns="http://www.w3.org/2005/Atom"><title>t</title><entry><title>e</title>
        <link rel="http://opds-spec.org/acquisition/open-access" href="free.epub"
              type="application/epub+zip"/></entry></feed>
        """.trimIndent()
        val feed = OpdsDocument.parse(xml.toByteArray(), baseUrl = base)
        assertEquals(
            OpdsAcquisition.Kind.OPEN,
            feed.publications.first().acquisitions.first().kind,
        )
    }

    @Test
    fun anUnknownAcquisitionRelationIsIndirectRatherThanLost() {
        val xml = """
        <feed xmlns="http://www.w3.org/2005/Atom"><title>t</title><entry><title>e</title>
        <link rel="http://opds-spec.org/acquisition/lend-later" href="x"
              type="application/epub+zip"/></entry></feed>
        """.trimIndent()
        val feed = OpdsDocument.parse(xml.toByteArray(), baseUrl = base)
        assertEquals(
            OpdsAcquisition.Kind.INDIRECT,
            feed.publications.first().acquisitions.first().kind,
        )
    }

    @Test
    fun aSearchLinkWithoutATemplateIsADescriptionDocument() {
        val xml = """
        <feed xmlns="http://www.w3.org/2005/Atom"><title>t</title>
        <link rel="search" href="opensearch.xml"
              type="application/opensearchdescription+xml"/></feed>
        """.trimIndent()
        val feed = OpdsDocument.parse(xml.toByteArray(), baseUrl = base)
        assertNull(feed.searchTemplate)
        assertTrue(feed.searchDescription!!.endsWith("opensearch.xml"))
    }

    private val json = """
    {
      "metadata": { "title": "Example Library" },
      "links": [
        { "rel": "self", "href": "/opds", "type": "application/opds+json" },
        { "rel": ["next"], "href": "/opds?page=2", "type": "application/opds+json" },
        { "rel": "search", "href": "/opds/search{?query}", "templated": true }
      ],
      "navigation": [
        { "title": "Unread", "href": "/opds/unread", "type": "application/opds+json",
          "properties": { "numberOfItems": 12 } }
      ],
      "groups": [
        {
          "navigation": [
            { "title": "Series", "href": "/opds/series", "type": "application/opds+json" }
          ],
          "publications": [
            {
              "metadata": {
                "identifier": "urn:uuid:9", "title": "Grouped Title",
                "author": "Grace Hopper"
              },
              "links": [
                { "href": "/download/9.epub", "type": "application/epub+zip",
                  "rel": "http://opds-spec.org/acquisition" }
              ]
            }
          ]
        }
      ],
      "facets": [
        {
          "metadata": { "title": "Language" },
          "links": [
            { "title": "English", "href": "/opds?lang=en",
              "properties": { "numberOfItems": 40 } }
          ]
        }
      ],
      "publications": [
        {
          "metadata": {
            "title": "Harbour Lights 02",
            "author": [{ "name": "Ada Lovelace" }, "Alan Turing"],
            "belongsTo": { "series": { "name": "Harbour Lights", "position": 2 } },
            "modified": "2026-08-01T10:00:00Z",
            "description": "Second."
          },
          "images": [
            { "href": "/cover/2.jpg", "width": 1200 },
            { "href": "/thumb/2.jpg", "width": 200 }
          ],
          "links": [
            { "href": "/download/2.epub", "type": "application/epub+zip" }
          ]
        }
      ]
    }
    """.trimIndent()

    @Test
    fun jsonFeedIsDetectedAndRead() {
        val feed = OpdsDocument.parse(json.toByteArray(), baseUrl = base)
        assertEquals("Example Library", feed.title)
        assertEquals("https://library.example/opds?page=2", feed.next)
        assertEquals("https://library.example/opds/search{?query}", feed.searchTemplate)
        assertNull(feed.searchDescription)
    }

    @Test
    fun groupsAreFlattenedIntoTheFeed() {
        val feed = OpdsDocument.parse(json.toByteArray(), baseUrl = base)
        assertEquals(listOf("Unread", "Series"), feed.navigation.map { it.title })
        assertEquals(
            listOf("Harbour Lights 02", "Grouped Title"),
            feed.publications.map { it.title },
        )
    }

    @Test
    fun anAuthorIsReadWhicheverShapeItTakes() {
        val feed = OpdsDocument.parse(json.toByteArray(), baseUrl = base)
        assertEquals(
            listOf("Ada Lovelace", "Alan Turing"),
            feed.publications.first().authors,
        )
        assertEquals(listOf("Grace Hopper"), feed.publications.last().authors)
    }

    @Test
    fun theLargestImageIsTheCoverAndTheSmallestTheThumbnail() {
        val feed = OpdsDocument.parse(json.toByteArray(), baseUrl = base)
        val entry = feed.publications.first()
        assertTrue(entry.cover!!.contains("cover"))
        assertTrue(entry.thumbnail!!.contains("thumb"))
    }

    @Test
    fun seriesAndPositionAreRead() {
        val feed = OpdsDocument.parse(json.toByteArray(), baseUrl = base)
        assertEquals("Harbour Lights", feed.publications.first().series)
        assertEquals(2.0, feed.publications.first().seriesIndex!!, 0.001)
    }

    @Test
    fun aLinkWithNoRelationIsStillAnAcquisition() {
        val feed = OpdsDocument.parse(json.toByteArray(), baseUrl = base)
        assertEquals(
            listOf(OpdsAcquisition.Kind.DIRECT),
            feed.publications.first().acquisitions.map { it.kind },
        )
    }

    @Test
    fun anHtmlPageIsNamedAsOne() {
        val page = "<!DOCTYPE html><html><head><title>Log in</title></head></html>"
        val error = runCatching { OpdsDocument.parse(page.toByteArray(), baseUrl = base) }
            .exceptionOrNull()
        assertEquals(OpdsError.NotAFeed(OpdsError.Received.Html), error)
    }

    @Test
    fun anXhtmlPageIsAlsoAPageNotAFeed() {
        val page = """
        <?xml version="1.0"?>
        <html xmlns="http://www.w3.org/1999/xhtml"><body>Nope</body></html>
        """.trimIndent()
        val error = runCatching { OpdsDocument.parse(page.toByteArray(), baseUrl = base) }
            .exceptionOrNull()
        assertEquals(OpdsError.NotAFeed(OpdsError.Received.Html), error)
    }

    @Test
    fun anEmptyBodyIsNamedAsEmpty() {
        val error = runCatching { OpdsDocument.parse("   \n".toByteArray(), baseUrl = base) }
            .exceptionOrNull()
        assertEquals(OpdsError.Empty, error)
    }

    @Test
    fun someOtherJsonApiIsNotAFeed() {
        val error = runCatching {
            OpdsDocument.parse("""{"ok":true}""".toByteArray(), baseUrl = base)
        }.exceptionOrNull()
        assertEquals(
            OpdsError.NotAFeed(OpdsError.Received.Unrecognised("application/json")),
            error,
        )
    }

    @Test
    fun aBodyThatIsNeitherDialectSaysWhatItWas() {
        val error = runCatching {
            OpdsDocument.parse("a,b\n1,2".toByteArray(), contentType = "text/csv", baseUrl = base)
        }.exceptionOrNull()
        assertEquals(OpdsError.NotAFeed(OpdsError.Received.Unrecognised("text/csv")), error)
    }

    @Test
    fun aWrongContentTypeDoesNotStopACorrectBody() {
        // Several servers send `application/octet-stream` for a perfectly good Atom feed.
        val feed = OpdsDocument.parse(
            atomNavigation.toByteArray(),
            contentType = "application/octet-stream",
            baseUrl = base,
        )
        assertEquals("Example Library", feed.title)
    }

    @Test
    fun aChallengeNamesItsScheme() {
        assertEquals(
            OpdsError.AuthenticationScheme.BASIC,
            OpdsError.AuthenticationScheme.of("""Basic realm="opds""""),
        )
        assertEquals(
            OpdsError.AuthenticationScheme.BEARER,
            OpdsError.AuthenticationScheme.of("Bearer"),
        )
        assertNull(OpdsError.AuthenticationScheme.of("Digest qop=auth"))
        assertFalse(OpdsAcquisition.Kind.BORROW.isFetchable)
    }
}

/**
 * What a typed address becomes.
 *
 * The one piece of the add-a-catalogue flow that is not a network call, and the one that
 * decides whether a password travels in the clear.
 */
class OpdsAddressTest {
    @Test
    fun aBareHostBecomesHttps() {
        assertEquals(
            "https://library.example.com/opds",
            OpdsDocument.address("library.example.com/opds"),
        )
    }

    @Test
    fun anExplicitSchemeIsKept() {
        // A reader who typed `http` meant it -- usually a server on their own network. The
        // default is the secure one; the override is theirs.
        assertEquals("http://nas.local:8080/opds", OpdsDocument.address("http://nas.local:8080/opds"))
    }

    @Test
    fun surroundingSpaceIsIgnored() {
        assertEquals("https://komga.local/opds", OpdsDocument.address("  komga.local/opds  "))
    }

    @Test
    fun somethingWithNoHostIsNotAnAddress() {
        assertNull(OpdsDocument.address(""))
        assertNull(OpdsDocument.address("   "))
        assertNull(OpdsDocument.address("https://"))
        assertNull(OpdsDocument.address("not a host at all"))
    }
}
