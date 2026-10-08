import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

import Catalogue
import Formats
@testable import LibraryFeature
import StoryArcCore

/// Tasks 6.2, 4.1 and 3.3 of `cover-for-every-publication`: the publication page offers the
/// title search and the web search, and a tap on a candidate is the only way one is adopted.
/// Android's `CoverFinderTest` is the twin of this file.
@Suite("The publication page finds a cover", .serialized)
@MainActor
struct CoverFinderTests {

    private let candidate = CoverCandidate(
        title: "Fine Print",
        imageURL: URL(string: "https://covers.openlibrary.org/b/id/1-L.jpg")!,
        provider: .openLibrary
    )

    private let elsewhere = CoverCandidate(
        title: "Elsewhere",
        imageURL: URL(string: "https://tracker.example/c.jpg")!,
        provider: .openLibrary
    )

    private let publication = Publication(
        identity: PublicationIdentity(contentDigest: "finder-digest"),
        format: .epub,
        displayTitle: "Fine Print",
        authors: ["Ada"],
        origin: .inferred
    )

    private func rung(enabled: Bool) -> CoverLookupRung {
        CoverLookupRung(
            isEnabled: { enabled },
            client: CoverLookupClient(isEnabled: { enabled }),
            identify: { _, _ in nil }
        )
    }

    // MARK: What the page offers

    @Test("While the lookup is off there is no title search, and the web search is still there")
    func offOffersOnlyTheWebSearch() {
        let offer = LibraryModel().coverFinderOffer(through: rung(enabled: false))

        #expect(!offer.findACover)
        #expect(offer.webSearch)
    }

    @Test("While the lookup is on both are offered")
    func onOffersBoth() {
        let offer = LibraryModel().coverFinderOffer(through: rung(enabled: true))

        #expect(offer.findACover)
        #expect(offer.webSearch)
    }

    @Test("The hand-off opens an image search for the title and the first author")
    func handOffAddress() throws {
        var opened: URL?
        let handoff = CoverSearchHandoff(
            title: publication.displayTitle, author: publication.authors.first, open: { opened = $0 }
        )

        handoff.open(try #require(handoff.destination))

        #expect(opened?.host() == "duckduckgo.com")
        #expect(opened?.query()?.contains("Fine%20Print") == true)
        #expect(opened?.query()?.contains("Ada") == true)
    }

    // MARK: Adoption

    private func client(status: Int = 200, _ asked: FinderAsked) throws -> CoverLookupClient {
        let picture = try pngData()
        FinderStub.answer = { request in
            asked.append(request.url)
            return .response(status: status, body: status == 200 ? picture : Data())
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FinderStub.self]
        let cache = CoverLookupCache(
            file: URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("\(UUID().uuidString).json")
        )
        return CoverLookupClient(isEnabled: { true }, cache: cache, configuration: configuration)
    }

    private func temporaryStore() -> (CoverOverrideStore, URL) {
        let directory = URL.temporaryDirectory.appending(path: "finder-\(UUID().uuidString)")
        return (CoverOverrideStore(directory: directory), directory)
    }

    @Test("A tap on a candidate stores its picture in the override store")
    func tapStoresThePicture() async throws {
        let asked = FinderAsked()
        let (store, directory) = temporaryStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(store.file(for: publication) == nil, "The store was not empty to begin with.")

        let stored = await LibraryModel().adoptCandidate(
            candidate, for: publication, via: try client(asked), in: store
        )

        #expect(stored)
        #expect(store.file(for: publication) != nil, "The tap did not reach the override store.")
        #expect(asked.value == [candidate.imageURL])
    }

    @Test("A picture that does not arrive leaves the cover as it was")
    func missingPictureStoresNothing() async throws {
        let asked = FinderAsked()
        let (store, directory) = temporaryStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let stored = await LibraryModel().adoptCandidate(
            candidate, for: publication, via: try client(status: 404, asked), in: store
        )

        #expect(!stored)
        #expect(store.file(for: publication) == nil)
    }

    @Test("A candidate on a host the setting does not name is neither fetched nor stored")
    func unlistedHostStoresNothing() async throws {
        let asked = FinderAsked()
        let (store, directory) = temporaryStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let stored = await LibraryModel().adoptCandidate(
            elsewhere, for: publication, via: try client(asked), in: store
        )

        #expect(!stored)
        #expect(asked.value.isEmpty)
        #expect(store.file(for: publication) == nil)
    }

    @Test("Only the tap handler adopts: the search that fills the sheet stores nothing")
    func searchNeverAdopts() throws {
        // The sheet runs one search when it opens and then waits. Adoption is one function,
        // and the only call to it must be the row's own handler, never the `.task` that asks.
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/LibraryFeature/CoverFinder.swift")
        let text = try #require(
            try? String(contentsOf: file, encoding: .utf8),
            "\(file.path) could not be read. A guard that cannot find what it guards passes for ever."
        )
        let task = try #require(text.range(of: ".task(id: publication.id)"))
        let afterTask = String(text[task.lowerBound...])
        let block = String(afterTask.prefix(upTo: try #require(afterTask.range(of: "private func choose"))
            .lowerBound))
        #expect(!block.contains("adoptCandidate"), "The search adopts a candidate before any tap.")
        let mentions = text.components(separatedBy: "adoptCandidate(").count - 1
        #expect(mentions == 2, "Expected the declaration and one call.")
    }

    private func pngData() throws -> Data {
        let context = try #require(CGContext(
            data: nil, width: 8, height: 12, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
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

/// The addresses a stub transport saw, safe to write from the loader's own queue.
private final class FinderAsked: @unchecked Sendable {
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

/// A transport that answers from a closure, for this suite alone. Not shared with the other
/// stubs: suites run side by side and would answer each other.
private final class FinderStub: URLProtocol, @unchecked Sendable {
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
