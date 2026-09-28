internal import Formats

/// A PDF's own outline, read as chapter starts. iOS only — PDFKit reads an outline
/// and Android's PDF API exposes none (ADR-0012), which is why `comic-reader`'s D4
/// treats this as the platform's own half of the rule and Android uses `ComicInfo`
/// alone.
enum PdfOutlineChapters {
    /// Every page an outline entry resolves to, flattened from the whole tree and
    /// sorted. A nested entry is still a place in the document a reader can jump
    /// to, and the previous/next actions do not need the outline's own hierarchy —
    /// only where each entry lands.
    static func startIndices(_ items: [PdfOutlineItem]) -> [Int] {
        Set(flattened(items).compactMap(\.pageIndex)).sorted()
    }

    private static func flattened(_ items: [PdfOutlineItem]) -> [PdfOutlineItem] {
        items.flatMap { [$0] + flattened($0.children) }
    }
}
