public import Foundation

public import StoryArcCore

/// The metadata a comic archive carries in `ComicInfo.xml`.
///
/// `publication-formats` names thirteen fields plus a reading direction, and this
/// is all of them. The format is the de-facto ComicRack schema that every comic
/// tool writes: a flat list of elements, plus an optional `<Pages>` list that can
/// designate a cover other than page 1 and mark double-page spreads.
///
/// Every field is optional, because every field is optional in practice. A file
/// with only `<Series>` is common, and a parser that requires more of them finds
/// nothing in a real library.
public struct ComicInfo: Sendable, Equatable {
    public let series: String?
    /// Issue or chapter number. A string, not a number: "3.5" and "Annual 1" are
    /// both real, and rounding either loses the publication's identity.
    public let number: String?
    public let volume: Int?
    public let title: String?
    public let summary: String?
    /// `ComicInfo` allows a comma-separated list in every creator field.
    public let writers: [String]
    public let pencillers: [String]
    public let publisher: String?
    public let year: Int?
    public let month: Int?
    public let day: Int?
    /// The publisher's own page count. Treated as a claim, not a fact — the
    /// archive's actual page list is the authority.
    public let pageCount: Int?
    public let language: String?

    /// `<Genre>` — the shelf the publication belongs on, comma-separated.
    ///
    /// The schema has always defined it and this parser did not read it, which is
    /// why `library-browsing`'s genre filter had nothing to filter on. Comma-split
    /// like every other list field in ComicRack's format.
    public let genres: [String]
    /// `<Tags>` — whatever else the cataloguer recorded, comma-separated.
    ///
    /// Kept apart from ``genres`` because the file keeps them apart and the reader
    /// filters on them separately.
    public let tags: [String]

    /// The direction the publication declares, or `nil` when it declares none.
    ///
    /// `Manga=YesAndRightToLeft` is a declaration. `Manga=Yes` is **not**: it says
    /// the publication is manga, which is not the same as saying which way it
    /// reads, and plenty of manga are published left-to-right in translation. So
    /// `Yes` falls through to the language rule rather than assuming.
    public let declaredDirection: ReadingDirection?

    /// Where the cover is, when `<Pages>` designates one that is not the first.
    ///
    /// An index into the archive's page list, so `publication-formats`'s "the
    /// first page in reading order becomes the cover unless `ComicInfo.xml`
    /// designates a different one" has something to act on.
    public let coverPageIndex: Int?

    /// Pages `<Pages>` marks as double-page spreads.
    ///
    /// Believed in preference to guessing from aspect ratio: `PageDecoder.isSpread`
    /// is a heuristic and this is a statement.
    public let doublePageIndices: [Int]

    /// The direction the reader should open in.
    ///
    /// Resolved with the domain's own rule so the format layer does not get a
    /// second opinion about it: an explicit declaration wins, otherwise Japanese
    /// opens right-to-left.
    public var readingDirection: ReadingDirection {
        ReadingDirection.inferred(declared: declaredDirection, languageCode: language)
    }

    /// Parses `ComicInfo.xml`. Returns `nil` only when the bytes are not XML at
    /// all — a file with no recognised fields still yields an empty `ComicInfo`,
    /// because "present but empty" and "absent" are different states.
    public init?(data: Data) {
        guard let text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1),
              text.contains("<ComicInfo")
        else { return nil }

        func value(_ name: String) -> String? {
            guard let raw = Self.element(name, in: text) else { return nil }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : Self.unescape(trimmed)
        }
        func list(_ name: String) -> [String] {
            (value(name) ?? "")
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }

        self.series = value("Series")
        self.number = value("Number")
        self.volume = value("Volume").flatMap(Int.init)
        self.title = value("Title")
        self.summary = value("Summary")
        self.writers = list("Writer")
        self.pencillers = list("Penciller")
        self.publisher = value("Publisher")
        self.year = value("Year").flatMap(Int.init)
        self.month = value("Month").flatMap(Int.init)
        self.day = value("Day").flatMap(Int.init)
        self.pageCount = value("PageCount").flatMap(Int.init)
        self.language = value("LanguageISO") ?? value("Language")
        self.genres = list("Genre")
        self.tags = list("Tags")

        switch value("Manga")?.lowercased() {
        case "yesandrighttoleft": self.declaredDirection = .rightToLeft
        case "no": self.declaredDirection = .leftToRight
        default: self.declaredDirection = nil
        }

        // `<Page Image="n" .../>` — the attribute is the page's index, which is
        // not necessarily its position in the list.
        var cover: Int?
        var spreads: [Int] = []
        for attributes in Self.pageElements(in: text) {
            guard let index = attributes["Image"].flatMap(Int.init) else { continue }
            if attributes["Type"] == "FrontCover", cover == nil { cover = index }
            if attributes["DoublePage"]?.lowercased() == "true" { spreads.append(index) }
        }
        // Index 0 is the default, so designating it carries no information and is
        // dropped — otherwise every well-formed file would look like an override.
        self.coverPageIndex = cover == 0 ? nil : cover
        self.doublePageIndices = spreads.sorted()
    }

    // MARK: - Minimal XML reading
    //
    // ponytail: the same attribute-and-element scraping `EpubReader` uses, for the
    // same reason — ComicInfo is a flat list of uniquely-named elements, so a real
    // parser would be more code for identical answers. The one nested structure,
    // `<Pages>`, is a list of self-closing elements with attributes, which is the
    // easy case.

    private static func element(_ name: String, in text: String) -> String? {
        guard let open = text.range(of: "<\(name)>"),
              let close = text.range(of: "</\(name)>", range: open.upperBound..<text.endIndex)
        else { return nil }
        return String(text[open.upperBound..<close.lowerBound])
    }

    private static func pageElements(in text: String) -> [[String: String]] {
        var found: [[String: String]] = []
        var rest = Substring(text)
        while let open = rest.range(of: "<Page ") {
            rest = rest[open.upperBound...]
            guard let end = rest.firstIndex(of: ">") else { break }
            found.append(attributes(in: String(rest[..<end])))
            rest = rest[end...]
        }
        return found
    }

    private static func attributes(in fragment: String) -> [String: String] {
        var attributes: [String: String] = [:]
        var rest = Substring(fragment)
        while let equals = rest.firstIndex(of: "=") {
            let name = rest[..<equals].trimmingCharacters(
                in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "/"))
            )
            var after = rest[rest.index(after: equals)...]
            guard let quote = after.first, quote == "\"" || quote == "'" else { break }
            after = after.dropFirst()
            guard let closing = after.firstIndex(of: quote) else { break }
            if !name.isEmpty, !name.contains(" ") {
                attributes[name] = unescape(String(after[..<closing]))
            }
            rest = after[after.index(after: closing)...]
        }
        return attributes
    }

    /// The five predefined XML entities. A summary with an ampersand in it is
    /// ordinary, and showing `&amp;` in a library is not.
    private static func unescape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}
