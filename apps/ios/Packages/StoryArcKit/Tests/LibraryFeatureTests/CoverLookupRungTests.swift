import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

import Catalogue
import Formats
@testable import LibraryFeature
import Persistence
import StoryArcCore

/// The lookup is a rung of the ladder `LibraryModel.cover(for:maxPixelSize:)` climbs, and its
/// three trust rules hold on the way.
///
/// Tasks 6.1 and 3.2 of `cover-for-every-publication`. The rules are the wave 11 review's: the
/// rung reaches only the hosts the setting names, reads at most 8 MB of an answer (asserted
/// beside the transport, in `CatalogueTests`), and never runs while the setting is off.
/// Android's `CoverLookupRungTest` and `CoverLookupLadderWiringTest` are the twins.
@Suite("The cover lookup rung", .serialized)
@MainActor
struct CoverLookupRungTests {

    /// Every request the stub saw, which is what the egress assertions read.
    private final class Asked: @unchecked Sendable {
        private let lock = NSLock()
        private var urls: [URL] = []

        func append(_ url: URL?) {
            guard let url else { return }
            lock.lock()
            urls.append(url)
            lock.unlock()
        }

        var value: [URL] {
            lock.lock()
            defer { lock.unlock() }
            return urls
        }
    }

    private final class Identified: @unchecked Sendable {
        nonisolated(unsafe) var count = 0
    }

    private let isbn = CoverIdentifier.isbn("9780141187761")

