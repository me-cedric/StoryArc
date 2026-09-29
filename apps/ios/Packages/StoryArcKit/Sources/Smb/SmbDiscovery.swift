public import Foundation

internal import Network
internal import StoryArcCore

/// A host advertising SMB on the local network.
public struct SmbHost: Sendable, Equatable, Identifiable {
    public let name: String
    public let port: Int
    /// The host or address to connect to.
    ///
    /// Not the Bonjour instance name above -- `"TrueNAS"` or `"Cedric's MacBook Pro"` is what
    /// a reader sees on the list, not what resolves as a host. This is read off the service's
    /// own endpoint once it resolves, which is why a host only appears in
    /// ``SmbDiscovery/hosts`` after that finishes.
    public let address: String

    public var id: String { name }

    public init(name: String, port: Int, address: String) {
        self.name = name
        self.port = port
        self.address = address
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

    /// The browser this class runs, once ``start()`` has built one.
    ///
    /// Readable inside the module so a test can drive the handlers ``start()`` installs. The
    /// wiring is the production behaviour here, and a test that calls ``noteRefusal()``
    /// directly asserts none of it.
    private(set) var browser: NWBrowser?

    /// One resolving connection per service in flight, keyed by the service's own name, so a
    /// result reported again before it resolves does not open a second connection.
    private var resolving: [String: NWConnection] = [:]

    /// What each service resolved to. Kept apart from ``hosts`` so a service the browser no
    /// longer reports can be dropped from both without waiting on a fresh resolve, and so a
    /// resolve that finishes late does not revive a share that already left.
    private var resolved: [String: SmbHost] = [:]

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

    /// Records a refusal, if this is what a browser reports one as.
    ///
    /// `.waiting` is what a refusal produces in practice; `.failed` is the same answer
    /// arriving as a stop rather than as a pause. Neither empties the host list, so discovery
    /// keeps hiding itself exactly as it did before.
    func note(_ state: NWBrowser.State) {
        switch state {
        case let .waiting(error), let .failed(error):
            if Self.isRefusal(error) { noteRefusal() }
        default:
            break
        }
    }

    /// Starts looking. Idempotent, so a screen may call it on every appearance.
    public func start() {
        guard browser == nil else { return }

        let found = NWBrowser(
            for: .bonjour(type: "_smb._tcp", domain: nil),
            using: .tcp
        )
        found.stateUpdateHandler = { [weak self] state in
            // Network delivers this on the queue handed to `start(queue:)` below, which is the
            // main one, so this is already the main actor rather than a hop to it. Change that
            // queue and this line has to change with it.
            MainActor.assumeIsolated {
                guard let self else { return }
                self.note(state)
            }
        }
        found.browseResultsChangedHandler = { [weak self] results, _ in
            MainActor.assumeIsolated {
                self?.handle(results)
            }
        }
        found.start(queue: .main)
        browser = found
    }

    /// Starts or drops a resolve for each result the browser now reports, and drops the
    /// resolved host of one it no longer does.
    private func handle(_ results: Set<NWBrowser.Result>) {
        let seen = Set(results.compactMap { Self.serviceName(of: $0.endpoint) })

        for name in resolving.keys where !seen.contains(name) {
            resolving[name]?.cancel()
            resolving.removeValue(forKey: name)
        }
        resolved = resolved.filter { seen.contains($0.key) }

        for result in results {
            guard let name = Self.serviceName(of: result.endpoint) else { continue }
            guard resolved[name] == nil, resolving[name] == nil else { continue }
            resolve(name: name, endpoint: result.endpoint)
        }
        hosts = resolved.values.sorted { $0.name < $1.name }
    }

    /// Lifted beside `handle(_:)` rather than buried in it, so a test can assert the rule —
    /// only a `.service` endpoint names anything — without constructing a `NWBrowser.Result`,
    /// which the framework gives no initialiser for.
    static func serviceName(of endpoint: NWEndpoint) -> String? {
        guard case let .service(name, _, _, _) = endpoint else { return nil }
        return name
    }

    /// Resolves one service to a host or an address, the way a reader's next step already
    /// would: opening a connection to it. `NWEndpoint` has no bare resolver for a `.service`
    /// endpoint, so the connection this app is about to make anyway is what tells it.
    ///
    /// Internal rather than private for the same reason: a test drives this directly, against
    /// a real loopback listener, because `NWBrowser.Result` cannot be built by hand to go
    /// through ``handle(_:)``.
    func resolve(name: String, endpoint: NWEndpoint) {
        let connection = NWConnection(to: endpoint, using: Self.resolvingParameters)
        resolving[name] = connection
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                MainActor.assumeIsolated { self?.resolved(name: name, connection: connection) }
            case .failed:
                // Dropped, so the next report of this service tries again.
                MainActor.assumeIsolated { self?.abandon(name: name, connection: connection) }
            default:
                break
            }
        }
        connection.start(queue: .main)
    }

    /// TCP over IPv4 only. `SmbConnection` reads a `:` in the host field as the start of a
    /// port, so an IPv6 address — which a Bonjour service on a LAN often resolves to first —
    /// would reach it as `fe80` and nothing more.
    static var resolvingParameters: NWParameters {
        let parameters = NWParameters.tcp
        if let internet = parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
            internet.version = .v4
        }
        return parameters
    }

    private func abandon(name: String, connection: NWConnection) {
        connection.cancel()
        if resolving[name] === connection { resolving.removeValue(forKey: name) }
    }

    private func resolved(name: String, connection: NWConnection) {
        defer {
            connection.cancel()
            resolving.removeValue(forKey: name)
        }
        guard resolving[name] === connection,
              case let .hostPort(host, port) = connection.currentPath?.remoteEndpoint
        else { return }
        resolved[name] = SmbHost(name: name, port: Int(port.rawValue), address: Self.address(of: host))
        hosts = resolved.values.sorted { $0.name < $1.name }
    }

    /// A host or an address, read out of what `NWEndpoint.Host` actually is rather than
    /// dumped from its case -- `.name` already holds the plain string a share connects to,
    /// and an IP address prints its own dotted or colon form.
    static func address(of host: NWEndpoint.Host) -> String {
        switch host {
        case let .name(name, _): name
        case let .ipv4(address): "\(address)"
        case let .ipv6(address): "\(address)"
        @unknown default: "\(host)"
        }
    }

    public func stop() {
        browser?.cancel()
        browser = nil
        for connection in resolving.values { connection.cancel() }
        resolving.removeAll()
        resolved.removeAll()
        hosts = []
    }
}
