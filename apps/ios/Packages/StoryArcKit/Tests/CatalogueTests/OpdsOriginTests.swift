import Foundation
import Testing

@testable import Catalogue

/// Where a credential is allowed to travel.
///
/// A catalogue names every address the app then fetches — covers, next pages, acquisition
/// links. A feed that names an attacker's host and is handed the reader's Basic password has
/// collected it, and the cover path fires unattended as the grid scrolls. So the configured
/// source's origin travels beside the credential and decides.
///
/// Android's `OpdsOriginTest` asserts the same cases in the same order.
struct OpdsOriginTests {
    private func url(_ string: String) throws -> URL {
        try #require(URL(string: string))
    }

    private func origin(_ string: String) throws -> OpdsOrigin {
        try #require(OpdsOrigin(url: url(string)))
    }

    @Test func anOriginIsSchemeHostAndPort() throws {
        let books = try origin("https://books.example/opds/")
        #expect(books.scheme == "https")
        #expect(books.host == "books.example")
        // The scheme's own default, so `https://a` and `https://a:443` are one origin.
        #expect(books.port == 443)
    }

    @Test func anOriginAdmitsOnlyItself() throws {
        let books = try origin("https://books.example/opds/")
        #expect(books.admits(try url("https://books.example/covers/1.jpg")))
        #expect(books.admits(try url("https://books.example:443/x")))
        #expect(!books.admits(try url("https://collect.attacker.example/x")))
        #expect(!books.admits(try url("http://books.example/x")))
        #expect(!books.admits(try url("https://books.example:8443/x")))
    }

    @Test func nothingButHttpIsAnOrigin() throws {
        #expect(OpdsOrigin(url: try url("file:///etc/hosts")) == nil)
        #expect(OpdsOrigin(url: try url("ftp://books.example/x")) == nil)
    }

    @Test func onlyHttpAndHttpsAreFetchable() throws {
        #expect(OpdsOrigin.isFetchable(try url("https://books.example/x")))
        #expect(OpdsOrigin.isFetchable(try url("http://nas.local/x")))
        #expect(!OpdsOrigin.isFetchable(try url("file:///etc/hosts")))
        #expect(!OpdsOrigin.isFetchable(try url("ftp://books.example/x")))
    }

    @Test func anHttpsSourceRefusesToBeTalkedDownToHttp() throws {
        let secure = try origin("https://books.example/opds/")
        #expect(secure.downgrades(try url("http://books.example/covers/1.jpg")))
        #expect(!secure.downgrades(try url("https://books.example/covers/1.jpg")))

        // A reader who typed `http://nas.local` meant it. Nothing is downgraded from there.
        let plain = try origin("http://nas.local:8080/opds")
        #expect(!plain.downgrades(try url("http://nas.local:8080/1.jpg")))
    }
}
