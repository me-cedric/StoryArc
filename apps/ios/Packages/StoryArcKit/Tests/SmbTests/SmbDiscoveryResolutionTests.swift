import Foundation
import Network
import Testing

@testable import Smb

/// A discovered host resolves to a real address, not the Bonjour instance name.
///
/// `SmbSheet` used to fill the connection's host field with `host.name` -- the label a reader
/// sees, such as `"TrueNAS"` or `"Cedric's MacBook Pro"` -- which is not a host name and does
/// not resolve (STATUS.md recorded that `truenas` failed where `truenas.local` worked). A
/// `.service` endpoint from `NWBrowser` carries no address; resolving one needs an actual
/// connection attempt, which is what `SmbDiscovery.resolve(name:endpoint:)` does.
///
/// **The pure half is asserted without a network.** `serviceName(of:)` and `address(of:)` are
/// lifted beside `handle(_:)` and `resolved(name:connection:)` for exactly this: neither needs
/// a socket, and `NWBrowser.Result` has no public initialiser to build one for `handle(_:)`
/// itself (confirmed: `NWBrowser.Result(endpoint:interfaces:metadata:)` does not compile).
///
/// **The resolving half is asserted against a real loopback listener.** `resolve(name:endpoint:)`
/// is driven directly with a `.hostPort` endpoint at a listener this test starts, because that
/// is the one endpoint shape `NWEndpoint` will actually construct for a caller.
@MainActor
@Suite("A discovered host resolves to an address")
struct SmbDiscoveryResolutionTests {

    @Test("Only a .service endpoint names a service")
    func serviceNameOnlyFromAService() {
        let service = NWEndpoint.service(name: "TrueNAS", type: "_smb._tcp", domain: "local", interface: nil)
        #expect(SmbDiscovery.serviceName(of: service) == "TrueNAS")

        let hostPort = NWEndpoint.hostPort(host: .ipv4(.loopback), port: 445)
        #expect(SmbDiscovery.serviceName(of: hostPort) == nil)
    }

    @Test("A named host reads its own string, not a description of itself")
    func addressOfName() {
        #expect(SmbDiscovery.address(of: .name("truenas.local", nil)) == "truenas.local")
    }

    @Test("An IPv4 host prints its dotted address")
    func addressOfIPv4() {
        #expect(SmbDiscovery.address(of: .ipv4(.loopback)) == "127.0.0.1")
    }

    /// Whether ``listening()``'s continuation has already resumed, held outside the closure
    /// so the closure itself captures no mutable state -- `NWListener.stateUpdateHandler` can
    /// report `.ready` and a later state on different turns, and only the first may resume.
    private final class ResumeGuard: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false
        func firstTime() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard !done else { return false }
            done = true
            return true
        }
    }

    /// Starts a bare TCP listener on loopback and returns it once it is ready to accept.
    private static func listening() async throws -> NWListener {
        let listener = try NWListener(using: .tcp)
        listener.newConnectionHandler = { $0.cancel() }
        let guarded = ResumeGuard()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready where guarded.firstTime():
                    continuation.resume()
                case let .failed(error) where guarded.firstTime():
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }
            listener.start(queue: .main)
        }
        return listener
    }

    @Test("Resolving a service against a real listener fills the address and the port")
    func resolvesToAnAddress() async throws {
        let listener = try await Self.listening()
        defer { listener.cancel() }
        let port = try #require(listener.port, "a ready listener has a port")

        let discovery = SmbDiscovery()
        defer { discovery.stop() }
        discovery.resolve(name: "TrueNAS", endpoint: .hostPort(host: .ipv4(.loopback), port: port))

        // The connection resolves asynchronously; poll `hosts` rather than assume one hop.
        for _ in 0..<50 where discovery.hosts.isEmpty {
            try await Task.sleep(for: .milliseconds(20))
        }
        let host = try #require(discovery.hosts.first, "the resolve never completed")
        #expect(host.name == "TrueNAS")
        #expect(host.address == "127.0.0.1")
        #expect(host.port == Int(port.rawValue))
    }
}
