import AppKit
import SwiftUI
import Formats
import Foundation
import LibraryFeature
import Persistence
import Smb
import StoryArcCore
import Testing

@testable import StoryArc

extension WindowWalks {
    /// Task 3.10's walk: each kind of source added against the repository's mock servers,
    /// through the same connection the add sheet drives, into the running app's library.
    ///
    /// `sources`, `network-share`, `opds-catalog`, `kavita-server` and `desktop-experience`'s
    /// *Finding and reaching a network share*. Each walk removes what it added, so the
    /// catalogue's screens never meet a server. A server that is not running skips its walk
    /// and says which (`MockServers`).
    @MainActor
    @Suite("Sources walk")
    struct SourcesWalkTests {
        @Test("An OPDS catalogue is added, named by its own feed, and its books join the library",
              .enabled(if: MockServers.isOpdsUp, "the OPDS mock is not running (pnpm opds)"))
        func catalogue() async throws {
            let library = try await Walk.library()
            let connection = library.servers.catalogue
            connection.address = MockServers.opdsRoot
            await connection.connect()
            guard case let .confirmed(title) = connection.step else {
                Issue.record("the catalogue did not confirm: \(connection.step)")
                return
            }
            #expect(!title.isEmpty)
            let source = try #require(connection.source())
            try await addAndRemove(source, in: library) { added in try await Self.browse(added, in: library) }
        }

        /// The source's own window: the phones' browser lists the feed, and a rename reaches the registry
        /// (`opds-catalog`, *Browsing a navigation feed*; `sources`, *Renaming a source*).
        static func browse(_ source: Source, in library: MacLibrary) async throws {
            let window = NSWindow(contentViewController: NSHostingController(
                rootView: SourceWindow(library: library, sourceID: source.id)
            ))
            window.setContentSize(NSSize(width: 900, height: 700))
            window.makeKeyAndOrderFront(nil)
            defer { window.close() }
            let named = await Walk.until(.seconds(15)) {
                AccessibilityAudit.controls(in: window).first { $0.name.contains("Torn Signal") }?.name
            }
            #expect(named != nil, "the feed's entries were not listed in the source window")
            ConformanceLog.note("source window", "the catalogue lists \(named ?? "nothing")", wave: 5)
            library.model.rename(source, to: "Renamed Catalogue")
            #expect(library.model.registry[source.id]?.displayName == "Renamed Catalogue")
        }

        @Test("A catalogue behind a sign-in asks for it, and the secret goes to the keychain only",
              .enabled(if: MockServers.isOpdsUp, "the OPDS mock is not running (pnpm opds)"))
        func catalogueWithSignIn() async throws {
            let library = try await Walk.library()
            let connection = CatalogueConnection(pins: .app, credentials: library.servers.credentials)
            connection.address = MockServers.opdsPrivate
            await connection.connect()
            guard case .askingCredentials = connection.step else {
                Issue.record("the private feed did not ask for a sign-in: \(connection.step)")
                return
            }
            connection.user = MockServers.opdsUser
            connection.password = MockServers.opdsPassword
            await connection.submitCredentials()
            let source = try #require(connection.source())
            let reference = try #require(source.credentialReference)
            #expect(library.servers.credentials.hasSecret(for: reference))
            #expect(source.locator?.contains(MockServers.opdsPassword) == false)
            try await addAndRemove(source, in: library)
            #expect(!library.servers.credentials.hasSecret(for: reference), "removing the source kept its secret")
        }

        @Test("A Kavita server confirms the account, and its series join the library",
              .enabled(if: MockServers.isKavitaUp, "the Kavita mock is not running (pnpm kavita)"))
        func kavita() async throws {
            let library = try await Walk.library()
            let connection = library.servers.kavita
            connection.address = MockServers.kavitaBase
            connection.apiKey = MockServers.kavitaKey
            await connection.connect()
            guard case let .confirmed(identity) = connection.step else {
                Issue.record("the Kavita server did not confirm: \(connection.step)")
                return
            }
            #expect(identity.username == "ada")
            let source = try #require(connection.source())
            connection.reset()
            try await addAndRemove(source, in: library)
        }

