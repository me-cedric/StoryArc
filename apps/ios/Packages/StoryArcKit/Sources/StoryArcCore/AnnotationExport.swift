public import Foundation

/// Turning what a reader marked into something they can keep.
///
/// `ebook-reader`: highlights and notes are "exportable as plain text or Markdown". Both,
/// from the one list, because a reader pasting into a message wants neither asterisks nor
/// a lost structure, and a reader pasting into their notes app wants the structure.
///
/// A pure function over the records rather than a view that builds a string: this is the
/// part worth asserting, and it is the part that has to read the same on both platforms.
///
/// Android's `AnnotationExport` writes the same documents.
public enum AnnotationExport {

    public enum Format: String, Sendable, CaseIterable {
        case plainText
        case markdown
    }

    /// The whole list, grouped under the chapters it falls in.
    ///
    /// Grouped rather than a flat run, because a quotation without its chapter is a
    /// quotation a reader cannot place again. Chapters appear in reading order and their
    /// marks with them; a mark whose chapter the publication never named is filed under
    /// nothing rather than under an invented heading.
    public static func document(
        _ annotations: [Annotation],
        title: String,
        format: Format
    ) -> String {
        let ordered = annotations.inReadingOrder
        guard !ordered.isEmpty else { return "" }

        var lines: [String] = []
        lines.append(format == .markdown ? "# \(title)" : title)
        lines.append("")

        var chapter: String?
        for annotation in ordered {
            if annotation.chapter != chapter {
                chapter = annotation.chapter
                if !annotation.chapter.isEmpty {
                    lines.append(format == .markdown ? "## \(annotation.chapter)" : annotation.chapter)
                    lines.append("")
                }
            }
            lines.append(contentsOf: entry(annotation, format: format))
            lines.append("")
        }

        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    private static func entry(_ annotation: Annotation, format: Format) -> [String] {
        var lines: [String] = []
        switch format {
        case .markdown:
            // A block quote, because that is what a quotation is in Markdown, and it
            // survives being pasted somewhere that renders it.
            lines.append("> \(annotation.text)")
            if annotation.hasNote {
                lines.append("")
                lines.append(annotation.note)
            }
        case .plainText:
            // Typographic quotes rather than Markdown's marks: this format exists for
            // somewhere that will not render anything.
            lines.append("“\(annotation.text)”")
            if annotation.hasNote {
                lines.append(annotation.note)
            }
        }
        return lines
    }
}
