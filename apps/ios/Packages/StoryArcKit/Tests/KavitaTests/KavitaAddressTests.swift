import Foundation
import Testing

@testable import Kavita

@Suite("Kavita address")
struct KavitaAddressTests {
    @Test("A pasted OPDS URL yields the base and the key")
    func fromOpds() throws {
        // `kavita-server`: the app "extracts the base URL and key and configures a native
        // Kavita source rather than a generic OPDS source".
        let address = try #require(
            KavitaAddress.fromOpds("https://kavita.example/api/opds/abc123def")
        )
        #expect(address.base.absoluteString == "https://kavita.example")
        #expect(address.apiKey == "abc123def")
    }

    @Test("A server behind a reverse-proxy subpath keeps its prefix")
    func fromOpdsWithAPrefix() throws {
        // Kavita behind `/books` is a common home-server setup, and dropping the prefix
        // would send every later request to a path the proxy does not serve.
        let address = try #require(
            KavitaAddress.fromOpds("https://home.example/books/api/opds/key")
        )
        #expect(address.base.absoluteString == "https://home.example/books")
        #expect(address.apiKey == "key")
    }

    @Test("A port survives")
    func fromOpdsWithAPort() throws {
        let address = try #require(
            KavitaAddress.fromOpds("http://192.168.1.10:5000/api/opds/key")
        )
        #expect(address.base.absoluteString == "http://192.168.1.10:5000")
    }

    @Test("Something that is not a Kavita OPDS URL is refused")
    func notAKavitaUrl() {
        // Refused rather than guessed, so the caller can fall back to asking for the base
        // and the key separately instead of configuring a server that does not exist.
        #expect(KavitaAddress.fromOpds("https://kavita.example/api/opds") == nil)
        #expect(KavitaAddress.fromOpds("https://calibre.example/opds") == nil)
        #expect(KavitaAddress.fromOpds("https://kavita.example/") == nil)
        #expect(KavitaAddress.fromOpds("not a url") == nil)
        #expect(KavitaAddress.fromOpds("") == nil)
    }

    @Test("A typed base is tidied rather than refused")
    func fromTypedBase() throws {
        // A trailing slash and a pasted `/api` are things a reader copies out of a browser
        // bar. Neither is a mistake worth an error message.
        for typed in [
            "https://kavita.example",
            "https://kavita.example/",
            "https://kavita.example/api",
            "https://kavita.example/api/",
            "kavita.example",
        ] {
            let address = try #require(KavitaAddress.from(base: typed, apiKey: "k"))
            #expect(address.base.absoluteString == "https://kavita.example", "\(typed)")
        }
    }

    @Test("A missing key or host is refused")
    func incomplete() {
        #expect(KavitaAddress.from(base: "https://kavita.example", apiKey: "  ") == nil)
        #expect(KavitaAddress.from(base: "  ", apiKey: "k") == nil)
        #expect(KavitaAddress.from(base: "https://", apiKey: "k") == nil)
    }

    @Test("An endpoint hangs off the base, under api")
    func endpoints() throws {
        let address = try #require(KavitaAddress.from(base: "https://k.example/books", apiKey: "k"))
        let url = try #require(address.endpoint("Library/libraries"))
        #expect(url.absoluteString == "https://k.example/books/api/Library/libraries")
    }

    @Test("Describing an address never says what the key is")
    func descriptionRedactsTheKey() throws {
        let secret = "s3cret-api-key"
        let address = try #require(KavitaAddress.from(base: "https://k.example", apiKey: secret))

        // Every way a value reaches a string, because the leak is whichever one nobody
        // thought of. Android's `KavitaAddressTest` makes the same claim.
        #expect(!address.description.contains(secret))
        #expect(!address.debugDescription.contains(secret))
        #expect(!"\(address)".contains(secret))
        #expect(!String(describing: address).contains(secret))
        #expect(!String(reflecting: address).contains(secret))
        #expect(address.description.contains("k.example"))
    }
}
