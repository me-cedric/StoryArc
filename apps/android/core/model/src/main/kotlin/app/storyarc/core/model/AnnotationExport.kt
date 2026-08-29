package app.storyarc.core.model

/**
 * Turning what a reader marked into something they can keep.
 *
 * `ebook-reader`: highlights and notes are "exportable as plain text or Markdown". Both, from
 * the one list, because a reader pasting into a message wants neither asterisks nor a lost
 * structure, and a reader pasting into their notes app wants the structure.
 *
 * A pure function over the records rather than a view that builds a string: this is the part
 * worth asserting, and it is the part that has to read the same on both platforms.
 *
 * iOS's `AnnotationExport` writes the same documents.
 */
object AnnotationExport {

    enum class Format { PLAIN_TEXT, MARKDOWN }

    /**
     * The whole list, grouped under the chapters it falls in.
     *
     * Grouped rather than a flat run, because a quotation without its chapter is a quotation
     * a reader cannot place again. Chapters appear in reading order and their marks with
     * them; a mark whose chapter the publication never named is filed under nothing rather
     * than under an invented heading.
     */
    fun document(annotations: List<Annotation>, title: String, format: Format): String {
        val ordered = annotations.inReadingOrder()
        if (ordered.isEmpty()) return ""

        val lines = mutableListOf<String>()
        lines += if (format == Format.MARKDOWN) "# $title" else title
        lines += ""

        var chapter: String? = null
        for (annotation in ordered) {
            if (annotation.chapter != chapter) {
                chapter = annotation.chapter
                if (annotation.chapter.isNotEmpty()) {
                    lines += if (format == Format.MARKDOWN) "## ${annotation.chapter}" else annotation.chapter
                    lines += ""
                }
            }
            lines += entry(annotation, format)
            lines += ""
        }

        return lines.joinToString("\n").trim() + "\n"
    }

    private fun entry(annotation: Annotation, format: Format): List<String> = buildList {
        when (format) {
            // A block quote, because that is what a quotation is in Markdown, and it
            // survives being pasted somewhere that renders it.
            Format.MARKDOWN -> {
                add("> ${annotation.text}")
                if (annotation.hasNote) {
                    add("")
                    add(annotation.note)
                }
            }
            // Typographic quotes rather than Markdown's marks: this format exists for
            // somewhere that will not render anything.
            Format.PLAIN_TEXT -> {
                add("“${annotation.text}”")
                if (annotation.hasNote) add(annotation.note)
            }
        }
    }
}
