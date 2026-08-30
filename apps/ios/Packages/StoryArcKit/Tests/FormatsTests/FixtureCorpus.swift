import Foundation
import Testing

/// Locates the shared fixture corpus at `packages/test-fixtures`.
///
/// The corpus lives outside this SPM package on purpose — both platforms read
/// the same files, which is what stops the two implementations from quietly
/// disagreeing about what a correct parse is (ADR-0001). SPM cannot declare a
/// resource outside its own root, so the path is resolved from `#filePath` at
/// runtime instead of being copied in.
enum FixtureCorpus {
    /// Walks up from this file until it finds the repository root.
    static let root: URL = {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while dir.path != "/" {
            let corpus = dir.appending(path: "packages/test-fixtures")
            if FileManager.default.fileExists(atPath: corpus.appending(path: "manifest.json").path) {
                return corpus
            }
            dir = dir.deletingLastPathComponent()
        }
        fatalError("fixture corpus not found — expected packages/test-fixtures above \(#filePath)")
    }()

    static func url(_ relativePath: String) -> URL {
        root.appending(path: relativePath)
    }

    /// One entry from `manifest.json`, which records what a correct parse yields.
    struct Fixture: Decodable {
        let file: String
        let pins: String
        let expectedPageCount: Int?
        let expectedPageOrder: [String]?
        let isRecoverable: Bool?
        let actualContainer: String?
        let hasComicInfo: Bool?
        let expectedSeries: String?
        let spreadIndices: [Int]?
        let isSolid: Bool?
        let isStreamable: Bool?
        let expectedRefusal: String?
        let expectedEntryNames: [String]?
        let pageDimensions: [Int]?
        let expectedPagePixel: [Int]?
    }

    /// One entry from the manifest's `pdfs` list. PDF is not an archive, so its
    /// expectations are geometry and text rather than entry order.
    struct PdfFixture: Decodable {
        let file: String
        let pins: String
        let expectedPageCount: Int
        let expectedPageSizePoints: [Int]?
        let hasTextLayer: Bool
        let expectedPageText: [String]?
        let expectedOutlineTitles: [String]?
        let expectedAspect: [Int]?
    }

    /// One entry from the manifest's `ebooks` list.
    struct EbookFixture: Decodable {
        let file: String
        let pins: String
        let epubVersion: Int
        let expectedSpineCount: Int
        let expectedTitle: String?
        let expectedAuthor: String?
        let expectedLanguage: String?
        let expectedIdentifier: String?
        let expectedPublisher: String?
        let expectedDescription: String?
        let expectedSeries: String?
        let expectedSeriesIndex: String?
        let expectedSpineHrefs: [String]?
        let expectedTocTitles: [String]?
        let expectedCoverHref: String?
        let hasNavDocument: Bool
        let hasCoverImage: Bool
        let isFixedLayout: Bool
        let expectedRefusal: String?
    }

    /// One case from the manifest's `filenames` table. Needs no file on disk:
    /// filename inference is a pure function over a string, so what the corpus
    /// pins is the table of cases rather than any bytes.
    struct FilenameCase: Decodable, Sendable {
        let filename: String
        let series: String?
        let number: String?
        let volume: Int?
        let year: Int?
        /// Why this case is in the table, so a failure says what broke.
        let why: String
    }

    private struct Manifest: Decodable {
        let comics: [Fixture]
        let pdfs: [PdfFixture]
        let ebooks: [EbookFixture]
        let filenames: [FilenameCase]
    }

    static let comics: [Fixture] = {
        do {
            let data = try Data(contentsOf: url("manifest.json"))
            return try JSONDecoder().decode(Manifest.self, from: data).comics
        } catch {
            // The corpus is a build input, not a runtime condition. If it cannot
            // be read the test run is meaningless, so failing loudly here beats
            // every fixture test reporting its own confusing error.
            fatalError("could not read the fixture manifest: \(error)")
        }
    }()

    static let pdfs: [PdfFixture] = {
        do {
            let data = try Data(contentsOf: url("manifest.json"))
            return try JSONDecoder().decode(Manifest.self, from: data).pdfs
        } catch {
            fatalError("could not read the fixture manifest: \(error)")
        }
    }()

    static let ebooks: [EbookFixture] = {
        do {
            let data = try Data(contentsOf: url("manifest.json"))
            return try JSONDecoder().decode(Manifest.self, from: data).ebooks
        } catch {
            fatalError("could not read the fixture manifest: \(error)")
        }
    }()

    static let filenames: [FilenameCase] = {
        do {
            let data = try Data(contentsOf: url("manifest.json"))
            return try JSONDecoder().decode(Manifest.self, from: data).filenames
        } catch {
            fatalError("could not read the fixture manifest: \(error)")
        }
    }()

    static func ebook(_ name: String) -> EbookFixture? {
        ebooks.first { $0.file == "ebooks/\(name)" }
    }

    static func pdf(_ name: String) -> PdfFixture? {
        pdfs.first { $0.file == "comics/\(name)" }
    }

    static func comic(_ name: String) -> Fixture {
        guard let match = comics.first(where: { $0.file == "comics/\(name)" }) else {
            fatalError("no fixture named \(name) in manifest.json")
        }
        return match
    }
}
