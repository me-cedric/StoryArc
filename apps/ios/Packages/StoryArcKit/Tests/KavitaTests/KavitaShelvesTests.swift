import Foundation
import Testing

@testable import Kavita

/// Putting a local reading list on a server, and taking it back off again.
///
/// `collections-and-reading-lists` asks for a local list to be copied onto a server, and the
/// house makes an action of that shape undoable for ten seconds — which for a list the server
/// now holds means asking the server to drop it. Android's `KavitaShelvesTest` makes the same
/// four claims in the same order.
struct KavitaShelvesTests {
    /// What the stub was asked, so a test can check the verb and the address rather than
    /// only the answer.
    private final class Asked: @unchecked Sendable {
        var method: String?
        var path: String?
        var query: String?
    }

    private func client(
        _ asked: Asked,
        status: Int = 200,
        body: String = #"{"id":7,"title":"Crossover"}"#
    ) throws -> KavitaClient {
        let host = "\(UUID().uuidString).example"
        let configuration = KavitaStub.session(host: host) { request in
            if request.url?.path().contains("authenticate") == true {
                return .response(status: 200, body: Data(#"{"username":"ada","token":"t"}"#.utf8))
            }
            asked.method = request.httpMethod
            asked.path = request.url?.path()
            asked.query = request.url?.query()
            return .response(status: status, body: Data(body.utf8))
        }
        let address = try #require(KavitaAddress.from(base: "https://\(host)", apiKey: "key"))
        return KavitaClient(address: address, configuration: configuration)
    }

    @Test("Creating a list answers with the id the server minted")
    func createAnswersWithTheServersOwnId() async throws {
        // Everything that follows — the entries, and the undo — is addressed by it, so a
        // create that answered with nothing would leave the copy unable to finish.
        let made = try await client(Asked()).createList(named: "Crossover")
        #expect(made.id == 7)
        #expect(made.title == "Crossover")
    }

    @Test("Creating a list posts the name to the server's own endpoint")
    func createPostsTheName() async throws {
        let asked = Asked()
        _ = try await client(asked).createList(named: "Crossover")
        #expect(asked.method == "POST")
        #expect(asked.path == "/api/ReadingList/create")
    }

    @Test("Deleting a list names the one to drop")
    func deleteNamesTheList() async throws {
        let asked = Asked()
        try await client(asked, body: "true").deleteList(7)
        #expect(asked.method == "DELETE")
        #expect(asked.path == "/api/ReadingList")
        #expect(asked.query == "readingListId=7")
    }

    @Test("A server that refuses the create says so rather than answering with an empty list")
    func aRefusedCreateThrows() async throws {
        // The copy has to stop here. Carrying on would append entries to a list id that does
        // not exist, and report a copy that never happened.
        let client = try client(Asked(), status: 500, body: #"{"message":"no"}"#)
        await #expect(throws: KavitaError.http(status: 500)) {
            _ = try await client.createList(named: "Crossover")
        }
    }
}
