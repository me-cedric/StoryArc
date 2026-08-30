public import Foundation

// What an EPUB says about itself.
//
// Split out of `EpubReader.swift`, which had reached the 400-line cap this project
// enforces, when `publication-formats`' publisher, description and series were added. The
// division is not arbitrary: this file is what a publication *is*, and the reader is how it
// is got at.

public struct EpubMetadata: Sendable, Equatable {
    public let title: String?
    public let author: String?
    public let language: String?
    public let identifier: String?
    /// Who published it, which `publication-formats` asks to be read like any other field.
    public let publisher: String?
    /// The publisher's own blurb, shown on a publication's detail screen.
    public let description: String?
    /// The series it belongs to, and where in it.
    ///
    /// EPUB 3 states this as a `belongs-to-collection` refined by `collection-type="series"`
    /// and `group-position`. EPUB 2 has no such thing, and Calibre's `calibre:series` meta
    /// became the convention instead — so both are read, and the EPUB 3 form wins where a
    /// file carries both, because it is the one the format actually defines.
    public let series: String?
    public let seriesIndex: String?

    public init(
        title: String? = nil,
        author: String? = nil,
        language: String? = nil,
        identifier: String? = nil,
        publisher: String? = nil,
        description: String? = nil,
        series: String? = nil,
        seriesIndex: String? = nil
    ) {
        self.title = title
        self.author = author
        self.language = language
        self.identifier = identifier
        self.publisher = publisher
        self.description = description
        self.series = series
        self.seriesIndex = seriesIndex
    }
}

extension EpubReader {
    /// The series a publication belongs to, from whichever of the two conventions it uses.
    ///
    /// EPUB 3 states it as `<meta property="belongs-to-collection">`, refined elsewhere in
    /// the document by `collection-type` and `group-position` keyed on the collection's id.
    /// EPUB 2 states nothing, and Calibre's `<meta name="calibre:series">` filled the gap so
    /// widely that a reader's library is mostly that. The defined form wins where both are
    /// present; a file carrying both and disagreeing is a file whose publisher knew better
    /// than its converter.
    static func series(in elements: Elements) -> (name: String, position: String?)? {
        let metas = elements.named("meta")

        if let collection = metas.first(where: { $0["property"] == "belongs-to-collection" }),
           let name = collection["#text"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            let id = collection["id"]
            let refines = id.map { "#\($0)" }
            let position = metas.first {
                $0["property"] == "group-position" && (refines == nil || $0["refines"] == refines)
            }?["#text"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (name, position?.isEmpty == false ? position : nil)
        }

        guard let calibre = metas.first(where: { $0["name"] == "calibre:series" }),
              let name = calibre["content"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty
        else { return nil }
        let index = metas.first { $0["name"] == "calibre:series_index" }?["content"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (name, index?.isEmpty == false ? index : nil)
    }
}
