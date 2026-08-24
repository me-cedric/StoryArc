package app.storyarc.core.format

import app.storyarc.core.model.ReadingDirection

/**
 * The metadata a comic archive carries in `ComicInfo.xml`.
 *
 * `publication-formats` names thirteen fields plus a reading direction, and this is
 * all of them. The format is the de-facto ComicRack schema that every comic tool
 * writes: a flat list of elements, plus an optional `<Pages>` list that can
 * designate a cover other than page 1 and mark double-page spreads.
 *
 * Every field is nullable, because every field is optional in practice. A file with
 * only `<Series>` is common, and a parser that requires more of them finds nothing
 * in a real library.
 */
data class ComicInfo(
    val series: String?,
    /**
     * Issue or chapter number. A string, not a number: "3.5" and "Annual 1" are
     * both real, and rounding either loses the publication's identity.
     */
    val number: String?,
    val volume: Int?,
    val title: String?,
    val summary: String?,
    /** `ComicInfo` allows a comma-separated list in every creator field. */
    val writers: List<String>,
    val pencillers: List<String>,
    val publisher: String?,
    val year: Int?,
    val month: Int?,
    val day: Int?,
    /**
     * The publisher's own page count. Treated as a claim, not a fact — the
     * archive's actual page list is the authority.
     */
    val pageCount: Int?,
    val language: String?,
    /**
     * The direction the publication declares, or `null` when it declares none.
     *
     * `Manga=YesAndRightToLeft` is a declaration. `Manga=Yes` is **not**: it says
     * the publication is manga, which is not the same as saying which way it reads,
     * and plenty of manga are published left-to-right in translation. So `Yes`
     * falls through to the language rule rather than assuming.
     */
    val declaredDirection: ReadingDirection?,
    /**
     * Where the cover is, when `<Pages>` designates one that is not the first.
     *
     * An index into the archive's page list, so `publication-formats`'s "the first
     * page in reading order becomes the cover unless `ComicInfo.xml` designates a
     * different one" has something to act on.
     */
    val coverPageIndex: Int?,
    /**
     * Pages `<Pages>` marks as double-page spreads.
     *
     * Believed in preference to guessing from aspect ratio: [PageDecoder.isSpread]
     * is a heuristic and this is a statement.
     */
    val doublePageIndices: List<Int>,
) {
    /**
     * The direction the reader should open in.
     *
     * Resolved with the domain's own rule so the format layer does not get a second
     * opinion about it: an explicit declaration wins, otherwise Japanese opens
     * right-to-left.
     */
    val readingDirection: ReadingDirection
        get() = ReadingDirection.inferred(declaredDirection, language)

    companion object {
        /**
         * Parses `ComicInfo.xml`. Returns `null` only when the bytes are not
         * ComicInfo at all — a file with no recognised fields still yields an empty
         * [ComicInfo], because "present but empty" and "absent" are different
         * states.
         */
        fun parse(data: ByteArray): ComicInfo? {
            val text = String(data, Charsets.UTF_8).let {
                if (it.contains('�')) String(data, Charsets.ISO_8859_1) else it
            }
            if (!text.contains("<ComicInfo")) return null

            fun value(name: String): String? =
                element(name, text)?.trim()?.takeIf { it.isNotEmpty() }?.let(::unescape)

            fun list(name: String): List<String> =
                (value(name) ?: "").split(',').map { it.trim() }.filter { it.isNotEmpty() }

            var cover: Int? = null
            val spreads = mutableListOf<Int>()
            for (attributes in pageElements(text)) {
                val index = attributes["Image"]?.toIntOrNull() ?: continue
                if (attributes["Type"] == "FrontCover" && cover == null) cover = index
                if (attributes["DoublePage"]?.lowercase() == "true") spreads += index
            }

            return ComicInfo(
                series = value("Series"),
                number = value("Number"),
                volume = value("Volume")?.toIntOrNull(),
                title = value("Title"),
                summary = value("Summary"),
                writers = list("Writer"),
                pencillers = list("Penciller"),
                publisher = value("Publisher"),
                year = value("Year")?.toIntOrNull(),
                month = value("Month")?.toIntOrNull(),
                day = value("Day")?.toIntOrNull(),
                pageCount = value("PageCount")?.toIntOrNull(),
                language = value("LanguageISO") ?: value("Language"),
                declaredDirection = when (value("Manga")?.lowercase()) {
                    "yesandrighttoleft" -> ReadingDirection.RIGHT_TO_LEFT
                    "no" -> ReadingDirection.LEFT_TO_RIGHT
                    else -> null
                },
                // Index 0 is the default, so designating it carries no information
                // and is dropped — otherwise every well-formed file would look like
                // an override.
                coverPageIndex = cover?.takeIf { it != 0 },
                doublePageIndices = spreads.sorted(),
            )
        }

        // Minimal XML reading.
        //
        // ponytail: the same scraping [EpubReader] uses, for the same reason —
        // ComicInfo is a flat list of uniquely-named elements, so a real parser
        // would be more code for identical answers. The one nested structure,
        // `<Pages>`, is a list of self-closing elements with attributes, which is
        // the easy case.

        private fun element(name: String, text: String): String? {
            val open = text.indexOf("<$name>")
            if (open < 0) return null
            val close = text.indexOf("</$name>", open)
            if (close < 0) return null
            return text.substring(open + name.length + 2, close)
        }

        private fun pageElements(text: String): List<Map<String, String>> {
            val found = mutableListOf<Map<String, String>>()
            var at = 0
            while (true) {
                val open = text.indexOf("<Page ", at)
                if (open < 0) break
                val end = text.indexOf('>', open)
                if (end < 0) break
                found += attributes(text.substring(open + 6, end))
                at = end + 1
            }
            return found
        }

        private fun attributes(fragment: String): Map<String, String> {
            val attributes = mutableMapOf<String, String>()
            var at = 0
            while (true) {
                val equals = fragment.indexOf('=', at)
                if (equals < 0) break
                val name = fragment.substring(at, equals).trim().trim('/')
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

        /**
         * The five predefined XML entities. A summary with an ampersand in it is
         * ordinary, and showing `&amp;` in a library is not.
         */
        private fun unescape(value: String): String = value
            .replace("&lt;", "<")
            .replace("&gt;", ">")
            .replace("&quot;", "\"")
            .replace("&apos;", "'")
            .replace("&amp;", "&")
    }
}
