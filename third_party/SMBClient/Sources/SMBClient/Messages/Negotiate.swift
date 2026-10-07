import Foundation

public enum Negotiate {
  public struct Request: Message.Request {
    public typealias Response = Negotiate.Response

    public let header: Header
    public let structureSize: UInt16
    public let dialectCount: UInt16
    public let securityMode: SecurityMode
    public let reserved: UInt16
    public let capabilities: Capabilities
    public let clientGuid: UUID
    public let clientStartTime: UInt64
    public let dialects: [Dialects]
    public let padding: Data
    public let negotiateContextList: Data

    /// StoryArc: how many negotiate contexts follow the dialects. Zero unless 3.1.1 is offered.
    public let negotiateContextCount: UInt16

    public init(
      headerFlags: Header.Flags = [],
      messageId: UInt64,
      securityMode: SecurityMode,
      dialects: [Dialects],
      capabilities: Capabilities = [],
      ciphers: [SMB3Cipher] = []
    ) {
      header = Header(
        creditCharge: 1,
        command: .negotiate,
        creditRequest: 0,
        flags: headerFlags,
        messageId: messageId,
        treeId: 0,
        sessionId: 0
      )

      structureSize  = 36
      dialectCount = UInt16(dialects.count)
      self.securityMode = securityMode
      reserved = 0
      self.capabilities = capabilities
      clientGuid = UUID()
      clientStartTime = 0
      self.dialects = dialects

      // StoryArc: MS-SMB2 2.2.3. With 3.1.1 offered, ClientStartTime becomes the context
      // list's offset and count, and the list starts on an 8-byte boundary from the header.
      if dialects.contains(.smb311) {
        let contexts = Negotiate.contexts(ciphers: ciphers)
        negotiateContextCount = UInt16(contexts.count)
        padding = Data(count: (8 - (64 + 36 + dialects.count * 2) % 8) % 8)
        negotiateContextList = contexts.enumerated().reduce(into: Data()) { (list, each) in
          list += each.element
          if each.offset < contexts.count - 1 {
            list += Data(count: (8 - each.element.count % 8) % 8)
          }
        }
      } else {
        negotiateContextCount = 0
        padding = Data(count: (dialects.count * 2) % 8)
        negotiateContextList = Data()
      }
    }

    public func encoded() -> Data {
      var data = Data()

      data += header.encoded()

      data += structureSize
      data += dialectCount
      data += securityMode.rawValue
      data += reserved
      data += capabilities.rawValue
      data += Data(from: clientGuid)
      if negotiateContextCount > 0 {
        data += UInt32(64 + 36 + dialects.count * 2 + padding.count)
        data += negotiateContextCount
        data += UInt16(0)
      } else {
        data += clientStartTime
      }

      for dialect in dialects {
        data += dialect.rawValue
      }
      data += padding
      data += negotiateContextList

      return data
    }
  }

  /// StoryArc: the SMB 3.1.1 negotiate contexts of MS-SMB2 2.2.3.1, each with its header.
  ///
  /// PREAUTH_INTEGRITY_CAPABILITIES offers SHA-512 with a 32-byte salt, which 3.1.1 requires.
  /// ENCRYPTION_CAPABILITIES offers the ciphers, in the client's order of preference.
  static func contexts(ciphers: [SMB3Cipher]) -> [Data] {
    var preauth = Data()
    preauth += UInt16(1)
    preauth += UInt16(32)
    preauth += UInt16(0x0001)
    preauth += Crypto.randomBytes(count: 32)

    var contexts = [context(type: 0x0001, data: preauth)]
    if !ciphers.isEmpty {
      var encryption = Data()
      encryption += UInt16(ciphers.count)
      for cipher in ciphers {
        encryption += cipher.rawValue
      }
      contexts.append(context(type: 0x0002, data: encryption))
    }
    return contexts
  }

  private static func context(type: UInt16, data: Data) -> Data {
    var context = Data()
    context += type
    context += UInt16(data.count)
    context += UInt32(0)
    return context + data
  }

