import Formats
import Foundation

// The manifest's shape, as the renderer deserialises it. File-scope types rather than
// nested ones, for SwiftLint's nesting rule.

struct EpubWebLink: Codable, Sendable, Equatable {
    var href: String
    var type: String
    var title: String?
    var rel: String?
}

struct EpubWebMetadata: Codable, Sendable, Equatable {
    var type = "http://schema.org/Book"
    var identifier: String?
    var title: String
    var author: String?
    var language: [String]
    /// `fixed` or `reflowable`.
    var layout: String
    /// `ltr`, `rtl` or `auto`.
    var readingProgression: String

    enum CodingKeys: String, CodingKey {
        case type = "@type"
        case identifier, title, author, language, layout, readingProgression
    }
}

struct EpubWebManifest: Codable, Sendable, Equatable {
    var context = "https://readium.org/webpub-manifest/context.jsonld"
    var metadata: EpubWebMetadata
    var links: [EpubWebLink]
    var readingOrder: [EpubWebLink]
    var resources: [EpubWebLink]
    var toc: [EpubWebLink]

    enum CodingKeys: String, CodingKey {
        case context = "@context"
        case metadata, links, readingOrder, resources, toc
    }
}

struct EpubWebLocations: Codable, Sendable, Equatable {
    var position: Int
    var progression: Double
    var totalProgression: Double
}

struct EpubWebPosition: Codable, Sendable, Equatable {
    var href: String
    var type: String
    var title: String?
    var locations: EpubWebLocations
}

/// The Readium Web Publication Manifest and the positions list the renderer is owed, built
/// in Swift from what `StoryArcKit`'s `Formats` already reads.
///
/// `design.md` Open Question 6, answered by task 1.29: `EpubReader` yields the spine, the
/// table of contents, the metadata and the cover, and `ZipReader` yields each entry's
/// compressed size, which is the number the positions rule divides by 1024. Nothing is
/// duplicated but the serialisation. The shape is the one `apps/desktop-web/epub/test/
/// fixture.mjs` builds and the core's `WebPublication` of task 4.3 builds, so the three
/// hosts hand the bundle the same JSON: hrefs are container paths, the self link is the
/// scheme URL the host serves the manifest at, and `metadata.layout` and
/// `metadata.readingProgression` carry the rendition. Task 4.5.
struct EpubWebPublication: Sendable, Equatable {
    let manifest: EpubWebManifest
    let positions: [EpubWebPosition]

    /// Positions of the spine item at `index` in reading order.
    var positionCounts: [Int] {
        manifest.readingOrder.map { item in positions.filter { $0.href == item.href }.count }
    }

    /// The positions rule every platform shares: the compressed size in kilobytes, rounded
    /// up, and at least one. swift-toolkit's `EPUBPositionsService` does the same.
    static func positionCount(compressedSize: Int64) -> Int {
        max(1, Int((compressedSize + 1023) / 1024))
    }

    /// Builds both from the EPUB at `url`, with its manifest served at `selfHref`.
    static func build(url: URL, selfHref: String) async throws -> EpubWebPublication {
        let source = try FileSource(url: url)
        let reader = try await EpubReader(source: source)
        let zip = try await ZipReader(source: source)
        return build(reader: reader, compressedSizes: zip.compressedSizes, selfHref: selfHref)
    }

    static func build(
        reader: EpubReader, compressedSizes: [String: Int64], selfHref: String
    ) -> EpubWebPublication {
        let titles = tocTitles(reader.toc)
        let readingOrder = reader.spine.map { item in
            EpubWebLink(
                href: item.href, type: item.mediaType.isEmpty ? "application/xhtml+xml" : item.mediaType,
                title: titles[item.href]
            )
        }
        let counts = reader.spine.map { positionCount(compressedSize: compressedSizes[$0.href] ?? 0) }
        let total = counts.reduce(0, +)
        var positions: [EpubWebPosition] = []
        var number = 0
        for (index, item) in readingOrder.enumerated() {
            for page in 0..<counts[index] {
                number += 1
                positions.append(EpubWebPosition(
                    href: item.href, type: item.type, title: item.title,
                    locations: EpubWebLocations(
                        position: number,
                        progression: Double(page) / Double(counts[index]),
                        totalProgression: Double(number - 1) / Double(max(1, total))
                    )
                ))
            }
        }
        let metadata = EpubWebMetadata(
            identifier: reader.metadata.identifier,
            title: reader.metadata.title ?? url(selfHref),
            author: reader.metadata.author,
            language: reader.metadata.language.map { [$0] } ?? [],
            layout: reader.isFixedLayout ? "fixed" : "reflowable",
            readingProgression: progression(reader.pageProgressionDirection)
        )
        let cover = reader.coverHref.map { EpubWebLink(href: $0, type: EpubMediaTypes.type(of: $0), rel: "cover") }
        return EpubWebPublication(
            manifest: EpubWebManifest(
                metadata: metadata,
                links: [EpubWebLink(href: selfHref, type: "application/webpub+json", rel: "self")],
                readingOrder: readingOrder,
                resources: cover.map { [$0] } ?? [],
                toc: flatten(reader.toc)
            ),
            positions: positions
        )
    }

    private static func progression(_ declared: String?) -> String {
        switch declared?.lowercased() {
        case "rtl": "rtl"
        case "ltr": "ltr"
        default: "auto"
        }
    }

    /// A title that is never empty: the manifest requires one.
    private static func url(_ selfHref: String) -> String {
        URL(string: selfHref)?.host() ?? "Untitled"
    }

    /// The first title the navigation gives each resource, as `SpokenParts` names parts.
    private static func tocTitles(_ entries: [EpubTocEntry]) -> [String: String] {
        var titles: [String: String] = [:]
        for entry in flatten(entries) where titles[entry.href] == nil { titles[entry.href] = entry.title }
        return titles
    }

    private static func flatten(_ entries: [EpubTocEntry]) -> [EpubWebLink] {
        entries.flatMap { entry in
            [EpubWebLink(href: entry.href, type: EpubMediaTypes.type(of: entry.href), title: entry.title)]
                + flatten(entry.children)
        }
    }

    /// The manifest as the bytes the scheme handler serves.
    func manifestData() throws -> Data { try Self.encoder.encode(manifest) }

    func positionsData() throws -> Data { try Self.encoder.encode(positions) }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()
}

extension ZipReader {
    /// Each entry's compressed size by its path, the number the positions rule divides.
    var compressedSizes: [String: Int64] {
        Dictionary(entries.map { ($0.path, $0.compressedSize) }, uniquingKeysWith: { first, _ in first })
    }
}
