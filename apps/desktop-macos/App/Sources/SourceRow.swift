import Foundation
import StoryArcCore
import SwiftUI

/// One configured server in the Sources tab: a share, a catalogue or a Kavita server.
///
/// Free of the view so the rules are asserted (`SourceRowTests`). `sources`: an unreachable
/// source is grey, never red, and keeps its place; a refused sign-in offers one action.
/// `desktop-experience`, *Encryption*: a share states whether its session was encrypted. The
/// answer is the session's own, read from `ShareSessions`, so a share not yet connected in
/// this run claims nothing either way.
struct SourceRow: Identifiable, Equatable {
    enum Kind: Equatable {
        case share, catalogue, kavita

        var symbolName: String {
            switch self {
            case .share: "externaldrive.connected.to.line.below"
            case .catalogue: "books.vertical"
            case .kavita: "server.rack"
            }
        }
    }

    /// A grey line under the name.
    enum Line: Equatable {
        case unreachable
        case needsSignIn
        case encrypted(dialect: String)
        case notEncrypted(dialect: String)
        case transportUnknown

        var text: Text {
            switch self {
            case .unreachable: Text("desktop.sources.unreachable")
            case .needsSignIn: Text("desktop.sources.needsSignIn")
            case let .encrypted(dialect): Text("desktop.sources.encrypted \(dialect)")
            case let .notEncrypted(dialect): Text("desktop.sources.notEncrypted \(dialect)")
            case .transportUnknown: Text("desktop.sources.transportUnknown")
            }
        }
    }

    let id: UUID
    let name: String
    let kind: Kind
    let lines: [Line]
    let isGrey: Bool
    let offersReconnect: Bool
    /// Where the source is, with no user name in it.
    let address: String

    init(server: Source, transport: ShareTransport?) {
        id = server.id
        name = server.displayName
        kind = switch server.kind {
        case .networkShare, .localFolder: .share
        case .opdsCatalog: .catalogue
        case .kavitaServer: .kavita
        }
        address = Self.address(of: server.locator)
        var lines: [Line] = []
        switch server.state {
        case .unreachable: lines.append(.unreachable)
        case .unauthorized: lines.append(.needsSignIn)
        case .connected, .connecting: break
        }
        if kind == .share, lines.isEmpty {
            if let transport {
                lines.append(transport.isEncrypted
                    ? .encrypted(dialect: transport.dialect) : .notEncrypted(dialect: transport.dialect))
            } else {
                lines.append(.transportUnknown)
            }
        }
        self.lines = lines
        isGrey = !lines.allSatisfy { line in
            switch line {
            case .encrypted, .notEncrypted, .transportUnknown: true
            case .unreachable, .needsSignIn: false
            }
        }
        offersReconnect = server.state.needsUserAction
    }

    /// The locator with any user name and query cut out: a row is no place for either.
    static func address(of locator: String?) -> String {
        guard let locator, var parts = URLComponents(string: locator) else { return locator ?? "" }
        parts.user = nil
        parts.password = nil
        parts.query = nil
        return parts.string ?? locator
    }
}
