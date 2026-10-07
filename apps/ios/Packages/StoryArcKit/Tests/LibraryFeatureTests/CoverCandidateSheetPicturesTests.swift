import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

import Catalogue
@testable import LibraryFeature
import StoryArcCore

/// The candidate sheet shows each picture, and shows it through the client.
///
/// Task 6.3 of `cover-for-every-publication`. The sheet loaded pictures with `AsyncImage` on
/// the shared session, which checks neither the setting nor the host, and keyed its rows on
/// the picture's address, which two equal answers share. Android's
/// `CoverCandidateSheetPicturesTest` is the twin of this file.
@Suite("The candidate sheet's pictures", .serialized)
struct CoverCandidateSheetPicturesTests {

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

    private let listed = CoverCandidate(
        title: "Fine Print",
        imageURL: URL(string: "https://covers.openlibrary.org/b/id/1-L.jpg")!,
        provider: .openLibrary
    )

    private let unlisted = CoverCandidate(
        title: "Elsewhere",
        imageURL: URL(string: "https://tracker.example/c.jpg")!,
        provider: .openLibrary
    )

    private func client(enabled: Bool = true, _ asked: Asked) throws -> CoverLookupClient {
        let picture = try pngData()
        SheetStub.answer = { request in
            asked.append(request.url)
            return .response(status: 200, body: picture)
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SheetStub.self]
        let cache = CoverLookupCache(
            file: URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("\(UUID().uuidString).json")
        )
        return CoverLookupClient(isEnabled: { enabled }, cache: cache, configuration: configuration)
    }

    @Test("A candidate's picture is drawn, fetched through the client")
    func drawsAListedPicture() async throws {
        let asked = Asked()

        let picture = await CoverCandidatePicture.picture(for: listed, via: try client(asked))

        #expect(picture != nil)
        #expect(asked.value == [listed.imageURL])
    }

    @Test("A picture from a host the setting does not name is not requested and not drawn")
    func refusesAnUnlistedHost() async throws {
        let asked = Asked()

        let picture = await CoverCandidatePicture.picture(for: unlisted, via: try client(asked))

        #expect(picture == nil)
        #expect(asked.value.isEmpty)
    }

    @Test("No picture is requested while the setting is off")
    func staysQuietWhileOff() async throws {
        let asked = Asked()

        let picture = await CoverCandidatePicture.picture(
            for: listed, via: try client(enabled: false, asked)
        )

        #expect(picture == nil)
        #expect(asked.value.isEmpty)
    }

    @Test("Two equal answers are two rows with two identities")
    func equalAnswersHaveDistinctRows() {
        let rows = CoverCandidatePicture.rows([listed, listed, unlisted])

        #expect(rows.count == 3)
        #expect(Set(rows.map(\.id)).count == 3, "Two equal answers shared a row identity.")
        #expect(rows.map(\.candidate) == [listed, listed, unlisted])
    }

    @Test("The same address answered by two catalogues is two rows")
    func twoCataloguesAreTwoRows() {
        let other = CoverCandidate(
            title: "Fine Print", imageURL: listed.imageURL, provider: .aniList
        )

        let rows = CoverCandidatePicture.rows([listed, other])

        #expect(rows[0].id != rows[1].id)
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

/// A transport that answers from a closure, for this suite alone. Not shared with
/// `CoverLookupRungTests`: two suites run side by side and would answer each other.
private final class SheetStub: URLProtocol, @unchecked Sendable {
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
