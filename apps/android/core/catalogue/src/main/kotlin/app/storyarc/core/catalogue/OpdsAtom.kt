package app.storyarc.core.catalogue

import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import org.xmlpull.v1.XmlPullParser
import org.xmlpull.v1.XmlPullParserException
import org.xmlpull.v1.XmlPullParserFactory

/**
 * OPDS 1.2, which is an Atom feed with a handful of extra relations.
 *
 * Parsed with the platform's `XmlPullParser` rather than a dependency. Atom is a small
 * grammar and the subset OPDS uses is smaller still -- a feed title, entries, and links
 * distinguished by their `rel`.
 *
 * iOS uses `XMLParser` for the same job. Both are the platform's own reader.
 */
internal object OpdsAtom {

    @Suppress("LongMethod", "CyclomaticComplexMethod")
    fun parse(body: ByteArray, baseUrl: String): OpdsFeed {
        // `XmlPullParserFactory` rather than `android.util.Xml`, so the same parser runs
        // in a JVM unit test. Android's factory returns the same KXml implementation the
        // convenience method would have given.
        val factory = XmlPullParserFactory.newInstance()
        factory.isNamespaceAware = true
        val parser = factory.newPullParser()
        parser.setInput(body.inputStream(), null)

        var sawFeed = false
        var feedTitle = ""
        val navigation = mutableListOf<OpdsSection>()
        val publications = mutableListOf<OpdsEntry>()
        val facets = mutableListOf<OpdsFacet>()
        var next: String? = null
        var searchTemplate: String? = null
        var searchDescription: String? = null

        var entry: PartialEntry? = null
        var text = StringBuilder()

        try {
            var event = parser.eventType
            while (event != XmlPullParser.END_DOCUMENT) {
                when (event) {
                    XmlPullParser.START_TAG -> {
                        text = StringBuilder()
                        when (parser.name) {
                            "feed" -> sawFeed = true
                            "entry" -> entry = PartialEntry()
                            "link" -> {
                                val link = Link.of(parser, baseUrl)
                                if (link != null) {
                                    val current = entry
                                    if (current != null) {
                                        entryLink(current, link)
                                    } else {
                                        when {
                                            link.rel == "next" -> next = link.href
                                            link.rel == "search" ->
                                                // Two shapes wear the same relation. Some
                                                // servers put the query template straight
                                                // in the href; others point at an
                                                // OpenSearch description that holds it.
                                                if (link.raw.contains("{searchTerms}")) {
                                                    searchTemplate = link.href
                                                } else {
                                                    searchDescription = link.href
                                                }
                                            link.rel == FACET ->
                                                facets += OpdsFacet(
                                                    group = link.facetGroup ?: link.title,
                                                    title = link.title,
                                                    href = link.href,
                                                    count = link.count,
                                                    isActive = link.isActiveFacet,
                                                )
                                            link.isSection ->
                                                navigation += OpdsSection(
                                                    title = link.title,
                                                    href = link.href,
                                                    count = link.count,
                                                )
                                        }
                                    }
                                }
                            }
                        }
                    }

                    XmlPullParser.TEXT -> text.append(parser.text)

                    XmlPullParser.END_TAG -> {
                        val value = text.toString().trim()
                        val current = entry
                        when (parser.name) {
                            "entry" -> {
                                current?.finished()?.let { publications += it }
                                entry = null
                            }
                            "title" ->
                                if (current != null) {
                                    current.title = value
                                } else if (feedTitle.isEmpty()) {
                                    feedTitle = value
                                }
                            "id" -> if (current != null) current.id = value
                            // Inside `author`. Atom puts nothing else called `name` here.
                            "name" -> if (current != null && value.isNotEmpty()) {
                                current.authors += value
                            }
                            "summary", "content" ->
                                if (current != null && current.summary == null &&
                                    value.isNotEmpty()
                                ) {
                                    current.summary = value
                                }
                            "updated" -> if (current != null) current.updated = OpdsDates.parse(value)
                            // Calibre's OPDS extension.
                            "series" -> if (current != null && value.isNotEmpty()) {
                                current.series = value
                            }
                        }
                    }
                }
                event = parser.next()
            }
        } catch (error: XmlPullParserException) {
            throw OpdsError.Malformed(error.message ?: "invalid XML")
        }

        if (!sawFeed) throw OpdsError.NotAFeed(OpdsError.Received.Unrecognised(null))

        return OpdsFeed(
            title = feedTitle,
            navigation = navigation,
            publications = publications,
            facets = facets,
            next = next,
            searchTemplate = searchTemplate,
            searchDescription = searchDescription,
        )
    }

