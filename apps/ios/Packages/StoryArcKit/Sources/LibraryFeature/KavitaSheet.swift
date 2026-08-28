public import SwiftUI

internal import DesignSystem
internal import Kavita
public import StoryArcCore

/// Adding a Kavita server.
///
/// The same shape as ``CatalogueSheet``, because it is the same job: an address, whatever
/// proof of identity the server wants, and a confirmation before anything is saved.
public struct KavitaSheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    private let connection: KavitaConnection
    private let onAdd: (Source) -> Void

    public init(connection: KavitaConnection, onAdd: @escaping (Source) -> Void) {
        self.connection = connection
        self.onAdd = onAdd
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: StoryArcSpace.lg) {
                    address
                    key

                    Button {
                        Task { await connection.connect() }
                    } label: {
                        Text("kavita.connect", bundle: .module)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, StoryArcSpace.xs)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!connection.canConnect)

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
                    case let .confirmed(identity):
                        confirmation(identity)
                    case let .failed(message):
                        CatalogueFailure(message: message) {
                            Task { await connection.connect() }
                        }
                    }
                }
                .padding(StoryArcSpace.gutter)
            }
            .background(theme.palette.surfaceCanvas)
            .navigationTitle(Text("kavita.title", bundle: .module))
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
            Text("kavita.address.label", bundle: .module)
                .textRole(.headline)
                .foregroundStyle(theme.palette.textPrimary)

            TextField(
                text: Binding(get: { connection.address }, set: { connection.address = $0 }),
                prompt: Text("kavita.address.prompt", bundle: .module)
            ) {
                Text("kavita.address.label", bundle: .module)
            }
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .autocorrectionDisabled()
            #if os(iOS)
            .textInputAutocapitalization(.never)
            .keyboardType(.URL)
            #endif

            Text("kavita.address.hint", bundle: .module)
                .textRole(.footnote)
                .foregroundStyle(theme.palette.textSecondary)
        }
    }

    /// The key field, hidden when the address already carries one.
    ///
    /// Asking for something the reader has already given is how a form makes someone feel
    /// they typed it wrong.
    @ViewBuilder
    private var key: some View {
        if connection.addressCarriesKey {
            Label {
                Text("kavita.keyFromAddress", bundle: .module)
                    .textRole(.footnote)
            } icon: {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(StoryArcColor.Status.success)
            }
            .foregroundStyle(theme.palette.textSecondary)
        } else {
            VStack(alignment: .leading, spacing: StoryArcSpace.sm) {
                Text("kavita.key.label", bundle: .module)
                    .textRole(.headline)
                    .foregroundStyle(theme.palette.textPrimary)

                SecureField(
                    text: Binding(get: { connection.apiKey }, set: { connection.apiKey = $0 }),
                    prompt: Text("kavita.key.label", bundle: .module)
                ) {
                    Text("kavita.key.label", bundle: .module)
                }
                .labelsHidden()
                .textFieldStyle(.roundedBorder)

                Text("kavita.key.hint", bundle: .module)
                    .textRole(.footnote)
                    .foregroundStyle(theme.palette.textSecondary)
            }
        }
    }

    @ViewBuilder
    private func confirmation(_ identity: KavitaIdentity) -> some View {
        VStack(alignment: .leading, spacing: StoryArcSpace.md) {
            Label {
                Text(
                    "kavita.confirmed \(identity.username) \(identity.version.description)",
                    bundle: .module
                )
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
                Text("kavita.add", bundle: .module)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, StoryArcSpace.xs)
            }
            .buttonStyle(.borderedProminent)
        }
    }
}
