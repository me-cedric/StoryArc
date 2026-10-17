import Catalogue
import Kavita
import LibraryFeature
import StoryArcCore
import SwiftUI

/// Adding an OPDS catalogue: the address, then a sign-in or a certificate when the server
/// asks for one, then its own name as the confirmation before saving (`opds-catalog`).
///
/// The certificate step shows the fingerprint before the offer to trust it, and trusting
/// pins it (`OpdsTrust`, through `CatalogueConnection.trustCertificate()`).
struct CatalogueSheet: View {
    let sources: MacSources
    @Environment(\.dismiss) private var dismiss

    private var connection: CatalogueConnection { sources.catalogue }

    var body: some View {
        @Bindable var connection = connection
        VStack(spacing: 0) {
            SheetTitle(title: "desktop.sources.add.catalogue.title")
            Form {
                Section {
                    TextField(text: $connection.address, prompt: Text("desktop.catalogue.address.prompt")) {
                        Text("desktop.catalogue.address")
                    }
                } footer: {
                    Text("desktop.catalogue.address.footer").foregroundStyle(.secondary)
                }
                switch connection.step {
                case .askingCredentials(scheme: .bearer):
                    Section {
                        SecureField(text: $connection.token) { Text("desktop.catalogue.token") }
                    } header: {
                        Text("desktop.catalogue.signIn")
                    }
                case .askingCredentials:
                    Section {
                        TextField(text: $connection.user) { Text("desktop.share.user") }
                        SecureField(text: $connection.password) { Text("desktop.share.password") }
                    } header: {
                        Text("desktop.catalogue.signIn")
                    }
                case let .untrusted(certificate):
                    Section {
                        Text("desktop.catalogue.untrusted \(certificate.host)")
                        LabeledContent { Text(certificate.subject) } label: { Text("desktop.catalogue.subject") }
                        LabeledContent {
                            Text(certificate.fingerprint).font(.caption.monospaced()).textSelection(.enabled)
                        } label: {
                            Text("desktop.catalogue.fingerprint")
                        }
                    } footer: {
                        Text("desktop.catalogue.untrusted.footer").foregroundStyle(.secondary)
                    }
                case let .confirmed(title):
                    Section { Text("desktop.catalogue.confirmed \(title)") }
                case .connecting:
                    Section { ProgressView().controlSize(.small) }
                case let .failed(sentence):
                    Section { Text(sentence).foregroundStyle(.secondary) }
                case .entering:
                    EmptyView()
                }
            }
            .formStyle(.grouped)
            // Bordered fields: the grouped form's plain ones are 16 points tall, under the
            // 20-point floor the audit holds a control to, and a box says where to type.
            .textFieldStyle(.roundedBorder)
            SheetButtons(
                primary: primaryTitle, isPrimaryEnabled: isPrimaryEnabled,
                onCancel: close, onPrimary: primary
            )
        }
        .frame(width: SourceSheet.width, height: SourceSheet.height)
    }

    private var primaryTitle: LocalizedStringKey {
        switch connection.step {
        case .confirmed: "desktop.catalogue.add"
        case .untrusted: "desktop.catalogue.trust"
        case .askingCredentials: "desktop.catalogue.signInAction"
        default: "desktop.share.connect"
        }
    }

    private var isPrimaryEnabled: Bool {
        switch connection.step {
        case .confirmed, .untrusted, .askingCredentials: true
        default: connection.canConnect
        }
    }

    private func primary() {
        switch connection.step {
        case .confirmed:
            guard let source = connection.source() else { return }
            if connection.replacing != nil { sources.replace(source) } else { sources.add(source) }
            dismiss()
        case .untrusted:
            Task { await connection.trustCertificate() }
        case .askingCredentials:
            Task { await connection.submitCredentials() }
        default:
            Task { await connection.connect() }
        }
    }

    private func close() {
        sources.adding = nil
        dismiss()
    }
}

/// Adding a Kavita server: the address and the API key, then the account name the server
/// confirms before saving (`kavita-server`). A pasted OPDS address carries its own key, and
/// the key field goes away for it.
struct KavitaSheet: View {
    let sources: MacSources
    @Environment(\.dismiss) private var dismiss

    private var connection: KavitaConnection { sources.kavita }

    var body: some View {
        @Bindable var connection = connection
        VStack(spacing: 0) {
            SheetTitle(title: "desktop.sources.add.kavita.title")
            Form {
                Section {
                    TextField(text: $connection.address, prompt: Text("desktop.kavita.address.prompt")) {
                        Text("desktop.kavita.address")
                    }
                    if !connection.addressCarriesKey {
                        SecureField(text: $connection.apiKey) { Text("desktop.kavita.apiKey") }
                    }
                } footer: {
                    Text("desktop.kavita.footer").foregroundStyle(.secondary)
                }
                switch connection.step {
                case let .confirmed(identity):
                    Section { Text("desktop.kavita.confirmed \(identity.username)") }
                case .connecting:
                    Section { ProgressView().controlSize(.small) }
                case let .failed(sentence):
                    Section { Text(sentence).foregroundStyle(.secondary) }
                case .entering:
                    EmptyView()
                }
            }
            .formStyle(.grouped)
            // Bordered fields: the grouped form's plain ones are 16 points tall, under the
            // 20-point floor the audit holds a control to, and a box says where to type.
            .textFieldStyle(.roundedBorder)
            SheetButtons(
                primary: isConfirmed ? "desktop.kavita.add" : "desktop.share.connect",
                isPrimaryEnabled: isConfirmed || connection.canConnect,
                onCancel: close, onPrimary: primary
            )
        }
        .frame(width: SourceSheet.width, height: SourceSheet.height)
    }

    private var isConfirmed: Bool {
        if case .confirmed = connection.step { return true }
        return false
    }

    private func primary() {
        guard isConfirmed else {
            Task { await connection.connect() }
            return
        }
        guard let source = connection.source() else { return }
        if connection.replacing != nil { sources.replace(source) } else { sources.add(source) }
        connection.reset()
        dismiss()
    }

    private func close() {
        connection.reset()
        sources.adding = nil
        dismiss()
    }
}

extension View {
    /// Presents whichever add sheet the reader asked for.
    func addingSources(_ sources: MacSources) -> some View {
        sheet(item: Binding(get: { sources.adding }, set: { sources.adding = $0 })) { kind in
            Group {
                switch kind {
                case .share: ShareSheet(sources: sources)
                case .catalogue: CatalogueSheet(sources: sources)
                case .kavita: KavitaSheet(sources: sources)
                }
            }
            .macChrome()
        }
    }
}
