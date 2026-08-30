public import Foundation

/// One item in a publication's reading order.
public struct EpubSpineItem: Sendable, Equatable {
    /// Path inside the container, resolved against the package document.
    public let href: String
    public let mediaType: String
    /// EPUB 3 lets a single item opt out of the publication's layout.
    public let isFixedLayout: Bool?
}

/// One entry in the table of contents, from a nav document or an NCX.
public struct EpubTocEntry: Sendable, Equatable {
    public let title: String
    public let href: String
    public let children: [EpubTocEntry]
}

/// What a publication says about itself.
public enum EpubError: Error, Equatable {
    /// Not an EPUB: the `mimetype` entry is missing or says something else.
    case notEpub
    /// `META-INF/container.xml` is missing or names no root file.
    case noPackageDocument
    case malformed(String)
}

/// Reads an EPUB's structure: metadata, reading order, table of contents, cover.
///
/// **Not a rendering engine.** Laying out reflowable XHTML with the typography
/// controls `ebook-reader` requires is Readium's job ([ADR-0005]) — writing one
/// would be the largest and least differentiated piece of work in the project.
///
/// What this does instead is everything the *library* needs, which turns out to be
/// all of it except the rendering: an EPUB is a ZIP holding XML, so the container
/// is our own reader ([ADR-0008]) and the XML is the platform's. So a shelf of
/// EPUBs can be indexed — titles, authors, covers, chapter counts — with no
/// dependency at all, and Readium is needed only once someone opens one to read.
///
/// The four combinations `publication-formats` promises — EPUB 2 and 3,
/// reflowable and fixed-layout — differ in exactly the places a parser gets
/// wrong, so each is handled explicitly rather than by assuming the modern shape:
/// EPUB 2 has an NCX where EPUB 3 has a nav document, and names its cover with a
/// metadata `meta` where EPUB 3 uses a manifest property.
public struct EpubReader: Sendable {
    /// The package document's path, which every other href resolves against.
    public let packagePath: String
    public let version: Int
    public let metadata: EpubMetadata
    /// Reading order, as the spine declares it.
    public let spine: [EpubSpineItem]
    public let toc: [EpubTocEntry]
    /// The cover image's path inside the container, when the publication names one.
    public let coverHref: String?
    /// True when the publication is pre-paginated.
    ///
    /// Drives which reader opens it: a fixed-layout EPUB is images with positions,
    /// so `ebook-reader` requires the image reader and forbids offering typography
    /// controls that cannot do anything.
    public let isFixedLayout: Bool

    private let reader: ZipReader
    let pathToEntry: [String: ZipEntry]  // internal: see EpubSpineCover.swift

    public init(source: any RandomAccessSource) async throws {
        do {
            self.reader = try await ZipReader(source: source)
        } catch {
            throw EpubError.notEpub
        }
        var index: [String: ZipEntry] = [:]
        for entry in reader.entries { index[entry.path] = entry }
        self.pathToEntry = index

        // The container spec's one hard requirement, and the cheapest way to tell
        // an EPUB from any other ZIP before parsing XML.
        guard let mimetype = index["mimetype"],
              let text = String(data: try await reader.data(for: mimetype), encoding: .utf8),
              text.trimmingCharacters(in: .whitespacesAndNewlines) == "application/epub+zip"
        else { throw EpubError.notEpub }

        guard let container = index["META-INF/container.xml"] else {
            throw EpubError.noPackageDocument
        }
        let containerXML = try await reader.data(for: container)
        guard let packagePath = Self.attribute(
            "full-path", ofFirst: "rootfile", in: containerXML
        ) else { throw EpubError.noPackageDocument }
        self.packagePath = packagePath

        guard let packageEntry = index[packagePath] else { throw EpubError.noPackageDocument }
        let packageXML = try await reader.data(for: packageEntry)
        let base = Self.directory(of: packagePath)

        let package = try Self.parsePackage(packageXML, base: base)
        self.version = package.version
        self.metadata = package.metadata
        self.spine = package.spine
        self.coverHref = package.coverHref
        self.isFixedLayout = package.isFixedLayout

        // The table of contents lives in a different file, in a different format,
        // depending on the version. Missing is not an error: a publication with no
        // declared contents still reads front to back.
        if let navPath = package.navHref, let navEntry = index[navPath] {
            self.toc = Self.parseNav(
                try await reader.data(for: navEntry), base: Self.directory(of: navPath)
            )
        } else if let ncxPath = package.ncxHref, let ncxEntry = index[ncxPath] {
            self.toc = Self.parseNcx(
                try await reader.data(for: ncxEntry), base: Self.directory(of: ncxPath)
            )
        } else {
            self.toc = []
        }
    }

    /// One item's bytes, by its container path.
    public func data(at href: String) async throws -> Data {
        guard let entry = pathToEntry[href] else { throw EpubError.malformed("no entry at \(href)") }
        return try await reader.data(for: entry)
    }