    private const val FACET = "http://opds-spec.org/facet"
    private const val ACQUISITION = "http://opds-spec.org/acquisition"

    private fun entryLink(entry: PartialEntry, link: Link) {
        when (link.rel) {
            "http://opds-spec.org/image", "http://opds-spec.org/cover" -> entry.cover = link.href
            "http://opds-spec.org/image/thumbnail", "http://opds-spec.org/thumbnail" ->
                entry.thumbnail = link.href
            else -> {
                val kind = OpdsAcquisition.Kind.named(link.rel)
                    // A relation the standard added after this code was written. Listed as
                    // indirect rather than dropped: the spec requires an unsupported
                    // acquisition to be named, and a dropped link cannot be named.
                    ?: if (link.rel.startsWith(ACQUISITION)) {
                        OpdsAcquisition.Kind.INDIRECT
                    } else {
                        null
                    }
                if (kind != null) {
                    entry.acquisitions += OpdsAcquisition(link.href, link.type, kind)
                }
            }
        }
    }

    /** One `link` element, which in OPDS carries almost everything. */
    private class Link(
        val raw: String,
        val href: String,
        val rel: String,
        val type: String,
        val title: String,
        val count: Int?,
        val facetGroup: String?,
        val isActiveFacet: Boolean,
    ) {
        /**
         * Whether this points at another feed a reader can enter.
         *
         * The relation varies -- `subsection`, `sort_new`, or nothing at all -- so the type
         * is what decides. `self`, `start` and the pagination relations point at feeds too,
         * and are not places to go.
         */
        val isSection: Boolean
            get() = type.contains("application/atom+xml") && title.isNotEmpty() &&
                rel !in setOf("self", "start", "up", "first", "last", "previous")

        companion object {
            fun of(parser: XmlPullParser, baseUrl: String): Link? {
                val raw = attribute(parser, "href") ?: return null
                val href = OpdsDocument.resolve(raw, baseUrl) ?: return null
                return Link(
                    raw = raw,
                    href = href,
                    rel = attribute(parser, "rel").orEmpty(),
                    type = attribute(parser, "type").orEmpty(),
                    title = attribute(parser, "title").orEmpty(),
                    count = attribute(parser, "count")?.toIntOrNull(),
                    facetGroup = attribute(parser, "facetGroup"),
                    isActiveFacet = attribute(parser, "activeFacet") == "true",
                )
            }

            /**
             * An attribute by its local name, whatever namespace it is in.
             *
             * `count`, `facetGroup` and `activeFacet` all live in namespaces. Asking for a
             * bare name and getting nothing is how a section that declared twelve items
             * reported none.
             */
            private fun attribute(parser: XmlPullParser, name: String): String? {
                for (index in 0 until parser.attributeCount) {
                    if (parser.getAttributeName(index) == name) {
                        return parser.getAttributeValue(index)
                    }
                }
                return null
            }
        }
    }

    /** An entry under construction. */
    private class PartialEntry {
        var id = ""
        var title = ""
        var authors = mutableListOf<String>()
        var summary: String? = null
        var series: String? = null
        var updated: Date? = null
        var cover: String? = null
        var thumbnail: String? = null
        var acquisitions = mutableListOf<OpdsAcquisition>()

        /** Null for an entry with no title, which is not something a reader can be shown. */
        fun finished(): OpdsEntry? {
            if (title.isEmpty()) return null
            return OpdsEntry(
                id = id.ifEmpty { title },
                title = title,
                authors = authors.toList(),
                summary = summary,
                series = series,
                updated = updated,
                cover = cover,
                thumbnail = thumbnail,
                acquisitions = acquisitions.toList(),
            )
        }
    }
}

/** The date formats OPDS feeds actually use. */
internal object OpdsDates {
    /**
     * RFC 3339, which Atom requires, and the date-only form several servers send anyway.
     *
     * A formatter per call rather than a shared one: `SimpleDateFormat` is not thread-safe,
     * and a feed is parsed once per request -- the allocation is nothing beside the fetch
     * that produced the bytes.
     */
    fun parse(value: String): Date? {
        for (pattern in PATTERNS) {
            val format = SimpleDateFormat(pattern, Locale.US)
            format.timeZone = TimeZone.getTimeZone("UTC")
            format.isLenient = false
            runCatching { format.parse(value) }.getOrNull()?.let { return it }
        }
        return null
    }

    private val PATTERNS = listOf(
        "yyyy-MM-dd'T'HH:mm:ss.SSSXXX",
        "yyyy-MM-dd'T'HH:mm:ssXXX",
        "yyyy-MM-dd",
    )
}
