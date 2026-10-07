import Foundation
import Testing

import SMBClient

/// The SMB 3 primitives the vendored client added, checked against published values.
///
/// AES-CMAC signs every SMB 3 message that is not sealed, so it is checked against the four
/// RFC 4493 vectors, which cover an empty message, one whole block, a part block and four
/// whole blocks. AES-CCM and AES-GCM are checked for what a reader depends on: the bytes
/// come back, and a changed byte or a wrong session is refused. `SmbDialectMatrixTests`
/// checks both ciphers against Samba.
@Suite("SMB 3 cryptography")
struct SMB3CryptoTests {
    private static func bytes(_ hex: String) -> Data {
        var data = Data()
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            data.append(UInt8(hex[index..<next], radix: 16) ?? 0)
            index = next
        }
        return data
    }

    private static let cmacKey = bytes("2b7e151628aed2a6abf7158809cf4f3c")
    private static let rfcMessage = bytes(
        "6bc1bee22e409f96e93d7e117393172aae2d8a571e03ac9c9eb76fac45af8e51"
            + "30c81c46a35ce411e5fbc1191a0a52eff69f2445df4f9b17ad2b417be66c3710"
    )

    @Test(
        "AES-CMAC gives the RFC 4493 tags",
        arguments: [
            (0, "bb1d6929e95937287fa37d129b756746"),
            (16, "070a16b46b4d4144f79bdd9dd04a287c"),
            (40, "dfa66747de9ae63030ca32611497c827"),
            (64, "51f0bebf7e3b9d92fc49741779363cfe"),
        ]
    )
    func cmacMatchesRFC4493(length: Int, tag: String) {
        let mac = SMB3Crypto.cmac(key: Self.cmacKey, message: Self.rfcMessage.prefix(length))
        #expect(mac == Self.bytes(tag))
    }

    private static let key = bytes("000102030405060708090a0b0c0d0e0f")
    private static let message = Data((0..<1000).map { UInt8(truncatingIfNeeded: $0 &* 7) })

    @Test("A sealed message opens with its key, for both ciphers", arguments: [SMB3Cipher.aes128CCM, .aes128GCM])
    func sealsAndOpens(_ cipher: SMB3Cipher) throws {
        let transform = try Self.seal(cipher, sessionId: 42)
        let opened = try SMB3Transform.open(transform, cipher: cipher, key: Self.key, sessionId: 42)
        #expect(opened == Self.message)
        #expect(!transform.suffix(Self.message.count).elementsEqual(Self.message))
    }

    @Test("A changed byte is refused, for both ciphers", arguments: [SMB3Cipher.aes128CCM, .aes128GCM])
    func refusesAChangedByte(_ cipher: SMB3Cipher) throws {
        var transform = try Self.seal(cipher, sessionId: 42)
        transform[transform.count - 1] ^= 0x01
        #expect(throws: SMB3Error.self) {
            try SMB3Transform.open(transform, cipher: cipher, key: Self.key, sessionId: 42)
        }
    }

    @Test("A transform for another session is refused", arguments: [SMB3Cipher.aes128CCM, .aes128GCM])
    func refusesAnotherSession(_ cipher: SMB3Cipher) throws {
        let transform = try Self.seal(cipher, sessionId: 42)
        #expect(throws: SMB3Error.self) {
            try SMB3Transform.open(transform, cipher: cipher, key: Self.key, sessionId: 43)
        }
    }

    /// The SMB2 TRANSFORM_HEADER is 52 bytes, and its protocol identifier is `0xFD 'SMB'`.
    @Test("The transform header has the layout MS-SMB2 2.2.41 gives it")
    func transformLayout() throws {
        let transform = try Self.seal(.aes128GCM, sessionId: 0x0102_0304_0506_0708)
        #expect(Array(transform.prefix(4)) == [0xFD, 0x53, 0x4D, 0x42])
        #expect(transform.count == 52 + Self.message.count)
        let size = transform[36..<40].reversed().reduce(0) { $0 << 8 | Int($1) }
        #expect(size == Self.message.count)
        #expect(Array(transform[42..<44]) == [0x01, 0x00])
        #expect(Array(transform[44..<52]) == [0x08, 0x07, 0x06, 0x05, 0x04, 0x03, 0x02, 0x01])
    }

    private static func seal(_ cipher: SMB3Cipher, sessionId: UInt64) throws -> Data {
        let nonceLength = cipher == .aes128GCM ? 12 : 11
        return try SMB3Transform.seal(
            message,
            cipher: cipher,
            key: key,
            sessionId: sessionId,
            nonce: Data(repeating: 0x5A, count: nonceLength)
        )
    }
}