    /// The cover image's bytes, when the publication has one.
    public func coverData() async throws -> Data? {
        guard let coverHref else { return nil }
        return try? await data(at: coverHref)
    }

    // MARK: - Package document

    private struct Package {
        let version: Int
        let metadata: EpubMetadata
        let spine: [EpubSpineItem]
        let coverHref: String?
        let navHref: String?
        let ncxHref: String?
        let isFixedLayout: Bool
    }

    // One pass over the package document, reading metadata, manifest and spine in the
    // order they appear. Three passes would be three times the XML walking.
    // swiftlint:disable:next function_body_length
    private static func parsePackage(_ xml: Data, base: String) throws -> Package {
        let elements = Elements(xml)

        let version = Int(
            (attribute("version", ofFirst: "package", in: xml) ?? "3")
                .split(separator: ".").first.map(String.init) ?? "3"
        ) ?? 3

        // A manifest item is (id, href, media-type, properties). Everything else
        // in the package refers to items by id, so this map comes first.
        struct Item {
            let href: String
            let mediaType: String
            let properties: String
        }
        var items: [String: Item] = [:]
        for element in elements.named("item") {
            guard let id = element["id"], let href = element["href"] else { continue }
            items[id] = Item(
                href: resolve(href, against: base),
                mediaType: element["media-type"] ?? "",
                properties: element["properties"] ?? ""
            )
        }

        let layoutValue = elements.named("meta").first {
            $0["property"] == "rendition:layout"
        }?.text
        let isFixedLayout = layoutValue?.trimmingCharacters(in: .whitespacesAndNewlines)
            == "pre-paginated"

        var spine: [EpubSpineItem] = []
        for element in elements.named("itemref") {
            guard let idref = element["idref"], let item = items[idref] else { continue }
            // `rendition:layout-pre-paginated` on an itemref overrides the
            // publication's own layout for that one item.
            let properties = element["properties"] ?? ""
            let itemLayout: Bool? = properties.contains("rendition:layout-pre-paginated")
                ? true
                : (properties.contains("rendition:layout-reflowable") ? false : nil)
            spine.append(
                EpubSpineItem(href: item.href, mediaType: item.mediaType, isFixedLayout: itemLayout)
            )
        }

        // EPUB 3 marks the cover with a manifest property; EPUB 2 names an item id
        // from a metadata meta. Both are checked, in that order, because a version
        // number is not a promise about which convention a file actually used.
        var coverHref = items.values.first { $0.properties.contains("cover-image") }?.href
        if coverHref == nil,
           let coverId = elements.named("meta").first(where: { $0["name"] == "cover" })?["content"] {
            coverHref = items[coverId]?.href
        }

        let navHref = items.values.first { $0.properties.contains("nav") }?.href
        // The NCX is reached through the spine's `toc` attribute, not by media type
        // — a publication may carry an NCX it does not use.
        let ncxId = attribute("toc", ofFirst: "spine", in: xml)
        let ncxHref = ncxId.flatMap { items[$0]?.href }
            ?? items.values.first { $0.mediaType == "application/x-dtbncx+xml" }?.href

        return Package(
            version: version,
            metadata: EpubMetadata(
                title: elements.text(of: "dc:title") ?? elements.text(of: "title"),
                author: elements.text(of: "dc:creator") ?? elements.text(of: "creator"),
                language: elements.text(of: "dc:language") ?? elements.text(of: "language"),
                identifier: elements.text(of: "dc:identifier") ?? elements.text(of: "identifier"),
                publisher: elements.text(of: "dc:publisher") ?? elements.text(of: "publisher"),
                description: elements.text(of: "dc:description")
                    ?? elements.text(of: "description"),
                series: series(in: elements)?.name,
                seriesIndex: series(in: elements)?.position
            ),
            spine: spine,
            coverHref: coverHref,
            navHref: navHref,
            ncxHref: ncxHref,
            isFixedLayout: isFixedLayout
        )
    }

    /// The EPUB 3 nav document: the `<nav epub:type="toc">` list.
    private static func parseNav(_ xml: Data, base: String) -> [EpubTocEntry] {
        // Only anchors inside the toc nav count. A nav document may also carry a
        // landmarks or page-list nav, and treating those as chapters would put
        // "Start of content" in the table of contents.
        guard let scoped = slice(xml, from: "epub:type=\"toc\"", to: "</nav>") else {
            return anchors(in: xml, base: base)
        }
        return anchors(in: scoped, base: base)
    }

    /// The EPUB 2 NCX: `navPoint` with a `navLabel/text` and a `content/@src`.
    private static func parseNcx(_ xml: Data, base: String) -> [EpubTocEntry] {
        guard let text = String(data: xml, encoding: .utf8) else { return [] }
        var entries: [EpubTocEntry] = []
        var rest = Substring(text)
        while let start = rest.range(of: "<navPoint") {
            rest = rest[start.upperBound...]
            guard let end = rest.range(of: "</navPoint>") ?? rest.range(of: "/>") else { break }
            let block = rest[..<end.lowerBound]
            let label = between(block, "<text>", "</text>")?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let src = Elements(Data(block.utf8)).named("content").first?["src"]
            if let label, let src, !label.isEmpty {
                entries.append(
                    EpubTocEntry(title: label, href: resolve(src, against: base), children: [])
                )
            }
        }
        return entries
    }

