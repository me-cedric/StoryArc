// StoryArc: SMB 3 key derivation, signing and transport encryption, from MS-SMB2 3.1.4.
// Not in upstream SMBClient. CryptoKit for SHA-512, HMAC-SHA256 and AES-GCM; CommonCrypto,
// which upstream already uses, for the raw AES block that AES-CMAC and AES-CCM are built on.

import CommonCrypto
import CryptoKit
import Foundation

/// The two SMB 3 ciphers this client speaks, by their MS-SMB2 2.2.3.1.2 identifiers.
public enum SMB3Cipher: UInt16, Sendable {
  case aes128CCM = 0x0001
  case aes128GCM = 0x0002

  /// The nonce length the transform header carries for this cipher.
  var nonceLength: Int {
    switch self {
    case .aes128CCM: 11
    case .aes128GCM: 12
    }
  }
}

public enum SMB3Error: Error, Sendable {
  /// The server demands encryption, and the session has no key to encrypt with.
  case encryptionRequired
  /// A transform that does not open: a wrong key, a changed byte, or a wrong session.
  case decryptionFailed
}

public enum SMB3Crypto {
  /// The SP800-108 counter-mode KDF with HMAC-SHA256, one block, for a 128-bit key.
  ///
  /// `label` and `context` are given without their terminating NUL, which this adds, as
  /// MS-SMB2 3.1.4.2 counts it as part of each. A 3.1.1 context is the preauth hash, which
  /// has no NUL, so it is passed as data.
  public static func deriveKey(_ key: Data, label: String, context: Data) -> Data {
    var input = Data([0x00, 0x00, 0x00, 0x01])
    input += Data(label.utf8) + [0x00]
    input += [0x00]
    input += context
    input += Data([0x00, 0x00, 0x00, 0x80])
    let mac = HMAC<SHA256>.authenticationCode(for: input, using: SymmetricKey(data: key))
    return Data(mac).prefix(16)
  }

  /// A string with its terminating NUL, for a 3.0 KDF context.
  public static func terminated(_ text: String) -> Data {
    Data(text.utf8) + [0x00]
  }

  /// SHA-512 of `hash` followed by `message`: one step of the 3.1.1 preauth integrity hash.
  public static func chain(_ hash: Data, _ message: Data) -> Data {
    Data(SHA512.hash(data: hash + message))
  }

  /// AES-128-CMAC, from RFC 4493.
  public static func cmac(key: Data, message: Data) -> Data {
    let subkey1 = doubled(aes(key: key, block: Data(count: 16)))
    let subkey2 = doubled(subkey1)

    let blockCount = max(1, (message.count + 15) / 16)
    let isComplete = !message.isEmpty && message.count % 16 == 0
    var last = Data(message.dropFirst((blockCount - 1) * 16))
    if isComplete {
      last = xor(last, subkey1)
    } else {
      last.append(0x80)
      last.append(Data(count: 16 - last.count))
      last = xor(last, subkey2)
    }
    let blocks = Data(message.prefix((blockCount - 1) * 16)) + last
    return cbcMAC(key: key, blocks: blocks)
  }

  /// Encrypts `plaintext` and authenticates it and `aad`. Returns the ciphertext and a
  /// 16-byte tag.
  public static func seal(
    _ cipher: SMB3Cipher, key: Data, nonce: Data, plaintext: Data, aad: Data
  ) throws -> (ciphertext: Data, tag: Data) {
    switch cipher {
    case .aes128GCM:
      let box = try AES.GCM.seal(
        plaintext,
        using: SymmetricKey(data: key),
        nonce: AES.GCM.Nonce(data: nonce),
        authenticating: aad
      )
      return (box.ciphertext, box.tag)
    case .aes128CCM:
      let tag = xor(ccmMAC(key: key, nonce: nonce, plaintext: plaintext, aad: aad), ccmKeystream(key: key, nonce: nonce, from: 0, count: 16))
      let ciphertext = xor(plaintext, ccmKeystream(key: key, nonce: nonce, from: 1, count: plaintext.count))
      return (ciphertext, tag)
    }
  }

