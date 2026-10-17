import Catalogue
import Formats
import Foundation
import LibraryFeature
import Persistence
import Smb
import StoryArcCore

/// The servers a reader configured: shares, OPDS catalogues and Kavita servers.
///
/// The connections, the registry, the server reading and the opener for `smb://` addresses
/// are StoryArcKit's; this is the Mac's composition of them, the copy of what the iOS shell
/// does in `StoryArcApp.init` and `StoryArcAppSources.swift` until parent task 5.12 shares
/// it. Secrets go through `CredentialStore`, which lands in the login keychain on an ad-hoc
/// build (`MacCredentialStore.path`, task 1.13); the registry holds only a reference.
@MainActor
@Observable
final class MacSources {
    let model: LibraryModel
    let credentials: CredentialStore
    /// The add sheet on show, if any. Set by the menu, the Sources tab and a walk.
    var adding: AddedSource?

    /// The connections the sheets drive, held so a sheet closed mid-sign-in keeps its fields.
    private(set) var share: SmbConnection
    private(set) var catalogue: CatalogueConnection
    private(set) var kavita: KavitaConnection
    /// Whether the share sheet looks for shares on the network. The catalogue turns it off so
    /// a snapshot does not depend on what the network announces that day.
    var discoversShares = true

    init(model: LibraryModel, credentials: CredentialStore = CredentialStore()) {
        self.model = model
        self.credentials = credentials
        share = SmbConnection(credentials: credentials)
        catalogue = CatalogueConnection(
            pins: .app, credentials: credentials, pinStore: CertificatePinStore()
        )
        kavita = KavitaConnection(credentials: credentials)
        Self.registerOpeners()
    }

    /// Fresh connections, so a sheet opens empty: after a source is saved, and for the catalogue.
    func resetSheets() {
        share = SmbConnection(credentials: credentials)
        catalogue = CatalogueConnection(pins: .app, credentials: credentials, pinStore: CertificatePinStore())
        kavita = KavitaConnection(credentials: credentials)
    }

    /// The configured servers, folders left out: folders have their own rows.
    var servers: [Source] {
        model.registry.sources.filter { $0.kind != .localFolder }
    }

    /// A row for each server, with what its last session negotiated.
    var rows: [SourceRow] {
        servers.map { SourceRow(server: $0, transport: ShareSessions.shared.transport(forLocator: $0.locator)) }
    }

    /// Saves a source a sheet confirmed, and reads what it holds into the library now.
    func add(_ source: Source) {
        model.add(source, credentials: credentials)
        adding = nil
        resetSheets()
        Task { await model.readServers() }
    }

    /// Removes a source with its secret. Downloads and reading positions stay (the sheet says so).
    func remove(_ id: Source.ID) {
        guard let source = model.registry[id] else { return }
        if let key = source.locator.flatMap(ShareKey.init(locator:)) { ShareSessions.shared.forget(key) }
        model.remove(source, credentials: credentials, pins: .app)
    }

    /// Reads every server again: File › Refresh Sources and a source row's Refresh.
    func refresh() async {
        await model.readServers()
    }

    func refresh(_ id: Source.ID) async {
        guard let source = model.registry[id] else { return }
        await model.refresh(source)
    }

    /// The sheet a refused source opens again, with everything filled in but the secret.
    func reconnect(_ id: Source.ID) {
        guard let source = model.registry[id] else { return }
        switch source.kind {
        case .networkShare:
            share.prefill(from: source)
            adding = .share
        case .opdsCatalog:
            catalogue.prefill(from: source)
            adding = .catalogue
        case .kavitaServer:
            kavita.prefill(from: source)
            adding = .kavita
        case .localFolder:
            break
        }
    }

    /// Saves what a sheet re-authorised in the place of the source it replaces.
    func replace(_ source: Source) {
        model.reconnect(source)
        adding = nil
        Task { await model.refresh(source) }
    }

    // MARK: - Openers

    /// How a share's and a catalogue's addresses are read, registered once a launch.
    ///
    /// `Formats` knows nothing of SMB or of a source's credential, so the app teaches it
    /// both, as iOS does in `StoryArcApp.init`.
    private static var areOpenersRegistered = false

    private static func registerOpeners() {
        guard !areOpenersRegistered else { return }
        areOpenersRegistered = true
        HttpSource.register(
            transport: SourceRangeTransport(
                pins: .app, credentials: CredentialStore(), sources: { SourceStore().registry().sources }
            )
        )
        ComicArchiveOpener.register(scheme: "smb") { url in
            // A plain loop rather than the iOS shell's lazy chain: on the Mac the lazy
            // `compactMap` over a tuple trapped while a cover loaded (measured 2026-10-17).
            let credentials = CredentialStore()
            var found: (SmbPage, String)?
            for source in SourceStore().registry().sources where source.kind == .networkShare {
                guard let page = SmbPage(source: source, credentials: credentials),
                      let inside = SmbLocator.inside(url, of: page.address)
                else { continue }
                found = (page, inside)
                break
            }
            guard let (page, inside) = found else { throw SmbError.shareNotFound }
            return try await SmbClient(address: page.address).open(inside)
        }
    }
}
