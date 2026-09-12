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
            // **The field was nameless to a screen reader, on the one form where a wrong
            // character means a refused connection.** Measured by an XCUITest dump on
            // 2026-09-11: textFields: [""] and secureTextFields: [""]. The name is drawn as a
            // separate headline above the field and hidden on the field itself, so VoiceOver
            // said "text field" and nothing else. From the same key the headline draws, so
            // the two cannot drift.
            .accessibilityLabel(Text("kavita.address.label", bundle: .module))
            .accessibilityHint(Text("kavita.address.hint", bundle: .module))
            .textFieldStyle(.roundedBorder)
            .autocorrectionDisabled()
            #if os(iOS)
            .textInputAutocapitalization(.never)
            .keyboardType(.URL)
            #endif

            Text("kavita.address.hint", bundle: .module)
                .textRole(.footnote)
                .foregroundStyle(theme.palette.textSecondary)
                // Spoken once, as the field's hint. It stays on screen for everyone else;
                // read as its own element it would be the same sentence twice.
                .accessibilityHidden(true)
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
                // The secret field, and the one this defect mattered most on. See the address
                // field above for what was measured.
                .accessibilityLabel(Text("kavita.key.label", bundle: .module))
                .accessibilityHint(Text("kavita.key.hint", bundle: .module))
                .textFieldStyle(.roundedBorder)

                Text("kavita.key.hint", bundle: .module)
                    .textRole(.footnote)
                    .foregroundStyle(theme.palette.textSecondary)
                    .accessibilityHidden(true)
            }
        }
    }

    @ViewBuilder
    private func confirmation(_ identity: KavitaIdentity) -> some View {
        VStack(alignment: .leading, spacing: StoryArcSpace.md) {
            Label {
                Text("kavita.confirmed \(identity.username)", bundle: .module)
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
