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

        // An entry-level link not yet resolved to an acquisition, because OPDS lets a
        // `<link>` carry an `<opds:indirectAcquisition>` child that only its end tag has
        // finished naming -- see 11.4.
        var pendingLink: Link? = null
        var pendingLinkIsIndirect = false

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
                                        // 11.1: the one link an OPDS 1.2 section entry
                                        // carries, not an acquisition and not the entry's
                                        // own permalink.
                                        if (link.type.contains("application/atom+xml") &&
                                            link.rel !in setOf("self", "up", "start")
                                        ) {
                                            current.sectionLink =
                                                SectionLink(href = link.href, count = link.count)
                                        }
                                        // Not resolved yet: the `link` end tag finishes
                                        // this once it knows whether an
                                        // `indirectAcquisition` child followed -- 11.4.
                                        pendingLink = link
                                        pendingLinkIsIndirect = isProtectedType(link.type)
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
                            "indirectAcquisition" ->
                                // 11.4: its mere presence means another step stands
                                // between this link and an openable file -- OPDS-LCP
                                // chief among them -- whatever format the step ends in.
                                // The type it carries is not read: the outer link's own
                                // type is what `publication-formats` already shows the
                                // reader as "offered as".
                                if (pendingLink != null) pendingLinkIsIndirect = true
                        }
                    }

                    XmlPullParser.TEXT -> text.append(parser.text)

                    XmlPullParser.END_TAG -> {
                        val value = text.toString().trim()
                        val current = entry
                        when (parser.name) {
                            "link" -> {
                                val link = pendingLink
                                if (current != null && link != null) {
                                    entryLink(current, link, pendingLinkIsIndirect)
                                }
                                pendingLink = null
                                pendingLinkIsIndirect = false
                            }
                            "entry" -> {
                                current?.finished()?.let { finished ->
                                    // OPDS 1.2 puts each section of a navigation feed in
                                    // its own `entry`, carrying one `application/atom+xml`
                                    // link rather than an acquisition. An entry with
                                    // nothing to acquire and such a link is that section,
                                    // not a publication with no download -- 11.1.
                                    val section = current.sectionLink
                                    if (finished.acquisitions.isEmpty() && section != null) {
                                        navigation += OpdsSection(
                                            title = finished.title,
                                            href = section.href,
                                            count = section.count,
                                        )
                                    } else {
                                        publications += finished
                                    }
                                }
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

    private fun entryLink(entry: PartialEntry, link: Link, isIndirect: Boolean) {
        when (link.rel) {
            "http://opds-spec.org/image", "http://opds-spec.org/cover" -> entry.cover = link.href
            "http://opds-spec.org/image/thumbnail", "http://opds-spec.org/thumbnail" ->
                entry.thumbnail = link.href
            else -> {
                val kind = if (isIndirect) {
                    OpdsAcquisition.Kind.INDIRECT
                } else {
                    OpdsAcquisition.Kind.named(link.rel)
                        // A relation the standard added after this code was written.
                        // Listed as indirect rather than dropped: the spec requires an
                        // unsupported acquisition to be named, and a dropped link cannot
                        // be named.
                        ?: if (link.rel.startsWith(ACQUISITION)) {
                            OpdsAcquisition.Kind.INDIRECT
                        } else {
                            null
                        }
                }
                if (kind != null) {
                    entry.acquisitions +=
                        OpdsAcquisition.of(link.href, link.type, kind, link.length)
                }
            }
        }
    }

    /**
     * A media type that names a protection step rather than an openable file -- OPDS-LCP's
     * license, or Adobe's ADEPT activation. 11.4: without this, a link typed to one of these
     * parsed as `direct` and the refusal named the wrapper's media type instead of saying the
     * acquisition itself is unsupported.
     */
    private fun isProtectedType(type: String): Boolean =
        type == "application/vnd.adobe.adept+xml" ||
            type.contains("vnd.readium.lcp.license") ||
            type.endsWith("+lcp")

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
        /** RFC 4287's own attribute, unprefixed, and advisory by its own definition. */
        val length: Long?,
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
                    length = attribute(parser, "length")?.toLongOrNull(),
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

    /** The entry-level `application/atom+xml` link, when it has the shape a section does. */
    private data class SectionLink(val href: String, val count: Int?)

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

        /**
         * This entry's `application/atom+xml` link, when it has exactly the shape an OPDS
         * 1.2 section entry does. `null` unless the entry carried no acquisition and did
         * carry this link -- never both, because a publication already answers [finished]
         * and a plain entry answers neither.
         */
        var sectionLink: SectionLink? = null

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
