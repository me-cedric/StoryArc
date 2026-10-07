internal import CommonCrypto
internal import CryptoKit
public import Foundation

/// The passphrase-sealed credential block of a library document.
///
/// `library-portability` / *Secrets travel only sealed, and only when asked*: each secret is
/// written only as ciphertext, keyed by its source, and every parameter is in the document, so
/// a hard-coded iteration count cannot trap a file already written. Android's `LibrarySecrets`
/// is the same shape. The packages/test-fixtures/library/sealed-secrets.json vector is opened by
/// both platforms' tests.
///
/// The writer fills this only when the reader chose to carry secrets and gave a passphrase.
public struct LibrarySecrets: Sendable, Equatable, Codable {
    public var kdf: String
    public var iterations: Int

    /// The salt, in base64. One per document.
    public var salt: String

    public var cipher: String

    /// One sealed secret per source, keyed by the source id in lower case.
    public var sealed: [String: SealedSecret]

    public init(
        kdf: String,
        iterations: Int,
        salt: String,
        cipher: String,
        sealed: [String: SealedSecret]
    ) {
        self.kdf = kdf
        self.iterations = iterations
        self.salt = salt
        self.cipher = cipher
        self.sealed = sealed
    }
}

/// One secret as ciphertext: the nonce it was sealed with, and the ciphertext followed by the
/// 128-bit tag, both in base64.
public struct SealedSecret: Sendable, Equatable, Codable {
    public var nonce: String
    public var ciphertext: String

    public init(nonce: String, ciphertext: String) {
        self.nonce = nonce
        self.ciphertext = ciphertext
    }
}

/// Why a block of secrets could not be sealed or opened.
public enum LibrarySecretsFailure: Error, Sendable, Equatable {
    /// The reader gave no passphrase.
    case emptyPassphrase

    /// A KDF, a cipher or an iteration count this build does not read.
    case unsupported

    /// A field that is not base64, or has the wrong length.
    case malformed

    /// The passphrase is wrong, or the ciphertext was changed. AES-GCM cannot tell the two
    /// apart, and the reader's next step is the same for both.
    case wrongPassphraseOrDamaged
}

/// Seals and opens secrets under a passphrase.
///
/// PBKDF2-HMAC-SHA256 at 600,000 iterations derives a 32-byte key from the passphrase and a
/// random 16-byte salt. Each secret is sealed with AES-256-GCM under that key, with its own
/// random 12-byte nonce and a 128-bit tag. No dependency: CommonCrypto and CryptoKit.
///
/// The passphrase is normalised to NFC before its UTF-8 bytes are taken, so one passphrase typed
/// on two keyboards is one key on both platforms. Android's `LibrarySecretSealer` does the same.
public enum LibrarySecretSealer {
    public static let kdfName = "PBKDF2-HMAC-SHA256"
    public static let cipherName = "AES-256-GCM"

    /// OWASP's figure for PBKDF2-HMAC-SHA256 when this was written. Always what the writer uses.
    public static let iterations = 600_000

    /// The most iterations a document may ask this build to run. A document is untrusted input,
    /// and an iteration count of four billion is a way to hang the app.
    public static let maximumIterations = 10_000_000

    private static let saltLength = 16
    private static let nonceLength = 12
    private static let keyLength = 32
    private static let tagLength = 16

    /// Seals each secret under `passphrase`, with a fresh salt and a fresh nonce for each.
    public static func seal(_ secrets: [UUID: String], passphrase: String) throws -> LibrarySecrets {
        try seal(
            secrets,
            passphrase: passphrase,
            salt: randomBytes(saltLength),
            nonces: secrets.mapValues { _ in randomBytes(nonceLength) }
        )
    }

    /// The same, with the salt and the nonces chosen by the caller. Fixed inputs make the output
    /// fixed, which is how the committed test vector is checked.
    static func seal(
        _ secrets: [UUID: String],
        passphrase: String,
        salt: Data,
        nonces: [UUID: Data]
    ) throws -> LibrarySecrets {
        let key = try derivedKey(passphrase, salt: salt, iterations: iterations)
        var sealed: [String: SealedSecret] = [:]
        for (id, secret) in secrets {
            guard let nonceBytes = nonces[id], nonceBytes.count == nonceLength,
                  let nonce = try? AES.GCM.Nonce(data: nonceBytes)
            else { throw LibrarySecretsFailure.malformed }
            let box = try AES.GCM.seal(Data(secret.utf8), using: key, nonce: nonce)
            sealed[id.uuidString.lowercased()] = SealedSecret(
                nonce: nonceBytes.base64EncodedString(),
                ciphertext: (box.ciphertext + box.tag).base64EncodedString()
            )
        }
        return LibrarySecrets(
            kdf: kdfName,
            iterations: iterations,
            salt: salt.base64EncodedString(),
            cipher: cipherName,
            sealed: sealed
        )
    }

    /// Every secret, by the id of its source.
    ///
    /// All or nothing: one secret that does not open fails the call. A wrong passphrase fails
    /// every secret at once, and a changed byte fails its own, so there is no partial answer
    /// the reader could act on better than "this passphrase did not open the file".
    public static func open(_ secrets: LibrarySecrets, passphrase: String) throws -> [UUID: String] {
        guard secrets.kdf == kdfName, secrets.cipher == cipherName,
              (1...maximumIterations).contains(secrets.iterations)
        else { throw LibrarySecretsFailure.unsupported }
        guard let salt = Data(base64Encoded: secrets.salt), !salt.isEmpty
        else { throw LibrarySecretsFailure.malformed }

        let key = try derivedKey(passphrase, salt: salt, iterations: secrets.iterations)
        var opened: [UUID: String] = [:]
        for (name, entry) in secrets.sealed {
            guard let id = UUID(uuidString: name),
                  let nonceBytes = Data(base64Encoded: entry.nonce), nonceBytes.count == nonceLength,
                  let combined = Data(base64Encoded: entry.ciphertext), combined.count >= tagLength,
                  let nonce = try? AES.GCM.Nonce(data: nonceBytes)
            else { throw LibrarySecretsFailure.malformed }
            let box = try? AES.GCM.SealedBox(
                nonce: nonce,
                ciphertext: combined.dropLast(tagLength),
                tag: combined.suffix(tagLength)
            )
            guard let box, let plain = try? AES.GCM.open(box, using: key),
                  let text = String(data: plain, encoding: .utf8)
            else { throw LibrarySecretsFailure.wrongPassphraseOrDamaged }
            opened[id] = text
        }
        return opened
    }

    private static func derivedKey(
        _ passphrase: String,
        salt: Data,
        iterations: Int
    ) throws -> SymmetricKey {
        let password = Array(passphrase.precomposedStringWithCanonicalMapping.utf8)
        guard !password.isEmpty else { throw LibrarySecretsFailure.emptyPassphrase }
        var key = [UInt8](repeating: 0, count: keyLength)
        let status = password.withUnsafeBufferPointer { password in
            salt.withUnsafeBytes { salt in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    password.baseAddress.map { UnsafeRawPointer($0).assumingMemoryBound(to: Int8.self) },
                    password.count,
                    salt.bindMemory(to: UInt8.self).baseAddress,
                    salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    UInt32(iterations),
                    &key,
                    keyLength
                )
            }
        }
        guard status == kCCSuccess else { throw LibrarySecretsFailure.malformed }
        return SymmetricKey(data: key)
    }

    private static func randomBytes(_ count: Int) -> Data {
        var generator = SystemRandomNumberGenerator()
        return Data((0..<count).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
    }
}
