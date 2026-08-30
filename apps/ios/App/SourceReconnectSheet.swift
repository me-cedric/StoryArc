import Catalogue
import LibraryFeature
import Persistence
import StoryArcCore
import SwiftUI

/// Signing in again to a source whose credential was refused.
///
/// `sources`: when a source returns an authentication failure the app "offers a single
/// action to re-enter credentials, pre-filled with everything except the secret". Neither
/// platform had one — an iOS comment named "remove and re-add" as the workaround, which
/// loses the source's place in the order, its downloads, and eventually the reading
/// positions its tombstone was holding.
///
/// The sheet the source was added through, re-opened. Not a new, smaller password prompt:
/// a refused credential is often a symptom of the address having moved, and a form that
/// only offers the secret cannot fix that. Reusing the sheet also means the reader is
/// answering the screen they already know.
///
/// In the app layer rather than in `LibraryFeature`, because this is reached from Settings
/// and a feature target never depends on another feature target. Android's `MainActivity`
/// presents the same three sheets from the same place.
struct SourceReconnectSheet: View {
    /// The source being put back. Its identifier and its credential reference travel into
    /// the connection, so what comes out replaces this row rather than joining it.
    let source: Source

    /// Handed the re-authorised source, for the registry to put back in place.
    let onReconnected: (Source) -> Void

    /// Held as state, so a reader who dismisses mid-sign-in and reopens finds what they
    /// typed still there — the same reason `LibraryView` holds its own three.
    @State private var kavita: KavitaConnection
    @State private var catalogue: CatalogueConnection
    @State private var smb: SmbConnection

    init(source: Source, onReconnected: @escaping (Source) -> Void) {
        self.source = source
        self.onReconnected = onReconnected

        let store = CertificatePinStore()
        let kavita = KavitaConnection(credentials: CredentialStore())
        let catalogue = CatalogueConnection(
            pins: CertificatePins(store.pins()),
            credentials: CredentialStore(),
            pinStore: store
        )
        let smb = SmbConnection(credentials: CredentialStore())

        // Filled in before the sheet is on screen. A prefill applied in `task` arrives after
        // the first frame, which a reader sees as an empty field that fills itself in.
        switch source.kind {
        case .kavitaServer: kavita.prefill(from: source)
        case .opdsCatalog: catalogue.prefill(from: source)
        case .networkShare: smb.prefill(from: source)
        case .localFolder: break
        }

        _kavita = State(initialValue: kavita)
        _catalogue = State(initialValue: catalogue)
        _smb = State(initialValue: smb)
    }

    var body: some View {
        switch source.kind {
        case .kavitaServer:
            KavitaSheet(connection: kavita, onAdd: onReconnected)
        case .opdsCatalog:
            CatalogueSheet(connection: catalogue, onAdd: onReconnected)
        case .networkShare:
            SmbSheet(connection: smb, onAdd: onReconnected)
        case .localFolder:
            // Never reached: a folder has no credential to refuse, so `SourceDiagnosis`
            // never offers the action for one. Answered rather than defaulted, so a fifth
            // kind has to be thought about here too.
            EmptyView()
        }
    }
}