    private static func anchors(in xml: Data, base: String) -> [EpubTocEntry] {
        guard let text = String(data: xml, encoding: .utf8) else { return [] }
        var entries: [EpubTocEntry] = []
        var rest = Substring(text)
        while let open = rest.range(of: "<a ") {
            rest = rest[open.lowerBound...]
            guard let close = rest.range(of: "</a>") else { break }
            let element = rest[..<close.upperBound]
            rest = rest[close.upperBound...]
            guard let href = Elements(Data(element.utf8)).named("a").first?["href"],
                  let title = between(element, ">", "</a>")?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  !title.isEmpty
            else { continue }
            entries.append(
                EpubTocEntry(title: title, href: resolve(href, against: base), children: [])
            )
        }
        return entries
    }

    // MARK: - Minimal XML reading
    //
    // ponytail: attribute scraping rather than a DOM. An EPUB package document is
    // a flat list of elements with attributes, and the fields needed here are
    // named unambiguously — so `XMLParser` and a delegate would be more code for
    // the same answers. If nested structure is ever needed (a hierarchical table
    // of contents, say), switch to `XMLParser` rather than growing this.

    /// Every element with a given local name, and its attributes.
    /// Not `private`: the metadata half of this type lives in `EpubMetadata.swift`, and
    /// Swift's `private` is file-scoped, so the split that keeps this file under the line
    /// cap is what widens it.
    struct Elements {
        private let text: String

        init(_ data: Data) {
            self.text = String(data: data, encoding: .utf8) ?? ""
        }

        func named(_ name: String) -> [[String: String]] {
            var found: [[String: String]] = []
            var rest = Substring(text)
            while let open = rest.range(of: "<\(name)") {
                rest = rest[open.upperBound...]
                // Guard against `<items>` matching a search for `<item>`.
                if let next = rest.first, next.isLetter || next.isNumber { continue }
                guard let end = rest.firstIndex(of: ">") else { break }
                var attributes = parseAttributes(String(rest[..<end]))
                // Element text, for `<meta property="...">value</meta>` and `<dc:title>`.
                let after = rest[rest.index(after: end)...]
                if let closing = after.range(of: "</\(name)>") {
                    attributes["#text"] = String(after[..<closing.lowerBound])
                }
                found.append(attributes)
                rest = after
            }
            return found
        }

        /// The text of the first element with this name.
        func text(of name: String) -> String? {
            named(name).first?.text
        }
    }

    private static func parseAttributes(_ fragment: String) -> [String: String] {
        var attributes: [String: String] = [:]
        var rest = Substring(fragment)
        while let equals = rest.firstIndex(of: "=") {
            let name = rest[..<equals].trimmingCharacters(
                in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "/?"))
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

    private static func attribute(
        _ name: String, ofFirst element: String, in xml: Data
    ) -> String? {
        Elements(xml).named(element).first?[name]
    }

    private static func slice(_ xml: Data, from: String, to: String) -> Data? {
        guard let text = String(data: xml, encoding: .utf8),
              let start = text.range(of: from),
              let end = text.range(of: to, range: start.upperBound..<text.endIndex)
        else { return nil }
        return Data(text[start.upperBound..<end.lowerBound].utf8)
    }

    private static func between(_ text: Substring, _ from: String, _ to: String) -> String? {
        guard let start = text.range(of: from),
              let end = text.range(of: to, range: start.upperBound..<text.endIndex)
        else { return nil }
        return String(text[start.upperBound..<end.lowerBound])
    }

    /// The five predefined XML entities. An EPUB title with an ampersand in it is
    /// ordinary, and showing `&amp;` in a library is not.
    private static func unescape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    // MARK: - Paths

    private static func directory(of path: String) -> String {
        guard let slash = path.lastIndex(of: "/") else { return "" }
        return String(path[..<slash])
    }

    /// An href relative to the document that declared it, with any fragment
    /// dropped — a table of contents entry may point at an anchor inside a file.
    private static func resolve(_ href: String, against base: String) -> String {
        let withoutFragment = href.split(separator: "#", maxSplits: 1).first.map(String.init) ?? href
        guard !withoutFragment.hasPrefix("/") else { return String(withoutFragment.dropFirst()) }
        guard !base.isEmpty else { return withoutFragment }

        var segments = base.split(separator: "/").map(String.init)
        for part in withoutFragment.split(separator: "/") {
            switch part {
            case ".": continue
            case "..": if !segments.isEmpty { segments.removeLast() }
            default: segments.append(String(part))
            }
        }
        return segments.joined(separator: "/")
    }
}
