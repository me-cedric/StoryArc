import Foundation
import Testing

@testable import Kavita

/// Putting a local reading list on a server, and taking it back off again.
///
/// `collections-and-reading-lists` asks for a local list to be copied onto a server, and the
/// house makes an action of that shape undoable for ten seconds — which for a list the server
/// now holds means asking the server to drop it. Android's `KavitaShelvesTest` makes the same
/// nine claims in the same order.
struct KavitaShelvesTests {
    /// What the stub was asked, so a test can check the verb and the address rather than
    /// only the answer.
    private final class Asked: @unchecked Sendable {
        var method: String?
        var path: String?
        var query: String?
    }

    /// What was posted, so a test can check the fields Kavita reads rather than only the
    /// address they were sent to.
    private final class Sent: @unchecked Sendable {
        var body: String?
    }

    private func client(
        _ asked: Asked,
        sent: Sent = Sent(),
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
            sent.body = KavitaStub.body(of: request)
            return .response(status: status, body: Data(body.utf8))
        }
        let address = try #require(KavitaAddress.from(base: "https://\(host)", apiKey: "key"))
        return KavitaClient(address: address, configuration: configuration)
    }

    /// A client whose server answers the create with nothing and the read-back with a list,
    /// which is the exchange a collection create actually is.
    private func collectionClient(
        _ asked: Asked,
        sent: Sent,
        listing: String = #"[{"id":4,"title":"Attic"}]"#,
        after: String? = nil
    ) throws -> KavitaClient {
        let host = "\(UUID().uuidString).example"
        let configuration = KavitaStub.session(host: host) { request in
            if request.url?.path().contains("authenticate") == true {
                return .response(status: 200, body: Data(#"{"username":"ada","token":"t"}"#.utf8))
            }
            if request.httpMethod == "GET" {
                // `asked.method` is set by the post below, so it says which side of the create
                // this read is on — which is what lets a test change what the server holds.
                let listed = asked.method == nil ? listing : (after ?? listing)
                return .response(status: 200, body: Data(listed.utf8))
            }
            asked.method = request.httpMethod
            asked.path = request.url?.path()
            sent.body = KavitaStub.body(of: request)
            return .response(status: 200, body: Data("{}".utf8))
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

    @Test("Moving an entry names the list, the entry, and both positions")
    func moveNamesTheEntryAndBothPositions() async throws {
        // Kavita moves by position and by entry together. A client that sent one without the
        // other would move whatever happens to sit there now.
        let asked = Asked()
        let sent = Sent()
        try await client(asked, sent: sent, body: "{}").moveInList(7, item: 3, from: 2, to: 0)
        #expect(asked.method == "POST")
        #expect(asked.path == "/api/ReadingList/update-position")
        #expect(sent.body?.contains(#""readingListId":7"#) == true)
        #expect(sent.body?.contains(#""readingListItemId":3"#) == true)
        #expect(sent.body?.contains(#""fromPosition":2"#) == true)
        #expect(sent.body?.contains(#""toPosition":0"#) == true)
    }

    @Test("A move the server refuses is not reported as a move that happened")
    func aRefusedMoveThrows() async throws {
        // Which is what lets the order stay queued: a caller that swallowed this would drop
        // the reader's order on the floor and say nothing.
        let client = try client(Asked(), status: 400, body: #"{"message":"no"}"#)
        await #expect(throws: KavitaError.http(status: 400)) {
            try await client.moveInList(7, item: 3, from: 2, to: 0)
        }
    }

    @Test("Creating a collection posts the name with no tag, which is how Kavita makes one")
    func createCollectionPostsTheNameWithNoTag() async throws {
        let asked = Asked()
        let sent = Sent()
        let made = try await collectionClient(asked, sent: sent).createCollection(named: "Attic")
        #expect(asked.method == "POST")
        #expect(asked.path == "/api/Collection/update-for-series")
        #expect(sent.body?.contains(#""collectionTagId":0"#) == true)
        #expect(sent.body?.contains(#""collectionTagTitle":"Attic""#) == true)
        // Read back, because the bulk-add answers with nothing and the id is what everything
        // after this is addressed by.
        #expect(made.id == 4)
        #expect(made.title == "Attic")
    }

    @Test("A collection made where the server already holds that name answers with the new one")
    func createCollectionAnswersWithTheMintedId() async throws {
        // Kavita lists collections by title, so two of one name have no reliable order and a
        // read-back that matched on the name could address somebody else's collection.
        let made = try await collectionClient(
            Asked(),
            sent: Sent(),
            listing: #"[{"id":4,"title":"Attic"}]"#,
            after: #"[{"id":9,"title":"Attic"},{"id":4,"title":"Attic"}]"#
        ).createCollection(named: "Attic")
        #expect(made.id == 9)
    }

    @Test("A collection the server never lists is not answered as if it had been made")
    func aCollectionTheServerNeverListsThrows() async throws {
        let client = try collectionClient(Asked(), sent: Sent(), listing: "[]")
        await #expect(throws: KavitaError.unexpectedResponse) {
            _ = try await client.createCollection(named: "Attic")
        }
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
