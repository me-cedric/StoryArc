public import Foundation

internal import Network

/// A host advertising SMB on the local network.
public struct SmbHost: Sendable, Equatable, Identifiable {
    public let name: String
    public let port: Int

    public var id: String { name }

    public init(name: String, port: Int) {
        self.name = name
        self.port = port
    }
}

/// Hosts advertising SMB on the local network.
///
/// `network-share` marks discovery a SHOULD, and is firm about what it must not become:
/// "manual entry is always available and never gated behind discovery". So this is a list
/// that grows beside the form, and an empty one costs a reader nothing — including when the
/// local-network permission is refused, which arrives here as simply no results.
///
/// mDNS, because that is what a NAS actually advertises: `_smb._tcp` is registered by Samba,
/// by macOS file sharing, and by every consumer NAS this app is likely to meet.
@MainActor
@Observable
public final class SmbDiscovery {
    public private(set) var hosts: [SmbHost] = []

    private var browser: NWBrowser?

    public init() {}

    /// Starts looking. Idempotent, so a screen may call it on every appearance.
    public func start() {
        guard browser == nil else { return }

        let found = NWBrowser(
            for: .bonjour(type: "_smb._tcp", domain: nil),
            using: .tcp
        )
        found.browseResultsChangedHandler = { [weak self] results, _ in
            let named: [SmbHost] = results.compactMap { result in
                guard case let .service(name, _, _, _) = result.endpoint else { return nil }
                // The port is not in the browse result -- resolving it needs a connection,
                // and the reader is about to make one anyway. 445 is what a share uses.
                return SmbHost(name: name, port: 445)
            }
            Task { @MainActor in self?.hosts = named.sorted { $0.name < $1.name } }
        }
        found.start(queue: .main)
        browser = found
    }

    public func stop() {
        browser?.cancel()
        browser = nil
    }
}
