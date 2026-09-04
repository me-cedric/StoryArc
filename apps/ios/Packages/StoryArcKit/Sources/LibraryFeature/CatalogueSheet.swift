public import SwiftUI

internal import Catalogue
internal import DesignSystem
public import StoryArcCore

/// Adding an OPDS catalogue.
///
/// One screen per step rather than one screen with everything on it. A reader adding a
/// catalogue that works never sees the credential fields or the certificate warning, and a
/// reader who does see the warning is looking at nothing else.
public struct CatalogueSheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    private let connection: CatalogueConnection
    private let onAdd: (Source) -> Void

    public init(connection: CatalogueConnection, onAdd: @escaping (Source) -> Void) {
        self.connection = connection
        self.onAdd = onAdd
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: StoryArcSpace.lg) {
                    address

                    switch connection.step {
                    case .entering:
                        EmptyView()
                    case .connecting:
                        Label {
                            Text("catalogue.connecting", bundle: .module)
                        } icon: {
                            ProgressView()
                        }
                        .textRole(.subheadline)
                        .foregroundStyle(theme.palette.textSecondary)
                    case let .askingCredentials(scheme):
                        CatalogueSignIn(connection: connection, scheme: scheme)
                    case let .untrusted(certificate):
                        CatalogueCertificateWarning(certificate: certificate) {
                            Task { await connection.trustCertificate() }
                        }
                    case let .confirmed(title):
                        confirmation(title)
                    case let .failed(message):
                        CatalogueFailure(message: message) {
                            Task { await connection.connect() }
                        }
                    }
                }
                .padding(StoryArcSpace.gutter)
            }
            .background(theme.palette.surfaceCanvas)
            .navigationTitle(Text("catalogue.title", bundle: .module))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private var address: some View {
        VStack(alignment: .leading, spacing: StoryArcSpace.sm) {
            Text("catalogue.address.label", bundle: .module)
                .textRole(.headline)
                .foregroundStyle(theme.palette.textPrimary)

            TextField(
                text: Binding(
                    get: { connection.address },
                    set: { connection.address = $0 }
                ),
                prompt: Text("catalogue.address.prompt", bundle: .module)
            ) {
                Text("catalogue.address.label", bundle: .module)
            }
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            // A URL is not a sentence. Capitalisation and autocorrection on an address
            // field turn `komga.local` into `Komga. Local` and the reader has to fight it
            // back. The rest of the package carries a macOS platform so pure-Swift targets
            // can be tested on the host, and these three modifiers exist only on iOS.
            .autocorrectionDisabled()
            #if os(iOS)
            .textInputAutocapitalization(.never)
            .keyboardType(.URL)
            .submitLabel(.go)
            #endif
            .onSubmit { Task { await connection.connect() } }

            Text("catalogue.address.hint", bundle: .module)
                .textRole(.footnote)
                .foregroundStyle(theme.palette.textSecondary)

            Button {
                Task { await connection.connect() }
            } label: {
                Text("catalogue.connect", bundle: .module)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, StoryArcSpace.xs)
            }
            // **The one thing on this form that does something, shaped like it.**
            // `.borderedProminent` renders as a plain grey capsule while it is
            // disabled — which is the state a reader meets it in, because the form
            // starts empty — the same colour, height and corner as the field above
            // it. The 2026-09-02 sweep called it "a fifth thing to type into", and
            // the frames agree.
            //
            // `.glassProminent` is how this app emphasises: `design.md` §5 keeps
            // chrome glass untinted so it picks up what is behind it, and the
            // prominent variant is the one meant to carry a tint — a `.tint` on plain
            // `.glass` tints the *material* and flattens it, which
            // `GlassIsUntintedTests` fails the build over. `DetailActions` already
            // uses exactly this trio for the *Read* button, which is the same job:
            // the one functional action on the screen.
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .tint(theme.accent)
            .disabled(!connection.canConnect)
        }
    }

    @ViewBuilder
    private func confirmation(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: StoryArcSpace.md) {
            Label {
                Text("catalogue.confirmed \(title)", bundle: .module)
                    .textRole(.headline)
                    .foregroundStyle(theme.palette.textPrimary)
            } icon: {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(StoryArcColor.Status.success)
            }

            Button {
                guard let source = connection.source() else { return }
                onAdd(source)
                dismiss()
            } label: {
                Text("catalogue.add", bundle: .module)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, StoryArcSpace.xs)
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

/// The credential prompt, for whichever scheme the server asked for.
struct CatalogueSignIn: View {
    @Environment(\.theme) private var theme

    let connection: CatalogueConnection
    let scheme: OpdsError.AuthenticationScheme?

    var body: some View {
        VStack(alignment: .leading, spacing: StoryArcSpace.sm) {
            Text("catalogue.signIn.title", bundle: .module)
                .textRole(.headline)
                .foregroundStyle(theme.palette.textPrimary)

            if scheme == .bearer {
                SecureField(
                    text: Binding(get: { connection.token }, set: { connection.token = $0 }),
                    prompt: Text("catalogue.signIn.token", bundle: .module)
                ) {
                    Text("catalogue.signIn.token", bundle: .module)
                }
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
            } else {
                TextField(
                    text: Binding(get: { connection.user }, set: { connection.user = $0 }),
                    prompt: Text("catalogue.signIn.user", bundle: .module)
                ) {
                    Text("catalogue.signIn.user", bundle: .module)
                }
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .textContentType(.username)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif

                SecureField(
                    text: Binding(get: { connection.password }, set: { connection.password = $0 }),
                    prompt: Text("catalogue.signIn.password", bundle: .module)
                ) {
                    Text("catalogue.signIn.password", bundle: .module)
                }
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .textContentType(.password)
            }

            // Said where the secret is entered, not buried in Privacy. `sources` promises
            // the secure store; a reader typing a password is the moment that promise is
            // worth anything.
            Text("catalogue.signIn.stored", bundle: .module)
                .textRole(.footnote)
                .foregroundStyle(theme.palette.textSecondary)

            Button {
                Task { await connection.submitCredentials() }
            } label: {
                Text("catalogue.signIn.submit", bundle: .module)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, StoryArcSpace.xs)
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

/// The warning shown before a certificate can be pinned.
///
/// `opds-catalog` requires the fingerprint and "an explicit warning" before the offer, in
/// that order. The order is the whole point: an offer above a warning is a button people
/// press.
struct CatalogueCertificateWarning: View {
    @Environment(\.theme) private var theme

    let certificate: UntrustedCertificate
    let onTrust: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: StoryArcSpace.md) {
            Label {
                Text("catalogue.untrusted.title", bundle: .module)
                    .textRole(.headline)
                    .foregroundStyle(theme.palette.textPrimary)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(StoryArcColor.Status.danger)
            }

            Text("catalogue.untrusted.explanation", bundle: .module)
                .textRole(.subheadline)
                .foregroundStyle(theme.palette.textSecondary)

            VStack(alignment: .leading, spacing: StoryArcSpace.hair) {
                Text("catalogue.untrusted.fingerprint", bundle: .module)
                    .textRole(.caption)
                    .foregroundStyle(theme.palette.textSecondary)

                // Monospaced, and selectable. Sixty-four hex digits are compared character
                // by character, and a proportional font makes that harder than it needs to
                // be.
                Text(certificate.fingerprint)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(theme.palette.textPrimary)
                    .textSelection(.enabled)

                Text(certificate.subject)
                    .textRole(.footnote)
                    .foregroundStyle(theme.palette.textSecondary)

                if let expiry = certificate.notValidAfter {
                    Text(
                        "catalogue.untrusted.expires \(expiry.formatted(date: .abbreviated, time: .omitted))",
                        bundle: .module
                    )
                    .textRole(.footnote)
                    .foregroundStyle(theme.palette.textSecondary)
                }
            }
            .padding(StoryArcSpace.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.palette.surfaceRaised, in: .rect(cornerRadius: StoryArcRadius.md))

            // Bordered, not prominent. This is the risky choice on the screen and should not
            // be the one the eye lands on.
            Button(action: onTrust) {
                Text("catalogue.untrusted.trust", bundle: .module)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, StoryArcSpace.xs)
            }
            .buttonStyle(.bordered)
        }
    }
}

/// Anything that went wrong, said plainly, with one way forward.
struct CatalogueFailure: View {
    @Environment(\.theme) private var theme

    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: StoryArcSpace.md) {
            Text(message)
                .textRole(.subheadline)
                .foregroundStyle(theme.palette.textPrimary)

            Button(action: onRetry) {
                Text("catalogue.retry", bundle: .module)
            }
            .buttonStyle(.bordered)
        }
        .padding(StoryArcSpace.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.palette.surfaceRaised, in: .rect(cornerRadius: StoryArcRadius.md))
    }
}
