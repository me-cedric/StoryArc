public import Foundation

/// Where a share is, and who is asking.
///
/// `network-share` takes "a host, share name, optional path, and either guest access or
/// username and password". All four travel together because none of them is useful alone.
/// Android's `SmbAddress` is the same four with the same two ways of arriving at them.
public struct SmbAddress: Sendable, Equatable {
    public let host: String
    public let share: String
    /// Inside the share. Empty means the share's own root.
    public let path: String
    public let username: String?
    public let password: String?
    /// Non-standard only for a test server; 445 is the port SMB actually uses.
    public let port: Int

    public static let defaultPort = 445

    public init(
        host: String,
        share: String,
        path: String = "",
        username: String? = nil,
        password: String? = nil,
        port: Int = SmbAddress.defaultPort
    ) {
        self.host = host
        self.share = share
        self.path = path
        self.username = username
        self.password = password
        self.port = port
    }

    /// Whether this connects without a name, which some shares allow.
    public var isGuest: Bool { username?.isEmpty ?? true }

    /// What to show a reader who is looking at a list of sources.
    public var displayName: String { "\(host)/\(share)" }

    /// Reads an address out of what a reader pasted.
    ///
    /// Accepts `smb://host/share/path` and the `\\host\share\path` form Windows shows,
    /// because those are the two a reader is likely to have to hand.
    public static func parse(_ pasted: String) -> SmbAddress? {
        let normalised = pasted
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\", with: "/")
        let stripped = normalised.hasPrefix("smb://")
            ? String(normalised.dropFirst("smb://".count))
            : normalised

        let parts = stripped.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return nil }

        let authority = parts[0].split(separator: ":").map(String.init)
        guard let host = authority.first, !host.isEmpty else { return nil }

        return SmbAddress(
            host: host,
            share: parts[1],
            path: parts.dropFirst(2).joined(separator: "/"),
            port: authority.count > 1 ? Int(authority[1]) ?? defaultPort : defaultPort
        )
    }
}

/// Why a share could not be reached.
///
/// `network-share` requires the specific failure rather than a general one: "host
/// unreachable, share not found, authentication rejected, or protocol unsupported". A reader
/// who typed the wrong password and a reader whose NAS is asleep need different sentences.
public enum SmbError: Error, Equatable, Sendable {
    case hostUnreachable
    case shareNotFound
    case authenticationRejected
    /// An SMB 1 server. Refused rather than accommodated — see ``SmbClient``.
    case protocolUnsupported
    case unexpected(detail: String)
}

/// One entry in a share's directory tree.
public struct SmbEntry: Sendable, Equatable, Identifiable {
    public let name: String
    /// Relative to the share's root, so it can be handed straight back as a path.
    public let path: String
    public let isDirectory: Bool
    public let length: Int64

    public var id: String { path }

    public init(name: String, path: String, isDirectory: Bool, length: Int64) {
        self.name = name
        self.path = path
        self.isDirectory = isDirectory
        self.length = length
    }
}

/// What a connection turned out to be, once it worked.
public struct SmbIdentity: Sendable, Equatable {
    /// The dialect the two ends agreed on, such as `SMB 3.1.1`.
    public let dialect: String
    /// Whether the transport is encrypted.
    ///
    /// `network-share` requires the source detail screen to state this, which means it has
    /// to be a fact about *this* connection rather than about what the app supports.
    public let isEncrypted: Bool

    public init(dialect: String, isEncrypted: Bool) {
        self.dialect = dialect
        self.isEncrypted = isEncrypted
    }
}
