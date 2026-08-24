package app.storyarc.core.format

/**
 * Series, volume, issue and year guessed from a filename.
 *
 * `publication-formats` requires this when a publication carries no embedded
 * metadata, and requires the results to be **marked as inferred**: a later
 * authoritative source — a Kavita server, an OPDS catalogue, a `ComicInfo.xml`
 * added afterwards — must be able to replace a guess without asking the user to
 * resolve a conflict it invented.
 *
 * So [isInferred] is always true here. The flag lives on the type rather than at
 * the call site because it travels with the values, and a guess that loses its
 * label becomes indistinguishable from a fact.
 */
data class FilenameMetadata(
    val series: String?,
    /**
     * Issue or chapter. A string for the same reason [ComicInfo.number] is one:
     * "3.5" is a real issue number.
     */
    val number: String?,
    val volume: Int?,
    val year: Int?,
) {
    /** Always true. Every value here is a guess, and the point is that it says so. */
    val isInferred: Boolean = true

    companion object {
        private val BRACKETED = listOf(Regex("""\[[^]]*]"""), Regex("""\{[^}]*}"""))
        private val PARENTHESISED_YEAR = Regex("""\((\d{4})\)""")
        private val VOLUME = Regex("""\bv(?:ol)?\.?\s*(\d{1,4})\b""", RegexOption.IGNORE_CASE)
        private val PARENTHESISED_VOLUME = Regex("""\(v(\d{1,4})\)""", RegexOption.IGNORE_CASE)
        private val NUMBER_PATTERNS = listOf(
            Regex("""#\s*(\d{1,5}(?:\.\d+)?)"""),
            Regex("""\bc(?:h(?:apter)?)?\.?\s*(\d{1,5}(?:\.\d+)?)\b""", RegexOption.IGNORE_CASE),
            // A trailing bare number, capped at three digits. Four is where a
            // number stops looking like an issue and starts looking like part of
            // the title: "Blame! 2001" is a series, not issue 2001 of "Blame!".
            //
            // ponytail: the ceiling is that a four-digit chapter needs an explicit
            // marker — "c1044", not "1044". Every naming convention that goes that
            // high uses one, so the guess stays on the safe side of a title.
            Regex("""\s(\d{1,3}(?:\.\d+)?)\s*$"""),
        )
        private const val TRIM_CHARS = " -–—_#.,:;()"

        /**
         * Reads what a filename implies. The extension is ignored, and a name that
         * implies nothing yields a series and nothing else.
         *
         * ponytail: an ordered set of patterns over one string, not a grammar.
         * Comic filenames have no syntax to parse — they have conventions, and the
         * honest model of a convention is a list of shapes tried in order. The
         * cases the list must handle live in the shared corpus manifest, so both
         * platforms agree on what "common naming pattern" means.
         */
        fun of(filename: String): FilenameMetadata {
            // A dotfile is not a publication, and stripping an extension leaves
            // ".cbz" intact — which would be read as a series called "cbz".
            if (filename.startsWith(".")) return FilenameMetadata(null, null, null, null)

            var stem = filename.substringBeforeLast('.', filename)

            // Bracketed groups — scanlation credits, quality tags, language tags —
            // are never part of a title, and leaving them in makes every file from
            // one group look like a different series.
            for (pattern in BRACKETED) stem = pattern.replace(stem, " ")

            // The year first, and only from parentheses. A bare four-digit number
            // is ambiguous: "Blame! 2001" is a title. Parentheses are what make it
            // a claim about a date.
            //
            // Last match rather than first: a title may contain parentheses of its
            // own, and the publication year conventionally comes after the title.
            var year: Int? = null
            val yearMatch = PARENTHESISED_YEAR.findAll(stem).lastOrNull { match ->
                match.groupValues[1].toIntOrNull()?.let { it in 1900..2200 } == true
            }
            if (yearMatch != null) {
                year = yearMatch.groupValues[1].toInt()
                stem = stem.replaceRange(yearMatch.range, " ")
            }

            // Volume, before the issue number: `v02` and `Vol. 3` would otherwise
            // be read as issues.
            var volume: Int? = null
            for (pattern in listOf(VOLUME, PARENTHESISED_VOLUME)) {
                val match = pattern.find(stem) ?: continue
                volume = match.groupValues[1].toIntOrNull()
                stem = stem.replaceRange(match.range, " ")
                break
            }

            // The issue or chapter, most explicit marker first. A trailing bare
            // number is last, because it is the weakest signal and the one that
            // misreads a title.
            var number: String? = null
            for (pattern in NUMBER_PATTERNS) {
                val match = pattern.find(stem) ?: continue
                number = trimLeadingZeros(match.groupValues[1])
                stem = stem.replaceRange(match.range, " ")
                break
            }

            return FilenameMetadata(tidySeries(stem), number, volume, year)
        }

        private fun trimLeadingZeros(value: String): String {
            // "#01" and "#1" are the same issue, and a library that sorts them
            // apart looks broken. A value that is all zeros stays "0".
            val trimmed = value.trimStart('0')
            return when {
                trimmed.isEmpty() -> "0"
                trimmed.startsWith('.') -> value
                else -> trimmed
            }
        }

        /** What is left after the markers are removed, as a title. */
        private fun tidySeries(text: String): String? {
            // Separators left dangling by a removed marker: "One Piece - " and
            // "Invincible #" should both come back as the title alone.
            val tidied = text.replace(Regex("""\s+"""), " ").trim { it in TRIM_CHARS }
            return tidied.ifEmpty { null }
        }
    }
}