  public struct Response: Message.Response {
    public let header: Header
    public let structureSize: UInt16
    public let securityMode: SecurityMode
    public let dialectRevision: UInt16
    public let negotiateContextCount: UInt16
    public let serverGuid: UUID
    public let capabilities: Capabilities
    public let maxTransactSize: UInt32
    public let maxReadSize: UInt32
    public let maxWriteSize: UInt32
    public let systemTime: UInt64
    public let serverStartTime: UInt64
    public let securityBufferOffset: UInt16
    public let securityBufferLength: UInt16
    public let negotiateContextOffset: UInt32
    public let securityBuffer: Data

    public init(data: Data) {
      let reader = ByteReader(data)

      header = reader.read()

      structureSize = reader.read()
      securityMode = SecurityMode(rawValue: reader.read())
      dialectRevision = reader.read()
      negotiateContextCount = reader.read()
      serverGuid = reader.read()
      capabilities = Capabilities(rawValue: reader.read())
      maxTransactSize = reader.read()
      maxReadSize = reader.read()
      maxWriteSize = reader.read()
      systemTime = reader.read()
      serverStartTime = reader.read()
      securityBufferOffset = reader.read()
      securityBufferLength = reader.read()
      negotiateContextOffset = reader.read()
      securityBuffer = reader.read(from: Int(securityBufferOffset), count: Int(securityBufferLength))

      cipher = dialectRevision == Dialects.smb311.rawValue
        ? Self.cipher(in: data, offset: Int(negotiateContextOffset), count: Int(negotiateContextCount))
        : nil
    }

    /// StoryArc: the cipher the server chose in its ENCRYPTION_CAPABILITIES context, for 3.1.1.
    ///
    /// `nil` when it sent none, chose none (cipher 0), or chose one this client did not offer.
    /// Every length is checked against the message, because the server writes them.
    public let cipher: SMB3Cipher?

    private static func cipher(in data: Data, offset start: Int, count: Int) -> SMB3Cipher? {
      let bytes = [UInt8](data)
      func word(_ at: Int) -> Int? {
        at + 2 <= bytes.count ? Int(bytes[at]) | Int(bytes[at + 1]) << 8 : nil
      }

      var offset = start
      for _ in 0..<count {
        guard let type = word(offset), let length = word(offset + 2) else { return nil }
        let body = offset + 8
        guard body + length <= bytes.count else { return nil }
        if type == 0x0002, length >= 4, word(body) == 1, let chosen = word(body + 2) {
          return SMB3Cipher(rawValue: UInt16(chosen))
        }
        offset = body + length
        offset += (8 - offset % 8) % 8
      }
      return nil
    }
  }

  public struct SecurityMode: OptionSet, Sendable {
    public let rawValue: UInt16

    public init(rawValue: UInt16) {
      self.rawValue = rawValue
    }

    public static let signingEnabled = SecurityMode(rawValue: 0x0001)
    public static let signingRequired = SecurityMode(rawValue: 0x0002)
  }

  public struct Capabilities: OptionSet, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
      self.rawValue = rawValue
    }

    public static let dfs = Capabilities(rawValue: 0x00000001)
    public static let leasing = Capabilities(rawValue: 0x00000002)
    public static let largeMtu = Capabilities(rawValue: 0x00000004)
    public static let multiChannel = Capabilities(rawValue: 0x00000008)
    public static let persistentHandles = Capabilities(rawValue: 0x00000010)
    public static let directoryLeasing = Capabilities(rawValue: 0x00000020)
    public static let encryption = Capabilities(rawValue: 0x00000040)
    public static let notifications = Capabilities(rawValue: 0x00000080)
  }

  public enum Dialects: UInt16 {
    case smb202 = 0x0202
    case smb210 = 0x0210
    case smb300 = 0x0300
    case smb302 = 0x0302
    case smb311 = 0x0311
  }
}
