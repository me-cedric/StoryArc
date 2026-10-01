import Catalogue
import CoreGraphics
import Foundation
import ImageIO
import StoryArcCore
import Testing
import UniformTypeIdentifiers

@testable import LibraryFeature

/// A library row filed under an OPDS source draws its artwork, fetched through the
/// catalogue it came from. 11.7 / D29: `OpdsContributor` keeps no acquisition address
/// because such a link can carry a key in its query, so the only way to its cover is to
/// find the entry again by the id the row was filed under.
///
/// `opdsCover(for:maxPixelSize:client:)`'s own `client` parameter is the seam: the
/// production path builds a real one over a real `URLSession`, and this hands it one
/// built over a stubbed `URLSessionConfiguration` instead — `OpdsClientTests`' own way of
/// asserting a client's behaviour without a live catalogue.
///
/// `.serialized`: `Stub.answer` is one static closure shared by every test's client, the
/// same constraint `OpdsClientTests`' own stub has.
@Suite(.serialized)
struct OpdsCoverTests {

    private func onePixelPNG() throws -> Data {
        let context = try #require(
            CGContext(
                data: nil,
                width: 2,
                height: 2,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.setFillColor(CGColor(red: 1, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(
            CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
        )
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    @Test("A row's cover is fetched by finding its entry again, through the source it came from")
    @MainActor
    func fetched() async throws {
        let entryID = "urn:uuid:\(UUID().uuidString)"
        let png = try onePixelPNG()
        let requestedThumbnail = Captured()

        Stub.answer = { request in
            let path = request.url?.path ?? ""
            if path.hasSuffix("thumb/1.jpg") {
                requestedThumbnail.value = true
                return .response(status: 200, headers: [:], body: png)
            }
            if path == "/opds" {
                let atom = """
                <?xml version="1.0"?>
                <feed xmlns="http://www.w3.org/2005/Atom"><title>t</title>
                <entry><title>Tidal Reach</title><id>\(entryID)</id>
                <link rel="http://opds-spec.org/image/thumbnail" href="thumb/1.jpg" type="image/png"/>
                <link rel="http://opds-spec.org/acquisition" href="download/1.epub"
                      type="application/epub+zip"/>
                </entry></feed>
                """
                return .response(status: 200, headers: ["Content-Type": "application/atom+xml"], body: Data(atom.utf8))
            }
            return .response(status: 404, headers: [:], body: Data())
        }

        let sourceID = UUID()
        let url = "https://library.example/opds/"
        let source = Source(id: sourceID, displayName: "Library", kind: .opdsCatalog, locator: url)
        let library = LibraryModel()
        library.registry = SourceRegistry(sources: [source])

        let publication = Publication(
            identity: PublicationIdentity(
                serverIdentifier: .init(sourceID: sourceID, remoteID: "opds:\(entryID)")
            ),
            format: .epub,
            displayTitle: "Tidal Reach",
            origin: .authoritative,
            sourceID: sourceID
        )

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [Stub.self]
        let client = OpdsClient(origin: OpdsOrigin(url: try #require(URL(string: url))), configuration: configuration)

        let cover = await library.opdsCover(for: publication, maxPixelSize: 180, client: client)
        #expect(cover != nil)
        #expect(requestedThumbnail.value == true)
    }

    @Test("A source removed since the row was filed draws nothing, not a crash")
    @MainActor
    func sourceGone() async throws {
        // Another, unrelated OPDS source stays in the registry, and answers through the
        // same stub with a real feed and a real cover — the point is that this row's own
        // sourceID is matched to its own source, not merely that the registry holds
        // something that happens to be reachable. If the wrong source were ever picked,
        // this is a client that would hand back an image for it, rather than one whose
        // own silent failure could pass the assertion below for an unrelated reason.
        let url = "https://other.example/opds/"
        let library = LibraryModel()
        library.registry = SourceRegistry(sources: [
            Source(displayName: "Some Other Library", kind: .opdsCatalog, locator: url),
        ])

        let png = try onePixelPNG()
        Stub.answer = { request in
            if (request.url?.path ?? "").hasSuffix("thumb.jpg") {
                return .response(status: 200, headers: [:], body: png)
            }
            let atom = """
            <?xml version="1.0"?>
            <feed xmlns="http://www.w3.org/2005/Atom"><title>t</title>
            <entry><title>e</title><id>urn:uuid:1</id>
            <link rel="http://opds-spec.org/image/thumbnail" href="thumb.jpg" type="image/png"/>
            <link rel="http://opds-spec.org/acquisition" href="x.epub" type="application/epub+zip"/>
            </entry></feed>
            """
            return .response(status: 200, headers: ["Content-Type": "application/atom+xml"], body: Data(atom.utf8))
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [Stub.self]
        let client = OpdsClient(origin: OpdsOrigin(url: try #require(URL(string: url))), configuration: configuration)

        let publication = Publication(
            identity: PublicationIdentity(
                serverIdentifier: .init(sourceID: UUID(), remoteID: "opds:urn:uuid:1")
            ),
            format: .epub,
            displayTitle: "Gone",
            origin: .authoritative,
            sourceID: UUID()
        )
        let cover = await library.opdsCover(for: publication, maxPixelSize: 180, client: client)
        #expect(cover == nil)
    }

    @Test("A row whose remote id carries no \"opds:\" prefix is never read as one")
    @MainActor
    func notAnOpdsRow() async throws {
        // A real "chapter:" id always arrives beside a Kavita source, never an OPDS one —
        // but the prefix is what this function itself must refuse on, not something it
        // may answer correctly only because another guard happened to catch it too. An
        // OPDS source given a non-"opds:" id is the shape that isolates the one guard
        // from the other.
        let sourceID = UUID()
        let url = "https://library.example/opds/"
        let source = Source(id: sourceID, displayName: "Library", kind: .opdsCatalog, locator: url)
        let library = LibraryModel()
        library.registry = SourceRegistry(sources: [source])

        let publication = Publication(
            identity: PublicationIdentity(
                serverIdentifier: .init(sourceID: sourceID, remoteID: "chapter:1")
            ),
            format: .cbz,
            displayTitle: "A Chapter",
            origin: .authoritative,
            sourceID: sourceID
        )

        // No network call at all is the point: were the id's own prefix not what this
        // function asked about, this is a client that would answer one and let the test
        // pass for the wrong reason.
        let wasAsked = Captured()
        Stub.answer = { _ in
            wasAsked.value = true
            return .response(status: 404, headers: [:], body: Data())
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [Stub.self]
        let client = OpdsClient(origin: OpdsOrigin(url: try #require(URL(string: url))), configuration: configuration)

        let cover = await library.opdsCover(for: publication, maxPixelSize: 180, client: client)
        #expect(cover == nil)
        #expect(wasAsked.value != true)
    }

    @Test("A publication with no server identity at all is never asked for one")
    @MainActor
    func notAServerRow() async {
        let publication = Publication(
            identity: PublicationIdentity(normalizedPath: "/a/b.cbz"),
            format: .cbz,
            displayTitle: "Local",
            origin: .inferred
        )
        let cover = await LibraryModel().opdsCover(for: publication, maxPixelSize: 180)
        #expect(cover == nil)
    }

    @Test("The artwork link is the entry filed under this id, not the first entry the feed listed")
    func artworkLookup() {
        let wanted = OpdsEntry(
            id: "urn:uuid:2",
            title: "Wanted",
            thumbnail: URL(string: "https://library.example/thumb/2.jpg")
        )
        let other = OpdsEntry(
            id: "urn:uuid:1",
            title: "Other",
            thumbnail: URL(string: "https://library.example/thumb/1.jpg")
        )
        #expect(
            LibraryModel.artworkURL(forRemoteID: "opds:urn:uuid:2", in: [other, wanted])
                == URL(string: "https://library.example/thumb/2.jpg")
        )
    }

    @Test("The full cover stands in when the entry offers no thumbnail")
    func artworkFallsBackToCover() {
        let entry = OpdsEntry(
            id: "urn:uuid:1",
            title: "e",
            cover: URL(string: "https://library.example/cover/1.jpg")
        )
        #expect(
            LibraryModel.artworkURL(forRemoteID: "opds:urn:uuid:1", in: [entry])
                == URL(string: "https://library.example/cover/1.jpg")
        )
    }

    @Test("No entry matches the id, and no entry at all offers artwork")
    func artworkMissing() {
        let entry = OpdsEntry(id: "urn:uuid:1", title: "e")
        #expect(LibraryModel.artworkURL(forRemoteID: "opds:urn:uuid:9", in: [entry]) == nil)
        #expect(LibraryModel.artworkURL(forRemoteID: "opds:urn:uuid:1", in: [entry]) == nil)
    }

    /// A box, because the stub runs on the session's queue and the test reads afterwards.
    /// `OpdsClientTests` carries the same one under the same name.
    private final class Captured: @unchecked Sendable {
        var value: Bool?
    }

    /// A transport that answers from a closure. iOS's `OpdsClientTests` carries the same
    /// shape under the same name, in a different module — each suite's stub answers only
    /// that suite's own client.
    private final class Stub: URLProtocol, @unchecked Sendable {
        enum Answer {
            case response(status: Int, headers: [String: String], body: Data)
        }

        nonisolated(unsafe) static var answer: (@Sendable (URLRequest) -> Answer)?

        override static func canInit(with request: URLRequest) -> Bool { true }
        override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            guard let answered = Self.answer?(request),
                  case let .response(status, headers, body) = answered,
                  let url = request.url,
                  let response = HTTPURLResponse(
                      url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers
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
}