    private func rung(
        enabled: Bool,
        identifier: CoverIdentifier? = .isbn("9780141187761"),
        identified: Identified = Identified(),
        _ answer: @escaping @Sendable (URLRequest) -> LookupStub.Answer
    ) -> CoverLookupRung {
        LookupStub.answer = answer
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LookupStub.self]
        let cache = CoverLookupCache(
            file: URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("\(UUID().uuidString).json")
        )
        return CoverLookupRung(
            isEnabled: { enabled },
            client: CoverLookupClient(isEnabled: { enabled }, cache: cache, configuration: configuration),
            identify: { _, _ in
                identified.count += 1
                return identifier
            }
        )
    }

    private let book = URL(fileURLWithPath: "/books/fine-print.epub")

    private func publication(id: String = UUID().uuidString) -> Publication {
        Publication(
            identity: PublicationIdentity(contentDigest: id, normalizedPath: "/books/\(id).epub"),
            format: .epub,
            displayTitle: "Fine Print",
            origin: .inferred
        )
    }

    // MARK: The rung

    @Test("One publication with one identifier asks one provider once while the switch is on")
    func asksOnce() async {
        let asked = Asked()
        let rung = rung(enabled: true) { request in
            asked.append(request.url)
            return .response(status: 200, body: Data("jpeg".utf8))
        }
        let publication = publication()

        let first = await rung.picture(for: publication, at: book)
        let second = await rung.picture(for: publication, at: book)

        #expect(first == Data("jpeg".utf8))
        #expect(second == first)
        #expect(asked.value.map(\.absoluteString)
            == ["https://covers.openlibrary.org/b/isbn/9780141187761-L.jpg?default=false"])
    }

    @Test("The request carries the identifier and nothing else")
    func sendsOnlyTheIdentifier() async throws {
        let asked = Asked()
        let publication = publication(id: "fine-print-digest")
        let rung = rung(enabled: true) { request in
            asked.append(request.url)
            return .response(status: 200, body: Data("jpeg".utf8))
        }

        _ = await rung.picture(for: publication, at: book)

        let url = try #require(asked.value.first?.absoluteString)
        #expect(!url.contains("fine-print") && !url.contains("digest"))
    }

    @Test("Nothing is read and nothing is asked while the switch is off")
    func asksNothingWhileOff() async {
        let asked = Asked()
        let identified = Identified()
        let rung = rung(enabled: false, identified: identified) { request in
            asked.append(request.url)
            return .response(status: 200, body: Data("jpeg".utf8))
        }

        let found = await rung.picture(for: publication(), at: book)

        #expect(found == nil)
        #expect(asked.value.isEmpty)
        #expect(identified.count < 1, "The file was opened for an identifier while the switch was off.")
    }

    @Test("A publication with no identifier asks nothing")
    func noIdentifier() async {
        let asked = Asked()
        let rung = rung(enabled: true, identifier: nil) { request in
            asked.append(request.url)
            return .response(status: 200, body: Data("jpeg".utf8))
        }

        #expect(await rung.picture(for: publication(), at: book) == nil)
        #expect(asked.value.isEmpty)
    }

    @Test("An answer that names a host the setting does not name is not followed")
    func unlistedHost() async {
        let asked = Asked()
        let rung = rung(enabled: true, identifier: .audibleASIN("B08G9PRS1K")) { request in
            asked.append(request.url)
            return .response(status: 200, body: Data(#"{"image":"https://tracker.example/c.jpg"}"#.utf8))
        }

        #expect(await rung.picture(for: publication(), at: book) == nil)
        #expect(asked.value.compactMap { $0.host() } == ["api.audnex.us"])
    }

    @Test("A refusal leaves the cover as it was and is not asked again")
    func refusalIsQuiet() async {
        let asked = Asked()
        let rung = rung(enabled: true) { request in
            asked.append(request.url)
            return .response(status: 429, body: Data())
        }
        let publication = publication()

        #expect(await rung.picture(for: publication, at: book) == nil)
        #expect(await rung.picture(for: publication, at: book) == nil)
        #expect(asked.value.count == 1)
    }

    // MARK: The ladder

    @Test("A book with no cover of its own and an ISBN gets its cover from the lookup, once")
    func ladderReachesTheLookup() async throws {
        let folder = URL.temporaryDirectory.appending(path: "lookup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appending(path: "book.epub")
        try bookWithISBN().write(to: file)
        let asked = Asked()
        let picture = try pngData()
        let live = CoverLookupRung.live
        defer { CoverLookupRung.live = live }
        let stubbed = rung(enabled: true) { request in
            asked.append(request.url)
            return .response(status: 200, body: picture)
        }
        CoverLookupRung.live = CoverLookupRung(
            isEnabled: stubbed.isEnabled,
            client: stubbed.client,
            identify: { await CoverIdentifierReader.identifier(for: $0, at: $1) }
        )
        let publication = publication()
        let model = LibraryModel()
        model.locations[publication.id] = file

        let drawn = await model.cover(for: publication, maxPixelSize: 64)
        // Another size misses the decoded cache, so the ladder is climbed a second time.
        model.covers = [:]
        let again = await model.cover(for: publication, maxPixelSize: 128)

        #expect(drawn != nil, "The looked-up picture was not drawn as the cover.")
        #expect(again != nil)
        #expect(asked.value.map(\.absoluteString)
            == ["https://covers.openlibrary.org/b/isbn/9780141187761-L.jpg?default=false"])
    }

    @Test("The live rung reads the stored setting at the moment of use")
    func liveRungReadsTheSetting() {
        let key = "app.storyarc.settings"
        let previous = UserDefaults.standard.data(forKey: key)
        defer {
            UserDefaults.standard.set(previous, forKey: key)
        }
        let store = SettingsStore()
        var settings = AppSettings.defaults

        settings.lookUpMissingCovers = false
        store.save(settings)
        #expect(!CoverLookupRung.live.isEnabled())

        settings.lookUpMissingCovers = true
        store.save(settings)
        #expect(CoverLookupRung.live.isEnabled())
    }

    private func bookWithISBN() -> Data {
        let opf = """
        <package version="3.0"><metadata><dc:title>Fine Print</dc:title>
        <dc:identifier>urn:uuid:5b4c1f9e-0c1d-4b5e-8f7a-1234567890ab</dc:identifier>
        <dc:identifier>urn:isbn:9780141187761</dc:identifier></metadata>
        <manifest></manifest><spine></spine></package>
        """
        return StoredZip.build([
            ("mimetype", Data("application/epub+zip".utf8)),
            ("META-INF/container.xml", Data(
                #"<container><rootfiles><rootfile full-path="package.opf"/></rootfiles></container>"#.utf8
            )),
            ("package.opf", Data(opf.utf8)),
        ])
    }

    private func pngData() throws -> Data {
        let context = try #require(CGContext(
            data: nil, width: 8, height: 12, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.8, green: 0.2, blue: 0.2, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 12))
        let image = try #require(context.makeImage())
        let buffer = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(
            buffer, UTType.png.identifier as CFString, 1, nil
        ))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return buffer as Data
    }
}

/// A transport that answers from a closure, for this suite alone.
final class LookupStub: URLProtocol, @unchecked Sendable {
    enum Answer {
        case response(status: Int, body: Data)
    }

    nonisolated(unsafe) static var answer: (@Sendable (URLRequest) -> Answer)?

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url,
              let answered = Self.answer?(request),
              case let .response(status, body) = answered,
              let response = HTTPURLResponse(
                  url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: [:]
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
