public import Foundation

public import Persistence
public import Smb
public import StoryArcCore

/// Adding a share, from a host and a password to a saved source.
///
/// `network-share` validates "before saving" and reports "the specific failure", then lets a
/// reader "browse the share's directory tree and pick the folder to use as the library
/// root". Those are two steps rather than one screen, and this is the state machine between
/// them. Android's `SmbConnection` is the same one.
@Observable
@MainActor
public final class SmbConnection {
    public enum Step: Equatable, Sendable {
        case entering
        case connecting
        /// Connected. The reader is now choosing which folder to read.
        case browsing(SmbIdentity, path: String, entries: [SmbEntry])
        case failed(String)
    }

    public private(set) var step: Step = .entering

    public var host = ""
    public var share = ""
    public var username = ""
    public var password = ""

    private let credentials: CredentialStore?
    private var resolved: SmbAddress?

    public init(credentials: CredentialStore? = nil) {
        self.credentials = credentials
    }

    /// Whether there is enough typed in to try.
    public var canConnect: Bool {
        guard step != .connecting else { return false }
        let typedHost = host.trimmingCharacters(in: .whitespaces)
        guard !typedHost.isEmpty else { return false }
        // A pasted `\\host\share` names both at once, so the share field may be empty.
        return !share.trimmingCharacters(in: .whitespaces).isEmpty
            || SmbAddress.parse(typedHost) != nil
    }

    /// Connects and lists the share's root, which is the first thing a reader chooses from.
    public func connect() async {
        guard let target = typedAddress() else {
            step = .failed(String(localized: "smb.error.notAnAddress", bundle: .module, locale: .storyArc))
            return
        }

        step = .connecting
        do {
            let client = SmbClient(address: target)
            let identity = try await client.connect()
            resolved = target
            step = .browsing(identity, path: target.path, entries: try await client.list(target.path))
        } catch let error as SmbError {
            step = .failed(Self.describe(error))
        } catch {
            step = .failed(String(localized: "smb.error.unexpected", bundle: .module, locale: .storyArc))
        }
    }

    /// Opens a folder inside the share, so the reader can go on choosing.
    public func enter(_ path: String) async {
        guard let target = resolved, case let .browsing(identity, _, previous) = step else { return }
        let entries = (try? await SmbClient(address: target).list(path)) ?? previous
        step = .browsing(identity, path: path, entries: entries)
    }

    /// The folder above the one being shown, or nil at the share's root.
    public func parent(of path: String) -> String? {
        guard !path.isEmpty else { return nil }
        guard let cut = path.lastIndex(of: "/") else { return "" }
        return String(path[path.startIndex..<cut])
    }

    /// The source to save, rooted at the folder the reader chose.
    ///
    /// Nil when the password cannot be stored, and the step says so. A share whose password
    /// is gone is a row that fails on the next launch with nothing to explain why.
    public func source() -> Source? {
        guard let target = resolved, case let .browsing(_, path, _) = step else { return nil }
        let rooted = SmbAddress(
            host: target.host,
            share: target.share,
            path: path,
            username: target.username,
            password: target.password,
            port: target.port
        )

        let id = UUID()
        var reference: String?
        if !rooted.isGuest {
            let key = CredentialStore.reference(for: id)
            guard credentials?.save(rooted.password ?? "", for: key) == true else {
                step = .failed(String(localized: "smb.error.keyNotStored", bundle: .module, locale: .storyArc))
                return nil
            }
            reference = key
        }

        return Source(
            id: id,
            displayName: rooted.displayName,
            kind: .networkShare,
            state: .connected,
            credentialReference: reference,
            locator: SmbLocator.write(rooted)
        )
    }

    public func reset() {
        step = .entering
    }

    private func typedAddress() -> SmbAddress? {
        let typedHost = host.trimmingCharacters(in: .whitespaces)
        let typedShare = share.trimmingCharacters(in: .whitespaces)
        let user = username.isEmpty ? nil : username
        let secret = password.isEmpty ? nil : password

        if typedShare.isEmpty, let pasted = SmbAddress.parse(typedHost) {
            return SmbAddress(
                host: pasted.host,
                share: pasted.share,
                path: pasted.path,
                username: user,
                password: secret,
                port: pasted.port
            )
        }

        // A host may carry a port. Most readers never type one, but a NAS behind a
        // forwarded port has no other way to say so.
        let parts = typedHost
            .replacingOccurrences(of: "smb://", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/\\"))
            .split(separator: ":")
            .map(String.init)
        guard let bare = parts.first, !bare.isEmpty, !typedShare.isEmpty else { return nil }

        return SmbAddress(
            host: bare,
            share: typedShare,
            username: user,
            password: secret,
            port: parts.count > 1 ? Int(parts[1]) ?? SmbAddress.defaultPort : SmbAddress.defaultPort
        )
    }

    private static func describe(_ error: SmbError) -> String {
        switch error {
        case .hostUnreachable:
            String(localized: "smb.error.hostUnreachable", bundle: .module, locale: .storyArc)
        case .shareNotFound:
            String(localized: "smb.error.shareNotFound", bundle: .module, locale: .storyArc)
        case .authenticationRejected:
            String(localized: "smb.error.authentication", bundle: .module, locale: .storyArc)
        case .protocolUnsupported:
            String(localized: "smb.error.smb1", bundle: .module, locale: .storyArc)
        case .encryptionRequired:
            String(localized: "smb.error.encryption", bundle: .module, locale: .storyArc)
        case .unexpected:
            String(localized: "smb.error.unexpected", bundle: .module, locale: .storyArc)
        }
    }
}

/// A share written down, and read back.
///
/// The registry stores one string per source, so the host, share, path and user name travel
/// as a URL. The password never does — that is what the credential store is for.
public enum SmbLocator {
    public static func write(_ address: SmbAddress) -> String {
        let user = (address.username?.isEmpty == false) ? "\(address.username ?? "")@" : ""
        let port = address.port == SmbAddress.defaultPort ? "" : ":\(address.port)"
        let trimmed = address.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let path = trimmed.isEmpty ? "" : "/\(trimmed)"
        return "smb://\(user)\(address.host)\(port)/\(address.share)\(path)"
    }

    public static func read(_ locator: String, password: String?) -> SmbAddress? {
        let body = locator.replacingOccurrences(of: "smb://", with: "")
        let user = body.contains("@") ? String(body.split(separator: "@")[0]) : nil
        let rest = user != nil ? String(body.split(separator: "@").dropFirst().joined(separator: "@")) : body
        guard let parsed = SmbAddress.parse(rest) else { return nil }
        return SmbAddress(
            host: parsed.host,
            share: parsed.share,
            path: parsed.path,
            username: user,
            password: password,
            port: parsed.port
        )
    }
}

/// What is needed to open a saved share.
public struct SmbPage: Sendable {
    public let id: String
    public let title: String
    public let address: SmbAddress

    /// Nil when the source is not a share, has no address, or has lost its password.
    public init?(source: Source, credentials: CredentialStore?) {
        guard source.kind == .networkShare, let locator = source.locator else { return nil }
        let password = source.credentialReference.flatMap { credentials?.secret(for: $0) }
        if source.credentialReference != nil, password == nil { return nil }
        guard let address = SmbLocator.read(locator, password: password) else { return nil }

        id = source.id.uuidString
        title = source.displayName
        self.address = address
    }
}
