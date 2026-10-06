import Foundation
import Testing

@testable import Kavita

/// Writing a cover back to the one Kavita route a normal reader may use.
///
/// Android's `KavitaCoverUploadTest` makes the same claims in the same order.
struct KavitaCoverUploadTests {
    private final class Asked: @unchecked Sendable {
        var method: String?
        var path: String?
        var body: String?
        var count = 0
    }

    private func client(_ asked: Asked, status: Int = 200) throws -> KavitaClient {
        let host = "\(UUID().uuidString).example"
        let configuration = KavitaStub.session(host: host) { request in
            if request.url?.path().contains("authenticate") == true {
                return .response(status: 200, body: Data(#"{"username":"ada","token":"t"}"#.utf8))
            }
            asked.count += 1
            asked.method = request.httpMethod
            asked.path = request.url?.path()
            asked.body = KavitaStub.body(of: request)
            return .response(status: status, body: Data("{}".utf8))
        }
        let address = try #require(KavitaAddress.from(base: "https://\(host)", apiKey: "key"))
        return KavitaClient(address: address, configuration: configuration)
    }

    @Test("The cover is posted once, as base64, to the reading-list upload route")
    func postsOnceAsBase64() async throws {
        let asked = Asked()
        let image = Data([0xFF, 0xD8, 0xFF, 0xE0])

        try await client(asked).uploadReadingListCover(7, image: image)

        #expect(asked.method == "POST")
        #expect(asked.path == "/api/Upload/reading-list")
        #expect(asked.count == 1)
        // Decoded rather than matched as text: Foundation escapes a forward slash in a JSON
        // string, and base64 is full of them, so a substring check reads a correct body as
        // wrong.
        let body = try #require(asked.body)
        let sent = try #require(
            JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any]
        )
        #expect(sent["id"] as? Int == 7)
        #expect(sent["url"] as? String == image.base64EncodedString())
    }

    @Test("A picture above the ceiling is refused before anything is sent")
    func refusesAPictureAboveTheCeiling() async throws {
        // `design.md` fixes the ceiling at eight megabytes. Refused here rather than by the
        // server: a rejected body is a wasted upload on a connection a reader may be paying
        // for, and a 413 says nothing about which limit was passed.
        let asked = Asked()
        let client = try client(asked)
        let image = Data(repeating: 0xFF, count: KavitaClient.coverUploadCeiling + 1)

        await #expect(throws: KavitaError.imageTooLarge) {
            try await client.uploadReadingListCover(7, image: image)
        }
        #expect(asked.count == 0)
    }

    @Test("An empty picture is refused too")
    func refusesAnEmptyPicture() async throws {
        let asked = Asked()
        let client = try client(asked)

        await #expect(throws: KavitaError.imageRejected) {
            try await client.uploadReadingListCover(7, image: Data())
        }
        #expect(asked.count == 0)
    }

    @Test("An older Kavita without the route says so once")
    func reportsAMissingRoute() async throws {
        // `sendVersioned` reads a 404 as the route being absent and remembers it, so a
        // reader on an older server is told once rather than on every attempt.
        let asked = Asked()
        let client = try client(asked, status: 404)

        await #expect(throws: KavitaError.routeMissing(path: "Upload/reading-list")) {
            try await client.uploadReadingListCover(7, image: Data([0xFF]))
        }
    }

    @Test("A list the server promoted decodes as promoted")
    func decodesPromoted() throws {
        // The one ownership signal a client gets, and what `CoverWriteBack` reads.
        let promoted = #"{"id":7,"title":"Staff picks","promoted":true}"#
        let own = #"{"id":8,"title":"Mine"}"#
        let decoder = JSONDecoder()

        #expect(
            try decoder.decode(KavitaReadingList.self, from: Data(promoted.utf8)).promoted
        )
        #expect(
            try !decoder.decode(KavitaReadingList.self, from: Data(own.utf8)).promoted
        )
    }
}
