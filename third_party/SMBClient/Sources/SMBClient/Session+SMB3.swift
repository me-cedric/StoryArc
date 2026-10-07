// StoryArc: the SMB 3 half of a session, kept apart from upstream's Session.swift.

import Foundation

extension Session {
  /// StoryArc: the signing key, and for SMB 3 the two cipher keys, from MS-SMB2 3.2.5.3.1.
  ///
  /// SMB 2 signs with the session key itself. SMB 3 derives a signing key, and an
  /// encryption and a decryption key when a cipher was agreed. A guest or anonymous
  /// session has no key the server shares, so it gets none.
  func establishKeys(sessionKey: Data, preauthHash hash: Data, flags: SessionSetup.SessionFlags) throws {
    guard !isAnonymous, !isGuest else {
      signingKey = nil
      if flags.contains(.encryptData) { throw SMB3Error.encryptionRequired }
      return
    }

    switch dialect {
    case .smb311:
      signingKey = SMB3Crypto.deriveKey(sessionKey, label: "SMBSigningKey", context: hash)
      if cipher != nil {
        encryptionKey = SMB3Crypto.deriveKey(sessionKey, label: "SMBC2SCipherKey", context: hash)
        decryptionKey = SMB3Crypto.deriveKey(sessionKey, label: "SMBS2CCipherKey", context: hash)
      }
    case .smb300, .smb302:
      signingKey = SMB3Crypto.deriveKey(sessionKey, label: "SMB2AESCMAC", context: SMB3Crypto.terminated("SmbSign"))
      if cipher != nil {
        encryptionKey = SMB3Crypto.deriveKey(sessionKey, label: "SMB2AESCCM", context: SMB3Crypto.terminated("ServerIn "))
        decryptionKey = SMB3Crypto.deriveKey(sessionKey, label: "SMB2AESCCM", context: SMB3Crypto.terminated("ServerOut"))
      }
    default:
      signingKey = sessionKey
    }

    if flags.contains(.encryptData) && encryptionKey == nil {
      throw SMB3Error.encryptionRequired
    }
    if let cipher, let decryptionKey {
      let sessionId = sessionId
      connection.unseal = { message in
        try SMB3Transform.open(message, cipher: cipher, key: decryptionKey, sessionId: sessionId)
      }
    }
  }

  /// StoryArc: seals a message, compounded or not, in one SMB 3 transform, once the session
  /// has a cipher key. Before that, and on SMB 2, the message goes as it is.
  func seal(_ message: Data) throws -> Data {
    guard let cipher, let encryptionKey else { return message }
    return try SMB3Transform.seal(
      message,
      cipher: cipher,
      key: encryptionKey,
      sessionId: sessionId,
      nonce: Crypto.randomBytes(count: cipher.nonceLength)
    )
  }
}
