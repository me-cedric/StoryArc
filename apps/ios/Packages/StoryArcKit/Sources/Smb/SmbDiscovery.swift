public import Foundation

internal import Network
internal import StoryArcCore

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
/// that grows beside the form, and an empty one costs a reader nothing.
///
/// mDNS, because that is what a NAS actually advertises: `_smb._tcp` is registered by Samba,
/// by macOS file sharing, and by every consumer NAS this app is likely to meet.
///
/// **A refused local-network permission is a state, not a silence.** The browser used to run
/// with no `stateUpdateHandler`, so a refusal and an empty network looked the same and the
/// app learned nothing. `network-share`'s *Local network permission denied* asks for three
/// things: discovery hidden, manual entry working, and the app explaining "once how to enable
/// discovery in system settings". The first two were already true, and both are deliberate.
/// The third is ``advice``.
@MainActor
@Observable
public final class SmbDiscovery {
    public private(set) var hosts: [SmbHost] = []

    /// The one sentence a refused local-network permission earns, or nil.
    ///
    /// Set on the first refusal and never again, so a second scan does not repeat it. A
    /// sentence beside the form rather than an alert: AGENTS.md section 2 keeps a normal
    /// condition out of the reader's way, and a refused permission with manual entry still
    /// working is a normal condition.
    public private(set) var advice: String?

    private var browser: NWBrowser?

    public init() {}

    /// Whether a browser error means the local-network permission was refused.
    ///
    /// `NWBrowser` reports a refusal as a dnssd policy error, and the same policy answers a
    /// direct local connection with `EPERM`. Everything else — an unreachable network, a
    /// server that went away — is an ordinary failure, and telling a reader to change a
    /// setting that is already right would be worse than saying nothing.
    nonisolated static func isRefusal(_ error: NWError) -> Bool {
        switch error {
        case let .dns(code):
            // kDNSServiceErr_PolicyDenied and kDNSServiceErr_NoAuth. Written out rather than
            // imported so this target keeps one import: `dnssd` would arrive for two numbers.
            code == -65570 || code == -65555
        case let .posix(code):
            code == .EPERM
        default:
            false
        }
    }

    /// Records a refusal, and reports whether this one produced the sentence.
    ///
    /// The return value is what makes "once" checkable: a second refusal answers `false` and
    /// leaves ``advice`` as it was.
    @discardableResult
    func noteRefusal() -> Bool {
        guard advice == nil else { return false }
        advice = String(localized: "smb.discovery.denied", bundle: .module, locale: .storyArc)
        return true
    }

    /// Starts looking. Idempotent, so a screen may call it on every appearance.
    public func start() {
        guard browser == nil else { return }

        let found = NWBrowser(
            for: .bonjour(type: "_smb._tcp", domain: nil),
            using: .tcp
        )
        found.stateUpdateHandler = { [weak self] state in
            // `.waiting` is what a refusal produces in practice; `.failed` is the same answer
            // arriving as a stop rather than as a pause. Neither empties the host list, so
            // discovery keeps hiding itself exactly as it did before.
            switch state {
            case let .waiting(error), let .failed(error):
                guard Self.isRefusal(error) else { return }
                Task { @MainActor in self?.noteRefusal() }
            default:
                return
            }
        }
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
