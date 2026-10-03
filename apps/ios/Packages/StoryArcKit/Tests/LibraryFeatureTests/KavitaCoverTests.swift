import CoreGraphics
import Foundation
import ImageIO
import Kavita
import Persistence
import StoryArcCore
import Testing
import UniformTypeIdentifiers

@testable import LibraryFeature

/// A library row filed under a Kavita server draws its artwork, fetched through the
/// server's own chapter-cover route. 17.4: `KavitaContributor` makes a chapter row with no
/// file location at all — the shelf path never asked a server for one, where Android's
/// `ServerLibrary.cachedCover` already did.
///
/// `kavitaCover(for:maxPixelSize:client:credentials:)`'s own `client` and `credentials`
/// parameters are the seam: the production path builds a real client over a real
/// `URLSession` and reads the real keychain, and this hands it one built over a stubbed
/// `URLSessionConfiguration` and an in-memory `CredentialStore` instead.
///
/// `.serialized`: `Stub.answer` is one static closure shared by every test's client, the
/// same constraint `OpdsCoverTests`' own stub has.
@Suite(.serialized)
struct KavitaCoverTests {

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
        context.setFillColor(CGColor(red: 0, green: 1, blue: 0, alpha: 1))
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

    private let sourceID = UUID()

    /// A model whose registry holds one reachable Kavita source, named `sourceID`, and the
    /// in-memory keychain that holds its key.
    @MainActor
    private func modelWithReachableSource() throws -> (LibraryModel, CredentialStore) {
        let credentials = CredentialStore(service: "app.storyarc.tests.\(UUID().uuidString)")
        let reference = CredentialStore.reference(for: sourceID)
        #expect(credentials.save("api-key", for: reference))
        let source = Source(
            id: sourceID,
            displayName: "Attic",
            kind: .kavitaServer,
            credentialReference: reference,
            locator: "https://kavita.example"
        )
        let model = LibraryModel()
        model.registry = SourceRegistry(sources: [source])
        return (model, credentials)
    }

    private func publication(remoteID: String = "chapter:3103") -> Publication {
        Publication(
            identity: PublicationIdentity(serverIdentifier: .init(sourceID: sourceID, remoteID: remoteID)),
            format: .cbz,
            displayTitle: "Issue #43",
            origin: .authoritative,
            sourceID: sourceID
        )
    }

    @Test("A chapter row's cover is fetched through the server's chapter-cover route")
    @MainActor
    func fetched() async throws {
        let png = try onePixelPNG()
        let requestedChapterCover = Captured()

        Stub.answer = { request in
            let path = request.url?.path ?? ""
            // The client exchanges the API key for a session token before its first request,
            // same as `OpdsClientTests`' own stub answers a feed only after whatever setup
            // its client needs.
            if path.hasSuffix("Plugin/authenticate") {
                return .response(
                    status: 200, headers: [:],
                    body: Data(#"{"username":"reader","token":"test-token"}"#.utf8)
                )
            }
            let query = request.url
                .flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?.queryItems ?? []
            if path.hasSuffix("Image/chapter-cover"),
               query.contains(where: { $0.name == "chapterId" && $0.value == "3103" }) {
                requestedChapterCover.value = true
                return .response(status: 200, headers: [:], body: png)
            }
            return .response(status: 404, headers: [:], body: Data())
        }

        let (model, credentials) = try modelWithReachableSource()
        defer { credentials.remove(CredentialStore.reference(for: sourceID)) }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [Stub.self]
        let client = KavitaClient(
            address: KavitaAddress(base: try #require(URL(string: "https://kavita.example")), apiKey: "api-key"),
            configuration: configuration
        )

        let cover = await model.kavitaCover(
            for: publication(), maxPixelSize: 180, client: client, credentials: credentials
        )
        #expect(cover != nil)
        #expect(requestedChapterCover.value == true)
    }

    @Test("A source removed since the row was filed draws nothing, not a crash")
    @MainActor
    func sourceGone() async throws {
        let model = LibraryModel()
        model.registry = SourceRegistry(sources: [])

        let wasAsked = Captured()
        Stub.answer = { _ in
            wasAsked.value = true
            return .response(status: 200, headers: [:], body: Data())
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [Stub.self]
        let client = KavitaClient(
            address: KavitaAddress(base: try #require(URL(string: "https://kavita.example")), apiKey: "api-key"),
            configuration: configuration
        )

        let cover = await model.kavitaCover(
            for: publication(), maxPixelSize: 180, client: client, credentials: CredentialStore()
        )
        #expect(cover == nil)
        #expect(wasAsked.value != true)
    }

    @Test("A row whose remote id carries no \"chapter:\" prefix is never read as one")
    @MainActor
    func notAKavitaRow() async throws {
        let (model, credentials) = try modelWithReachableSource()
        defer { credentials.remove(CredentialStore.reference(for: sourceID)) }

        let wasAsked = Captured()
        Stub.answer = { _ in
            wasAsked.value = true
            return .response(status: 200, headers: [:], body: Data())
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [Stub.self]
        let client = KavitaClient(
            address: KavitaAddress(base: try #require(URL(string: "https://kavita.example")), apiKey: "api-key"),
            configuration: configuration
        )

        let cover = await model.kavitaCover(
            for: publication(remoteID: "opds:9"), maxPixelSize: 180, client: client, credentials: credentials
        )
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
        let cover = await LibraryModel().kavitaCover(for: publication, maxPixelSize: 180)
        #expect(cover == nil)
    }

    /// A box, because the stub runs on the session's queue and the test reads afterwards.
    /// `OpdsCoverTests` carries the same one under the same name.
    private final class Captured: @unchecked Sendable {
        var value: Bool?
    }
}

/// A transport that answers from a closure. `OpdsCoverTests`, in this same test target,
/// carries the same shape under the same name — each is `private` to its own file, so each
/// suite's own `Stub` answers only that suite's client rather than the two colliding.
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