        @Test("A share is reached, states what its session negotiated, and its comics join the library",
              .enabled(if: MockServers.isSmbUp, "the SMB mock is not running (pnpm smb)"))
        func share() async throws {
            let library = try await Walk.library()
            let identity = try await connectShare(port: MockServers.smbPort, in: library)
            #expect(identity.dialect.hasPrefix("SMB"))
            ConformanceLog.note("plain share", "\(identity.dialect), encrypted \(identity.isEncrypted)")
            let source = try #require(library.servers.share.source())
            library.servers.share.reset()
            try await addAndRemove(source, in: library) { added in
                let row = SourceRow(server: added, transport: ShareSessions.shared.transport(forLocator: added.locator))
                #expect(row.lines == [identity.isEncrypted
                        ? .encrypted(dialect: identity.dialect) : .notEncrypted(dialect: identity.dialect)])
            }
        }

        @Test("A share that requires encryption is never read in the clear: encrypted, or refused by name",
              .enabled(if: MockServers.isEncryptedSmbUp, "the encrypted SMB mock is not running"))
        func encryptedShare() async throws {
            let library = try await Walk.library()
            let connection = library.servers.share
            connection.host = "127.0.0.1:\(MockServers.encryptedSmbPort)"
            connection.share = MockServers.smbShare
            connection.username = MockServers.smbUser
            connection.password = MockServers.smbPassword
            await connection.connect()
            defer { connection.reset() }
            switch connection.step {
            case let .browsing(identity, _, _):
                // The vendored client of ADR-0019 negotiates SMB 3 and seals the session.
                #expect(identity.isEncrypted, "a share that requires encryption was read unencrypted")
                ConformanceLog.note(
                    "encrypted share", "connected, \(identity.dialect), encrypted \(identity.isEncrypted)"
                )
            case let .failed(sentence):
                #expect(
                    sentence.localizedCaseInsensitiveContains("encrypt"),
                    "the refusal did not name encryption: \(sentence)"
                )
                ConformanceLog.note("encrypted share", "refused: \(sentence)")
            default:
                Issue.record("the encrypted share left the sheet at \(connection.step)")
            }
        }

        @Test("Bonjour discovery runs and either lists shares or stays quiet; the address field is always there")
        func discovery() async {
            let discovery = SmbDiscovery()
            discovery.start()
            _ = await Walk.until(.seconds(3)) { discovery.hosts.isEmpty ? nil : true }
            let hosts = discovery.hosts.map(\.name)
            ConformanceLog.note("bonjour discovery", "hosts \(hosts), advice \(discovery.advice ?? "none")")
            discovery.stop()
            #expect(discovery.hosts.allSatisfy { !$0.address.isEmpty })
        }

        // MARK: - Steps

        private func connectShare(port: Int, in library: MacLibrary) async throws -> SmbIdentity {
            let connection = library.servers.share
            connection.host = "127.0.0.1:\(port)"
            connection.share = MockServers.smbShare
            connection.username = MockServers.smbUser
            connection.password = MockServers.smbPassword
            await connection.connect()
            guard case let .browsing(identity, _, entries) = connection.step else {
                connection.reset()
                throw WalkFailure("the share did not connect: \(connection.step)")
            }
            #expect(!entries.isEmpty, "the share's root listed nothing")
            return identity
        }

        /// Saves the source as the sheet's Add does, waits for its books, then removes it the
        /// way the Sources tab does and checks they left with it.
        private func addAndRemove(
            _ source: Source, in library: MacLibrary, also check: (Source) async throws -> Void = { _ in }
        ) async throws {
            library.servers.add(source)
            let added = try #require(library.model.registry[source.id] ?? library.model.registry.sources.first {
                $0.locator == source.locator
            })
            let count = await Walk.until(.seconds(20)) {
                library.model.itemCount(of: added.id) > 0 ? library.model.itemCount(of: added.id) : nil
            }
            #expect(count != nil, "\(added.displayName) added nothing to the library")
            ConformanceLog.note("added \(added.kind.rawValue)", "\(added.displayName): \(count ?? 0) publications")
            #expect(library.servers.rows.contains { $0.id == added.id })
            try await check(added)
            library.servers.remove(added.id)
            _ = await Walk.until { library.model.itemCount(of: added.id) == 0 ? true : nil }
            #expect(library.model.registry[added.id] == nil)
            #expect(library.model.itemCount(of: added.id) == 0, "the removed source's books stayed")
        }
    }
}

struct WalkFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
