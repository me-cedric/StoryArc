import Foundation
import Testing

@testable import StoryArcCore

/// Mirrors Android's `AnnotationExportTest`, assertion for assertion.
@Suite("Annotation export")
struct AnnotationExportTests {

    private func mark(
        _ text: String,
        chapter: String = "Chapter One",
        note: String = "",
        at progression: Double = 0.1
    ) -> Annotation {
        Annotation(
            locator: "{}",
            resource: "ch1.xhtml",
            progression: progression,
            chapter: chapter,
            text: text,
            note: note,
            createdAt: Date(timeIntervalSince1970: progression * 1000)
        )
    }

    @Test("Nothing marked exports nothing, rather than an empty heading")
    func emptyExportsEmpty() {
        #expect(AnnotationExport.document([], title: "Moby-Dick", format: .markdown).isEmpty)
        #expect(AnnotationExport.document([], title: "Moby-Dick", format: .plainText).isEmpty)
    }

    @Test("Markdown quotes the words and titles the publication")
    func markdownQuotes() {
        let out = AnnotationExport.document([mark("Call me Ishmael")],
                                            title: "Moby-Dick", format: .markdown)
        #expect(out.contains("# Moby-Dick"))
        #expect(out.contains("## Chapter One"))
        #expect(out.contains("> Call me Ishmael"))
    }

    @Test("Plain text uses quotation marks, not Markdown's")
    func plainTextQuotes() {
        let out = AnnotationExport.document([mark("Call me Ishmael")],
                                            title: "Moby-Dick", format: .plainText)
        #expect(out.contains("“Call me Ishmael”"))
        #expect(!out.contains("#"))
        #expect(!out.contains(">"))
    }

    @Test("A note is written under the words it is about")
    func noteFollowsItsQuotation() {
        let out = AnnotationExport.document([mark("Call me Ishmael", note: "The famous opening")],
                                            title: "Moby-Dick", format: .markdown)
        let quote = try? #require(out.range(of: "> Call me Ishmael"))
        let note = try? #require(out.range(of: "The famous opening"))
        #expect(quote != nil && note != nil)
        if let quote, let note { #expect(quote.upperBound < note.lowerBound) }
    }

    @Test("A chapter is named once, however many marks it holds")
    func chapterHeadingIsNotRepeated() {
        let out = AnnotationExport.document(
            [mark("first", at: 0.1), mark("second", at: 0.2)],
            title: "Moby-Dick", format: .markdown
        )
        #expect(out.components(separatedBy: "## Chapter One").count - 1 == 1)
    }

    @Test("Chapters come out in reading order, not in the order they were marked")
    func chaptersAreOrdered() {
        let out = AnnotationExport.document(
            [mark("later", chapter: "Chapter Two", at: 0.8),
             mark("earlier", chapter: "Chapter One", at: 0.2)],
            title: "Moby-Dick", format: .plainText
        )
        let one = try? #require(out.range(of: "Chapter One"))
        let two = try? #require(out.range(of: "Chapter Two"))
        if let one, let two { #expect(one.lowerBound < two.lowerBound) }
    }

    @Test("A mark the publication never named a chapter for gets no invented heading")
    func unnamedChapterGetsNoHeading() {
        let out = AnnotationExport.document([mark("orphan", chapter: "")],
                                            title: "Moby-Dick", format: .markdown)
        #expect(!out.contains("## \n"))
        #expect(out.contains("> orphan"))
    }

    @Test("A highlight with nothing written on it is not a note")
    func highlightIsNotANote() {
        #expect(!mark("words").hasNote)
        #expect(!mark("words", note: "   ").hasNote)
        #expect(mark("words", note: "something").hasNote)
    }
}
