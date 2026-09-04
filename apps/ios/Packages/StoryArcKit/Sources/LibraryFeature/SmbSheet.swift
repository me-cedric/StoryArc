public import SwiftUI

internal import DesignSystem
public import Smb
public import StoryArcCore

/// Adding a network share.
///
/// Two steps in one sheet: what to connect to, then which folder to read. `network-share`
/// asks for both — the connection "validated before saving" with the specific failure named,
/// and the reader able to "browse the share's directory tree and pick the folder to use as
/// the library root".
public struct SmbSheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    private let connection: SmbConnection
    private let onAdd: (Source) -> Void

    /// `network-share` marks discovery a SHOULD and is firm that "manual entry is always
    /// available and never gated behind discovery". So the list sits above the form and an
    /// empty one shows nothing at all — no spinner, no "searching", no reason to wait. A
    /// refused local-network permission arrives here as simply no results.
    @State private var discovery = SmbDiscovery()

    public init(connection: SmbConnection, onAdd: @escaping (Source) -> Void) {
        self.connection = connection
        self.onAdd = onAdd
    }

    public var body: some View {
        NavigationStack {
            Form {
                if case let .browsing(identity, path, entries) = connection.step {
                    chooser(identity: identity, path: path, entries: entries)
                } else {
                    details
                }
            }
            .navigationTitle(Text("smb.title", bundle: .module))
            .task { discovery.start() }
            .onDisappear { discovery.stop() }
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text("smb.cancel", bundle: .module) }
                }
            }
        }
    }

    @ViewBuilder
    private var details: some View {
        if !discovery.hosts.isEmpty {
            Section {
                ForEach(discovery.hosts) { host in
                    Button {
                        connection.host = host.name
                    } label: {
                        Label(host.name, systemImage: "externaldrive.badge.wifi")
                    }
                }
            } header: {
                Text("smb.found", bundle: .module)
            }
        }

        Section {
            TextField(
                String(localized: "smb.host.label", bundle: .module, locale: .storyArc),
                text: Binding(get: { connection.host }, set: { connection.host = $0 })
            )
            #if os(iOS)
            .textInputAutocapitalization(.never)
            #endif
            .autocorrectionDisabled()

            TextField(
                String(localized: "smb.share.label", bundle: .module, locale: .storyArc),
                text: Binding(get: { connection.share }, set: { connection.share = $0 })
            )
            #if os(iOS)
            .textInputAutocapitalization(.never)
            #endif
            .autocorrectionDisabled()
        } footer: {
            Text("smb.host.hint", bundle: .module)
        }

        Section {
            TextField(
                String(localized: "smb.user.label", bundle: .module, locale: .storyArc),
                text: Binding(get: { connection.username }, set: { connection.username = $0 })
            )
            #if os(iOS)
            .textInputAutocapitalization(.never)
            #endif
            .autocorrectionDisabled()

            SecureField(
                String(localized: "smb.password.label", bundle: .module, locale: .storyArc),
                text: Binding(get: { connection.password }, set: { connection.password = $0 })
            )
        } footer: {
            Text("smb.user.hint", bundle: .module)
        }

        Section {
            // **The one thing on this form that does something, shaped like it.** Left
            // unstyled inside a `Form`, this drew as a list row — a white capsule the same
            // colour, height and corner as the four field groups above it, with its label in
            // the grey a placeholder wears while it is disabled, which is the state a reader
            // meets it in. The 2026-09-02 sweep called it "a fifth thing to type into", and
            // `ios-add-share-sheet.png` is a picture of five identical white capsules.
            //
            // So the row's own background goes and the button draws its own shape.
            // `.glassProminent` is how this app emphasises: `design.md` §5 keeps chrome glass
            // untinted so it picks up what is behind it, and the prominent variant is the one
            // meant to carry a tint — `.tint` on plain `.glass` tints the *material* and
            // flattens it, which `GlassIsUntintedTests` fails the build over.
            Button {
                Task { await connection.connect() }
            } label: {
                Group {
                    if case .connecting = connection.step {
                        ProgressView()
                    } else {
                        Text("smb.connect", bundle: .module)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, StoryArcSpace.xs)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .tint(theme.accent)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
            .disabled(!connection.canConnect)

            // `network-share` wants the specific failure, and the four the client separates
            // are four different sentences here.
            if case let .failed(message) = connection.step {
                Text(message)
                    .textRole(.footnote)
                    .foregroundStyle(theme.palette.textPrimary)
            }
        }
    }

    @ViewBuilder
    private func chooser(
        identity: SmbIdentity,
        path: String,
        entries: [SmbEntry]
    ) -> some View {
        Section {
            if let parent = connection.parent(of: path) {
                Button {
                    Task { await connection.enter(parent) }
                } label: {
                    Label(
                        String(localized: "smb.up", bundle: .module, locale: .storyArc),
                        systemImage: "arrow.up.left"
                    )
                }
            }
            ForEach(entries.filter(\.isDirectory)) { folder in
                Button {
                    Task { await connection.enter(folder.path) }
                } label: {
                    Label(folder.name, systemImage: "folder")
                }
            }
        } header: {
            Text(path.isEmpty ? String(localized: "smb.root", bundle: .module, locale: .storyArc) : path)
        } footer: {
            // `network-share`: the detail screen states whether the connection is
            // encrypted. Said here too, because this is the moment a reader decides
            // whether to trust it.
            Text(
                identity.isEncrypted
                    ? "smb.encrypted \(identity.dialect)"
                    : "smb.notEncrypted \(identity.dialect)",
                bundle: .module
            )
        }

        Section {
            // The other half of the same journey, and the same argument: this is the action
            // that adds the library, and a list row full of folder rows is where it must not
            // look like one more folder.
            Button {
                connection.source().map(onAdd)
                dismiss()
            } label: {
                Text("smb.useFolder", bundle: .module)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, StoryArcSpace.xs)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .tint(theme.accent)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        }
    }
}
