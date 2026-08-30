package app.storyarc.core.format

/** One item in a publication's reading order. */
data class EpubSpineItem(
    /** Path inside the container, resolved against the package document. */
    val href: String,
    val mediaType: String,
    /** EPUB 3 lets a single item opt out of the publication's layout. */
    val isFixedLayout: Boolean?,
)

/** One entry in the table of contents, from a nav document or an NCX. */
data class EpubTocEntry(
    val title: String,
    val href: String,
    val children: List<EpubTocEntry> = emptyList(),
)

/** What a publication says about itself. */
data class EpubMetadata(
    val title: String?,
    val author: String?,
    val language: String?,
    val identifier: String?,
    /** Who published it, which `publication-formats` asks to be read like any other field. */
    val publisher: String? = null,
    /** The publisher's own blurb, shown on a publication's detail screen. */
    val description: String? = null,
    /**
     * The series it belongs to, and where in it.
     *
     * EPUB 3 states this as a `belongs-to-collection` refined by `collection-type="series"`
     * and `group-position`. EPUB 2 has no such thing, and Calibre's `calibre:series` meta
     * became the convention instead -- so both are read, and the EPUB 3 form wins where a
     * file carries both, because it is the one the format actually defines.
     */
    val series: String? = null,
    val seriesIndex: String? = null,
)

sealed class EpubException(message: String) : Exception(message) {
    /** Not an EPUB: the `mimetype` entry is missing or says something else. */
    class NotEpub : EpubException("not an epub")

    /** `META-INF/container.xml` is missing or names no root file. */
    class NoPackageDocument : EpubException("no package document")

    class Malformed(message: String) : EpubException(message)
}

/**
 * Reads an EPUB's structure: metadata, reading order, table of contents, cover.
 *
 * **Not a rendering engine.** Laying out reflowable XHTML with the typography
 * controls `ebook-reader` requires is Readium's job (ADR-0005) — writing one would
 * be the largest and least differentiated piece of work in the project.
 *
 * What this does instead is everything the *library* needs, which turns out to be
 * all of it except the rendering: an EPUB is a ZIP holding XML, so the container is
 * our own reader (ADR-0008) and the XML is parsed here. So a shelf of EPUBs can be
 * indexed — titles, authors, covers, chapter counts — with no dependency at all,
 * and Readium is needed only once someone opens one to read.
 *
 * The four combinations `publication-formats` promises — EPUB 2 and 3, reflowable
 * and fixed-layout — differ in exactly the places a parser gets wrong, so each is
 * handled explicitly rather than by assuming the modern shape: EPUB 2 has an NCX
 * where EPUB 3 has a nav document, and names its cover with a metadata `meta`
 * where EPUB 3 uses a manifest property.
 */
