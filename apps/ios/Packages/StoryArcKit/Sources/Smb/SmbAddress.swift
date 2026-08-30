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
    /// The server insists on SMB 3 transport encryption, which this app cannot do.
    ///
    /// Its own case because it is its own answer. A reader whose NAS requires encryption is
    /// not looking at a network fault or a typo — there is a setting on their server, and a
    /// sentence that says so is worth more than a fifth way of saying "could not connect".
    case encryptionRequired
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

extension SmbEntry {
    /// Where this entry's bytes may be written under `directory`, or `nil` when the
    /// server's name is not usable as a filename.
    ///
    /// A hostile server picks both the destination and the content. `name` comes
    /// verbatim out of a directory-listing response, and a name of
    /// `../../Preferences/group.app.storyarc.plist` handed straight to `appending(path:)`
    /// resolves out of the cache directory and into the app's own preferences — the
    /// server then chooses what is written there. Only a decoder that needs a real file
    /// (PDF, solid RAR, CB7) makes the app write anything down, and the server chooses
    /// which format it serves, so it chooses whether that happens.
    ///
    /// The rule is the one `ImageFolderArchive.data(for:)` applies to a publication's own
    /// internal paths: keep the last component, and refuse a name that means a directory
    /// rather than a file. Refused rather than trimmed, like a download id — trimming is
    /// what invites `....//` and the rest of that family — and the resolved path is
    /// checked back against `directory` as the belt to that brace.
    ///
    /// `SmbClient.list` drops an exact `.` and `..` so the browser does not list them, and
    /// that is not this check: `../../Preferences/x.plist` is not an exact match and
    /// survives it untouched. A name only becomes dangerous where it becomes a path, which
    /// is here.
    public func cacheLocation(in directory: URL) -> URL? {
        // Both separators. `\` is SMB's own, and a rule that knows only `/` is a rule
        // written in the wrong protocol.
        let components = name.split(whereSeparator: { $0 == "/" || $0 == "\\" })
        guard let last = components.last.map(String.init), !last.isEmpty else { return nil }
        // `.`, `..`, and any longer run of dots — every one of them names a directory.
        guard last.contains(where: { $0 != "." }) else { return nil }
        // Nothing that survived the split can still be a separator, and nothing that
        // reaches a filesystem call may carry a NUL. Checked anyway: this is the last
        // place either could be true.
        guard !last.contains("/"), !last.contains("\\"), !last.contains("\0") else { return nil }

        let local = directory.appending(path: last)
        guard local.standardizedFileURL.path
            .hasPrefix(directory.standardizedFileURL.path + "/")
        else { return nil }
        return local
    }
}
