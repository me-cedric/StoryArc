import Catalogue
import CoreGraphics
import DesignSystem
import Foundation
import ImageIO
@testable import LibraryFeature
import Persistence
import ReaderFeature
@testable import SettingsFeature
import StoryArcCore
import SwiftUI
import UniformTypeIdentifiers
import XCTest

/// A transport that answers every picture request with a painted cover, so the candidate sheet
/// draws pictures with no network. Its own type: no other test shares its answers.
private final class PaintedCovers: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var pictures: [String: Data] = [:]

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url,
              let body = Self.pictures[url.absoluteString],
              let response = HTTPURLResponse(
                  url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [:]
              )
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// States that the first catalogue left out because no fixture reached them.
@MainActor
final class EdgeStateCatalogueTests: XCTestCase {
    private static let moment = Date(timeIntervalSince1970: 1_767_225_600)

    private func png(hue: CGFloat) throws -> Data {
        let image = try XCTUnwrap(CatalogueCover.image(for: "candidate", hue: hue) as CGImage?)
        let buffer = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(
            buffer, UTType.png.identifier as CFString, 1, nil
        ))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return buffer as Data
    }

    /// The sheet that opens from *Find a cover*, with three candidates and a picture for each.
    /// There is no best match and nothing is adopted until a row is tapped.
    func testCatalogue22CoverCandidatesWithPictures() throws {
        let candidates = [
            CoverCandidate(
                title: "The Long Field", subtitle: "Cullen Bunn · 2017",
                imageURL: try XCTUnwrap(URL(string: "https://covers.openlibrary.org/b/id/101-L.jpg")),
                provider: .openLibrary
            ),
            CoverCandidate(
                title: "The Long Field (second printing)", subtitle: "Cullen Bunn · 2019",
                imageURL: try XCTUnwrap(URL(string: "https://covers.openlibrary.org/b/id/102-L.jpg")),
                provider: .openLibrary
            ),
            CoverCandidate(
                title: "Long Field", subtitle: "Manga · 2021",
                imageURL: try XCTUnwrap(
                    URL(string: "https://s4.anilist.co/file/anilistcdn/media/manga/cover/large/103.jpg")
                ),
                provider: .aniList
            ),
        ]
        PaintedCovers.pictures = [
            candidates[0].imageURL.absoluteString: try png(hue: 0.02),
            candidates[1].imageURL.absoluteString: try png(hue: 0.55),
            candidates[2].imageURL.absoluteString: try png(hue: 0.72),
        ]
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PaintedCovers.self]
        let client = CoverLookupClient(
            isEnabled: { true },
            cache: CoverLookupCache(
                file: URL.temporaryDirectory.appending(path: "\(UUID().uuidString).json")
            ),
            configuration: configuration
        )
        assertCatalogue("22-cover-candidates-with-pictures", delay: 3) {
            NavigationStack {
                CoverCandidateSheet(candidates: candidates, onChoose: { _ in }, client: client)
            }
        }
    }

    /// Home when the book read last is an audiobook: the hero names the action Resume.
    func testCatalogue23HomeWithAnAudiobookHero() {
        let model = CatalogueLibrary.model()
        let book = model.publications[5]
        model.progress[book.id] = ReadingProgress(
            identity: book.identity,
            position: .listening(part: 1, partCount: 3, offset: 754, of: 2_410),
            isFinished: false,
            finishedAt: nil,
            updatedAt: Self.moment.addingTimeInterval(60)
        )
        model.rebuild()
        assertCatalogue("23-home-with-an-audiobook-hero", delay: 1.5, precision: 0.98) {
            HomeScreen(model: model)
        }
    }

    /// Home with one pinned collection and one pinned reading list, drawn with the real covers.
    /// The list is a run in an order of its own: its covers follow the list, not the library.
    func testCatalogue26HomeWithPinnedShelves() throws {
        let plain = CatalogueLibrary.entries.map { entry -> CatalogueLibrary.Entry in
            var copy = entry
            copy.progress = nil
            return copy
        }
        let model = CatalogueLibrary.model(entries: plain)
        let ids = model.publications.map(\.id)
        let collection = PublicationCollection(
            id: try XCTUnwrap(UUID(uuidString: "5A1D0000-0000-4000-8000-0000000000C1")),
            name: "Weekend reads", members: [ids[1], ids[4], ids[8]]
        )
        let list = ReadingList(
            id: try XCTUnwrap(UUID(uuidString: "5A1D0000-0000-4000-8000-0000000000C2")),
            name: "Start here", entries: [ids[11], ids[2], ids[0], ids[6]]
        )
        let shelves = Shelves(collections: [collection], lists: [list])
        let rows = pinnedShelfRows(
            PinnedShelves(stored: "collection:\(collection.id.uuidString) list:\(list.id.uuidString)"),
            shelves: shelves, publications: model.publications
        )
        XCTAssertEqual(rows.map(\.name), ["Weekend reads", "Start here"])
        XCTAssertEqual(rows[1].publications.map(\.id), [ids[11], ids[2], ids[0], ids[6]])
        assertCatalogue("26-home-pinned-shelves", delay: 2, largest: false) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: StoryArcSpace.section) {
                        ForEach(rows) { row in
                            HomeSection(title: Text(verbatim: row.name)) {
                                HomeMore(
                                    title: Text(verbatim: row.name), publications: row.publications, model: model
                                )
                            } content: {
                                HomeShelfRow(publications: row.publications, model: model)
                            }
                        }
                    }
                    .padding(.vertical, StoryArcSpace.lg)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    /// The source detail while a server read stands at its only title: "1 of 1 title".
    func testCatalogue24SourceDetailOneOfOneTitle() {
        let kavita = Source(
            id: UUID(uuidString: "5A1D0000-0000-4000-8000-0000000000B1") ?? UUID(),
            displayName: "Kavita at home", kind: .kavitaServer, state: .connected,
            lastSuccessfulSync: Self.moment, locator: "https://kavita.example.test"
        )
        let diagnosis = SourceDiagnosis.of(
            kavita, itemCount: 1, downloads: [], isPartial: true, readCount: 1, readTotal: 1
        )
        assertCatalogue("24-source-detail-one-of-one-title") {
            NavigationStack {
                SourceDetail(source: kavita, diagnosis: diagnosis, perform: { _ in })
                    .navigationTitle(kavita.displayName)
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
    }

    /// A comic of two pages, each four times as tall as it is wide, with a heavy frame at the
    /// page's own edges. A page that sits right of centre shows the frame cut on the right and a
    /// gap on the left.
    private func tallComic() throws -> (Publication, URL) {
        let directory = URL.temporaryDirectory.appending(path: "tall-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let pages = (0..<2).map { index -> (name: String, data: Data) in
            let size = CGSize(width: 600, height: 2_400)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let png = UIGraphicsImageRenderer(size: size, format: format).pngData { context in
                UIColor(hue: 0.1 + 0.2 * CGFloat(index), saturation: 0.2, brightness: 0.97, alpha: 1).setFill()
                context.fill(CGRect(origin: .zero, size: size))
                UIColor(hue: 0.6, saturation: 0.8, brightness: 0.45, alpha: 1).setFill()
                context.fill(CGRect(x: 0, y: 0, width: 36, height: size.height))
                context.fill(CGRect(x: size.width - 36, y: 0, width: 36, height: size.height))
                UIColor(hue: 0.02, saturation: 0.7, brightness: 0.75, alpha: 1).setFill()
                for band in 0..<6 {
                    context.fill(CGRect(x: 120, y: 120 + CGFloat(band) * 400, width: 360, height: 220))
                }
            }
            return (name: "page\(index + 1).png", data: png)
        }
        let file = directory.appending(path: "Tall Harbour 001.cbz")
        try StoredZip.build(pages).write(to: file)
        let publication = Publication(
            identity: PublicationIdentity(normalizedPath: file.path),
            format: .cbz,
            displayTitle: "Tall Harbour",
            origin: .embedded,
            pageCount: 2
        )
        return (publication, file)
    }

    /// Task 23.2: a tall page at Fit to Width fills the width and sits in the middle.
    private func tallPage(_ slug: String, transition: PageTransition) throws {
        let (publication, file) = try tallComic()
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "tall-\(UUID().uuidString)"))
        let preferences = ReaderPreferences(defaults: defaults)
        let shelf = ShelfMemory.shelf(series: publication.series, identity: publication.id)
        preferences.save(
            preferences.themes().remembering(
                ShelfSettings(transition: transition, fit: .width), for: .fixedLayout, shelf: shelf
            )
        )
        assertCatalogue(slug, delay: 3, precision: 0.96, largest: false) {
            ReaderView(publication: publication, url: file, preferences: preferences)
        }
    }

    func testCatalogue25aTallPageFitToWidthSlide() throws {
        try tallPage("25a-tall-page-fit-to-width-slide", transition: .slide)
    }

    func testCatalogue25bTallPageFitToWidthCurl() throws {
        try tallPage("25b-tall-page-fit-to-width-curl", transition: .pageCurl)
    }
}