class EpubReader private constructor(
    private val reader: ZipReader,
    /** Internal rather than private for one read in `EpubSpineCover.kt`. */
    internal val pathToEntry: Map<String, ZipEntry>,
    /** The package document's path, which every other href resolves against. */
    val packagePath: String,
    val version: Int,
    val metadata: EpubMetadata,
    /** Reading order, as the spine declares it. */
    val spine: List<EpubSpineItem>,
    val toc: List<EpubTocEntry>,
    /** The cover image's path inside the container, when the publication names one. */
    val coverHref: String?,
    /**
     * True when the publication is pre-paginated.
     *
     * Drives which reader opens it: a fixed-layout EPUB is images with positions,
     * so `ebook-reader` requires the image reader and forbids offering typography
     * controls that cannot do anything.
     */
    val isFixedLayout: Boolean,
) {

    companion object {
        suspend fun open(source: RandomAccessSource): EpubReader {
            val reader = try {
                ZipReader.open(source)
            } catch (_: Exception) {
                throw EpubException.NotEpub()
            }
            val index = reader.entries.associateBy { it.path }

            // The container spec's one hard requirement, and the cheapest way to
            // tell an EPUB from any other ZIP before parsing XML.
            val mimetype = index["mimetype"] ?: throw EpubException.NotEpub()
            if (String(reader.data(mimetype)).trim() != "application/epub+zip") {
                throw EpubException.NotEpub()
            }

            val container = index["META-INF/container.xml"]
                ?: throw EpubException.NoPackageDocument()
            val packagePath = elements(String(reader.data(container)), "rootfile")
                .firstNotNullOfOrNull { it["full-path"] }
                ?: throw EpubException.NoPackageDocument()

            val packageEntry = index[packagePath] ?: throw EpubException.NoPackageDocument()
            val packageXml = String(reader.data(packageEntry))
            val base = directoryOf(packagePath)

            val items = mutableMapOf<String, Triple<String, String, String>>()
            for (element in elements(packageXml, "item")) {
                val id = element["id"] ?: continue
                val href = element["href"] ?: continue
                items[id] = Triple(
                    resolve(href, base),
                    element["media-type"] ?: "",
                    element["properties"] ?: "",
                )
            }

            val metas = elements(packageXml, "meta")
            val isFixedLayout = metas
                .firstOrNull { it["property"] == "rendition:layout" }
                ?.get("#text")?.trim() == "pre-paginated"

            val spine = elements(packageXml, "itemref").mapNotNull { element ->
                val item = items[element["idref"] ?: return@mapNotNull null]
                    ?: return@mapNotNull null
                // `rendition:layout-pre-paginated` on an itemref overrides the
                // publication's own layout for that one item.
                val properties = element["properties"] ?: ""
                val itemLayout = when {
                    properties.contains("rendition:layout-pre-paginated") -> true
                    properties.contains("rendition:layout-reflowable") -> false
                    else -> null
                }
                EpubSpineItem(item.first, item.second, itemLayout)
            }

            // EPUB 3 marks the cover with a manifest property; EPUB 2 names an item
            // id from a metadata meta. Both are checked, in that order, because a
            // version number is not a promise about which convention a file used.
            val coverHref = items.values.firstOrNull { it.third.contains("cover-image") }?.first
                ?: metas.firstOrNull { it["name"] == "cover" }?.get("content")
                    ?.let { items[it]?.first }

            val navHref = items.values.firstOrNull { it.third.contains("nav") }?.first
            // The NCX is reached through the spine's `toc` attribute, not by media
            // type — a publication may carry an NCX it does not use.
            val ncxHref = elements(packageXml, "spine").firstNotNullOfOrNull { it["toc"] }
                ?.let { items[it]?.first }
                ?: items.values
                    .firstOrNull { it.second == "application/x-dtbncx+xml" }?.first

            // Missing is not an error: a publication with no declared contents
            // still reads front to back.
            val toc = when {
                navHref != null && index[navHref] != null ->
                    parseNav(String(reader.data(index.getValue(navHref))), directoryOf(navHref))

                ncxHref != null && index[ncxHref] != null ->
                    parseNcx(String(reader.data(index.getValue(ncxHref))), directoryOf(ncxHref))

                else -> emptyList()
            }

            return EpubReader(
                reader = reader,
                pathToEntry = index,
                packagePath = packagePath,
                version = elements(packageXml, "package").firstNotNullOfOrNull { it["version"] }
                    ?.substringBefore('.')?.toIntOrNull() ?: 3,
                metadata = EpubMetadata(
                    title = textOf(packageXml, "dc:title") ?: textOf(packageXml, "title"),
                    author = textOf(packageXml, "dc:creator") ?: textOf(packageXml, "creator"),
                    language = textOf(packageXml, "dc:language") ?: textOf(packageXml, "language"),
                    identifier = textOf(packageXml, "dc:identifier")
                        ?: textOf(packageXml, "identifier"),
                    publisher = textOf(packageXml, "dc:publisher")
                        ?: textOf(packageXml, "publisher"),
                    description = textOf(packageXml, "dc:description")
                        ?: textOf(packageXml, "description"),
                    series = seriesOf(packageXml)?.first,
                    seriesIndex = seriesOf(packageXml)?.second,
                ),
                spine = spine,
                toc = toc,
                coverHref = coverHref,
                isFixedLayout = isFixedLayout,
            )
        }

        /** The EPUB 3 nav document: the `<nav epub:type="toc">` list. */
        /**
         * The series a publication belongs to, from whichever of the two conventions it uses.
         *
         * EPUB 3 states it as `<meta property="belongs-to-collection">`, refined elsewhere in
         * the document by `collection-type` and `group-position` keyed on the collection's
         * id. EPUB 2 states nothing, and Calibre's `<meta name="calibre:series">` filled the
         * gap so widely that a reader's library is mostly that. The defined form wins where
         * both are present; a file carrying both and disagreeing is a file whose publisher
         * knew better than its converter.
         */
        private fun seriesOf(xml: String): Pair<String, String?>? {
            val metas = elements(xml, "meta")

            val collection = metas.firstOrNull { it["property"] == "belongs-to-collection" }
            val declared = collection?.get("#text")?.trim()
            if (collection != null && !declared.isNullOrEmpty()) {
                val refines = collection["id"]?.let { "#$it" }
                val position = metas.firstOrNull {
                    it["property"] == "group-position" &&
                        (refines == null || it["refines"] == refines)
                }?.get("#text")?.trim()
                return declared to position?.takeIf { it.isNotEmpty() }
            }

            val calibre = metas.firstOrNull { it["name"] == "calibre:series" }
                ?.get("content")?.trim()
                ?: return null
            if (calibre.isEmpty()) return null
            val index = metas.firstOrNull { it["name"] == "calibre:series_index" }
                ?.get("content")?.trim()
            return calibre to index?.takeIf { it.isNotEmpty() }
        }

        private fun parseNav(xml: String, base: String): List<EpubTocEntry> {
            // Only anchors inside the toc nav count. A nav document may also carry
            // a landmarks or page-list nav, and treating those as chapters would
            // put "Start of content" in the table of contents.
            val start = xml.indexOf("epub:type=\"toc\"")
            val scoped = if (start < 0) {
                xml
            } else {
                val end = xml.indexOf("</nav>", start)
                if (end < 0) xml.substring(start) else xml.substring(start, end)
            }
            return anchors(scoped, base)
        }

        /** The EPUB 2 NCX: `navPoint` with a `navLabel/text` and a `content/@src`. */
        private fun parseNcx(xml: String, base: String): List<EpubTocEntry> {
            val entries = mutableListOf<EpubTocEntry>()
            var at = 0
            while (true) {
                val open = xml.indexOf("<navPoint", at)
                if (open < 0) break
                val close = xml.indexOf("</navPoint>", open)
                val block = if (close < 0) xml.substring(open) else xml.substring(open, close)
                at = if (close < 0) xml.length else close + 1
                val label = between(block, "<text>", "</text>")?.trim()
                val src = elements(block, "content").firstNotNullOfOrNull { it["src"] }
                if (!label.isNullOrEmpty() && src != null) {
                    entries += EpubTocEntry(label, resolve(src, base))
                }
            }
            return entries
        }

        private fun anchors(xml: String, base: String): List<EpubTocEntry> {
            val entries = mutableListOf<EpubTocEntry>()
            var at = 0
            while (true) {
                val open = xml.indexOf("<a ", at)
                if (open < 0) break
                val close = xml.indexOf("</a>", open)
                if (close < 0) break
                val element = xml.substring(open, close + 4)
                at = close + 4
                val href = elements(element, "a").firstNotNullOfOrNull { it["href"] } ?: continue
                val title = between(element, ">", "</a>")?.trim()
                if (!title.isNullOrEmpty()) {
                    entries += EpubTocEntry(title, resolve(href, base))
                }
            }
            return entries
        }

        // Minimal XML reading.
        //
        // ponytail: attribute scraping rather than a DOM. An EPUB package document
        // is a flat list of elements with attributes, and the fields needed here
        // are named unambiguously — so a DocumentBuilder and a tree walk would be
        // more code for the same answers. If nested structure is ever needed (a
        // hierarchical table of contents, say), switch to an XML parser rather than
        // growing this. iOS's EpubReader.swift carries the same note.

        /** Every element with a given local name, its attributes, and its text. */
        private fun elements(xml: String, name: String): List<Map<String, String>> {
            val found = mutableListOf<Map<String, String>>()
            var at = 0
            while (true) {
                val open = xml.indexOf("<$name", at)
                if (open < 0) break
                val after = open + name.length + 1
                at = after
                // Guard against `<items>` matching a search for `<item>`.
                if (after < xml.length && (xml[after].isLetterOrDigit())) continue
                val end = xml.indexOf('>', after)
                if (end < 0) break
                val attributes = parseAttributes(xml.substring(after, end)).toMutableMap()
                val closing = xml.indexOf("</$name>", end)
                if (closing >= 0) attributes["#text"] = xml.substring(end + 1, closing)
                found += attributes
                at = end + 1
            }
            return found
        }

        private fun textOf(xml: String, name: String): String? =
            elements(xml, name).firstOrNull()?.get("#text")?.trim()?.takeIf { it.isNotEmpty() }

        private fun parseAttributes(fragment: String): Map<String, String> {
            val attributes = mutableMapOf<String, String>()
            var at = 0
            while (true) {
                val equals = fragment.indexOf('=', at)
                if (equals < 0) break
                val name = fragment.substring(at, equals).trim().trim('/', '?')
                if (equals + 1 >= fragment.length) break
                val quote = fragment[equals + 1]
                if (quote != '"' && quote != '\'') break
                val closing = fragment.indexOf(quote, equals + 2)
                if (closing < 0) break
                if (name.isNotEmpty() && !name.contains(' ')) {
                    attributes[name] = unescape(fragment.substring(equals + 2, closing))
                }
                at = closing + 1
            }
            return attributes
        }

        private fun between(text: String, from: String, to: String): String? {
            val start = text.indexOf(from)
            if (start < 0) return null
            val end = text.indexOf(to, start + from.length)
            if (end < 0) return null
            return text.substring(start + from.length, end)
        }

        /**
         * The five predefined XML entities. An EPUB title with an ampersand in it
         * is ordinary, and showing `&amp;` in a library is not.
         */
        private fun unescape(value: String): String = value
            .replace("&lt;", "<")
            .replace("&gt;", ">")
            .replace("&quot;", "\"")
            .replace("&apos;", "'")
            .replace("&amp;", "&")

        private fun directoryOf(path: String): String = path.substringBeforeLast('/', "")

        /**
         * An href relative to the document that declared it, with any fragment
         * dropped — a table of contents entry may point at an anchor inside a file.
         */
        private fun resolve(href: String, base: String): String {
            val withoutFragment = href.substringBefore('#')
            if (withoutFragment.startsWith("/")) return withoutFragment.removePrefix("/")
            if (base.isEmpty()) return withoutFragment

            val segments = base.split('/').toMutableList()
            for (part in withoutFragment.split('/')) {
                when (part) {
                    "." -> Unit
                    ".." -> if (segments.isNotEmpty()) segments.removeAt(segments.lastIndex)
                    else -> segments += part
                }
            }
            return segments.joinToString("/")
        }
    }

    /** One item's bytes, by its container path. */
    suspend fun data(href: String): ByteArray {
        val entry = pathToEntry[href] ?: throw EpubException.Malformed("no entry at $href")
        return reader.data(entry)
    }

    /** The cover image's bytes, when the publication has one. */
    suspend fun coverData(): ByteArray? =
        coverHref?.let { runCatching { data(it) }.getOrNull() }
}