  /// Opens what ``seal(_:key:nonce:plaintext:aad:)`` produced, or throws when the tag does
  /// not match.
  public static func open(
    _ cipher: SMB3Cipher, key: Data, nonce: Data, ciphertext: Data, tag: Data, aad: Data
  ) throws -> Data {
    switch cipher {
    case .aes128GCM:
      do {
        let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: nonce), ciphertext: ciphertext, tag: tag)
        return try AES.GCM.open(box, using: SymmetricKey(data: key), authenticating: aad)
      } catch {
        throw SMB3Error.decryptionFailed
      }
    case .aes128CCM:
      let plaintext = xor(ciphertext, ccmKeystream(key: key, nonce: nonce, from: 1, count: ciphertext.count))
      let expected = xor(ccmMAC(key: key, nonce: nonce, plaintext: plaintext, aad: aad), ccmKeystream(key: key, nonce: nonce, from: 0, count: 16))
      guard constantTimeEqual(expected, tag) else { throw SMB3Error.decryptionFailed }
      return plaintext
    }
  }

  // MARK: - AES-CCM, NIST SP 800-38C, with a 16-byte tag and an 11-byte nonce

  /// The CBC-MAC over B0, the encoded AAD and the plaintext.
  private static func ccmMAC(key: Data, nonce: Data, plaintext: Data, aad: Data) -> Data {
    let lengthBytes = 15 - nonce.count
    var flags = UInt8((16 - 2) / 2) << 3 | UInt8(lengthBytes - 1)
    if !aad.isEmpty { flags |= 0x40 }

    var blocks = Data([flags]) + nonce + bigEndian(plaintext.count, bytes: lengthBytes)
    if !aad.isEmpty {
      var encoded = bigEndian(aad.count, bytes: 2) + aad
      encoded.append(Data(count: (16 - encoded.count % 16) % 16))
      blocks += encoded
    }
    blocks += plaintext + Data(count: (16 - plaintext.count % 16) % 16)
    return cbcMAC(key: key, blocks: blocks)
  }

  /// The CTR keystream from counter block `from`, for `count` bytes.
  private static func ccmKeystream(key: Data, nonce: Data, from counter: Int, count: Int) -> Data {
    let lengthBytes = 15 - nonce.count
    let start = Data([UInt8(lengthBytes - 1)]) + nonce + bigEndian(counter, bytes: lengthBytes)
    // The counter field is big-endian and the lowest bytes of the block, so a 128-bit
    // big-endian increment is the same sequence for every message shorter than 2^32 blocks.
    return crypt(key: key, mode: CCMode(kCCModeCTR), iv: start, data: Data(count: count))
  }

  // MARK: - AES primitives on CommonCrypto

  private static func aes(key: Data, block: Data) -> Data {
    crypt(key: key, mode: CCMode(kCCModeECB), iv: nil, data: block)
  }

  /// The last block of an AES-CBC encryption with a zero IV: a CBC-MAC.
  private static func cbcMAC(key: Data, blocks: Data) -> Data {
    crypt(key: key, mode: CCMode(kCCModeCBC), iv: Data(count: 16), data: blocks).suffix(16)
  }

  private static func crypt(key: Data, mode: CCMode, iv: Data?, data: Data) -> Data {
    var cryptor: CCCryptorRef?
    let created = key.withUnsafeBytes { keyBytes in
      (iv ?? Data()).withUnsafeBytes { ivBytes in
        CCCryptorCreateWithMode(
          CCOperation(kCCEncrypt), mode, CCAlgorithm(kCCAlgorithmAES), CCPadding(ccNoPadding),
          iv == nil ? nil : ivBytes.baseAddress, keyBytes.baseAddress, key.count,
          nil, 0, 0, 0, &cryptor
        )
      }
    }
    guard created == kCCSuccess, let cryptor else { return Data(count: data.count) }
    defer { CCCryptorRelease(cryptor) }

    var output = Data(count: data.count)
    var moved = 0
    _ = output.withUnsafeMutableBytes { out in
      data.withUnsafeBytes { input in
        CCCryptorUpdate(cryptor, input.baseAddress, data.count, out.baseAddress, data.count, &moved)
      }
    }
    return output
  }

  // MARK: - Bytes

  private static func doubled(_ block: Data) -> Data {
    let bytes = [UInt8](block)
    var shifted = [UInt8](repeating: 0, count: 16)
    for index in 0..<16 {
      let carry: UInt8 = index < 15 ? bytes[index + 1] >> 7 : 0
      shifted[index] = bytes[index] << 1 | carry
    }
    if bytes[0] & 0x80 != 0 { shifted[15] ^= 0x87 }
    return Data(shifted)
  }

  static func xor(_ left: Data, _ right: Data) -> Data {
    Data(zip(left, right).map { $0 ^ $1 })
  }

  private static func bigEndian(_ value: Int, bytes: Int) -> Data {
    Data((0..<bytes).reversed().map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) })
  }

  private static func constantTimeEqual(_ left: Data, _ right: Data) -> Bool {
    guard left.count == right.count else { return false }
    return zip(left, right).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
  }
}

/// The SMB2 TRANSFORM_HEADER of MS-SMB2 2.2.41, and the message it carries.
public enum SMB3Transform {
  static let protocolId = Data([0xFD, 0x53, 0x4D, 0x42])
  static let headerLength = 52

  static func isTransform(_ message: Data) -> Bool {
    message.count >= headerLength && message.prefix(4) == protocolId
  }

  /// Encrypts one SMB2 message, compounded or not, for `sessionId`.
  public static func seal(
    _ message: Data, cipher: SMB3Cipher, key: Data, sessionId: UInt64, nonce: Data
  ) throws -> Data {
    var aad = nonce + Data(count: 16 - nonce.count)
    aad += UInt32(message.count)
    aad += UInt16(0)
    aad += UInt16(0x0001)
    aad += sessionId
    let sealed = try SMB3Crypto.seal(cipher, key: key, nonce: nonce, plaintext: message, aad: aad)
    return protocolId + sealed.tag + aad + sealed.ciphertext
  }

  /// Opens one transform, and refuses one for another session.
  public static func open(_ transform: Data, cipher: SMB3Cipher, key: Data, sessionId: UInt64) throws -> Data {
    guard isTransform(transform) else { throw SMB3Error.decryptionFailed }
    let bytes = Data(transform)
    let tag = bytes[4..<20]
    let aad = bytes[20..<52]
    let nonce = Data(aad.prefix(cipher.nonceLength))
    let size = Int(littleEndian(bytes[36..<40]))
    let session = littleEndian(bytes[44..<52])
    guard session == sessionId, bytes.count >= headerLength + size else { throw SMB3Error.decryptionFailed }
    return try SMB3Crypto.open(
      cipher, key: key, nonce: nonce,
      ciphertext: Data(bytes[52..<(52 + size)]), tag: Data(tag), aad: Data(aad)
    )
  }

  /// A little-endian integer, read a byte at a time so no alignment is assumed.
  private static func littleEndian(_ bytes: Data) -> UInt64 {
    bytes.reversed().reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
  }
}
