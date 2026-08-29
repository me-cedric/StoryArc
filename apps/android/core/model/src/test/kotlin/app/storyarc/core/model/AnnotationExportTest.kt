package app.storyarc.core.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Mirrors iOS's `AnnotationExportTests`, assertion for assertion. */
class AnnotationExportTest {

    private fun mark(
        text: String,
        chapter: String = "Chapter One",
        note: String = "",
        progression: Double = 0.1,
    ) = Annotation(
        id = "$text-$progression",
        locator = "{}",
        resource = "ch1.xhtml",
        progression = progression,
        chapter = chapter,
        text = text,
        note = note,
        createdAtEpochMillis = (progression * 1000).toLong(),
    )

    @Test
    fun `nothing marked exports nothing, rather than an empty heading`() {
        assertTrue(AnnotationExport.document(emptyList(), "Moby-Dick", AnnotationExport.Format.MARKDOWN).isEmpty())
        assertTrue(AnnotationExport.document(emptyList(), "Moby-Dick", AnnotationExport.Format.PLAIN_TEXT).isEmpty())
    }

    @Test
    fun `markdown quotes the words and titles the publication`() {
        val out = AnnotationExport.document(
            listOf(mark("Call me Ishmael")), "Moby-Dick", AnnotationExport.Format.MARKDOWN,
        )
        assertTrue(out.contains("# Moby-Dick"))
        assertTrue(out.contains("## Chapter One"))
        assertTrue(out.contains("> Call me Ishmael"))
    }

    @Test
    fun `plain text uses quotation marks, not markdown's`() {
        val out = AnnotationExport.document(
            listOf(mark("Call me Ishmael")), "Moby-Dick", AnnotationExport.Format.PLAIN_TEXT,
        )
        assertTrue(out.contains("“Call me Ishmael”"))
        assertFalse(out.contains("#"))
        assertFalse(out.contains(">"))
    }

    @Test
    fun `a note is written under the words it is about`() {
        val out = AnnotationExport.document(
            listOf(mark("Call me Ishmael", note = "The famous opening")),
            "Moby-Dick", AnnotationExport.Format.MARKDOWN,
        )
        assertTrue(out.indexOf("> Call me Ishmael") < out.indexOf("The famous opening"))
    }

    @Test
    fun `a chapter is named once, however many marks it holds`() {
        val out = AnnotationExport.document(
            listOf(mark("first", progression = 0.1), mark("second", progression = 0.2)),
            "Moby-Dick", AnnotationExport.Format.MARKDOWN,
        )
        assertEquals(1, out.split("## Chapter One").size - 1)
    }

    @Test
    fun `chapters come out in reading order, not in the order they were marked`() {
        val out = AnnotationExport.document(
            listOf(
                mark("later", chapter = "Chapter Two", progression = 0.8),
                mark("earlier", chapter = "Chapter One", progression = 0.2),
            ),
            "Moby-Dick", AnnotationExport.Format.PLAIN_TEXT,
        )
        assertTrue(out.indexOf("Chapter One") < out.indexOf("Chapter Two"))
    }

    @Test
    fun `a mark the publication never named a chapter for gets no invented heading`() {
        val out = AnnotationExport.document(
            listOf(mark("orphan", chapter = "")), "Moby-Dick", AnnotationExport.Format.MARKDOWN,
        )
        assertFalse(out.contains("## \n"))
        assertTrue(out.contains("> orphan"))
    }

    @Test
    fun `a highlight with nothing written on it is not a note`() {
        assertFalse(mark("words").hasNote)
        assertFalse(mark("words", note = "   ").hasNote)
        assertTrue(mark("words", note = "something").hasNote)
    }
}
