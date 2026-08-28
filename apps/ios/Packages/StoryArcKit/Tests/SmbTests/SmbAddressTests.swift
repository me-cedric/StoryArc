import Foundation
import Testing

@testable import Smb

@Suite("SMB address")
struct SmbAddressTests {

    @Test("reads an smb url")
    func readsSmbUrl() {
        let address = SmbAddress.parse("smb://nas.local/Comics/Manga")
        #expect(address?.host == "nas.local")
        #expect(address?.share == "Comics")
        #expect(address?.path == "Manga")
    }

    @Test("reads the windows form, which is what a reader has to hand")
    func readsWindowsForm() {
        let address = SmbAddress.parse(#"\\nas.local\Comics\Manga\Ongoing"#)
        #expect(address?.host == "nas.local")
        #expect(address?.share == "Comics")
        #expect(address?.path == "Manga/Ongoing")
    }

    @Test("keeps a port when one is given")
    func keepsPort() {
        #expect(SmbAddress.parse("smb://localhost:4445/Comics")?.port == 4445)
    }

    @Test("refuses a host with no share, which names nothing to read")
    func refusesHostAlone() {
        #expect(SmbAddress.parse("smb://nas.local") == nil)
        #expect(SmbAddress.parse("") == nil)
    }

    @Test("a nameless connection is a guest one")
    func guestWhenNameless() {
        #expect(SmbAddress(host: "nas", share: "Comics").isGuest)
        #expect(!SmbAddress(host: "nas", share: "Comics", username: "ada").isGuest)
    }
}
