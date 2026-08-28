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
        Section {
            TextField(
                String(localized: "smb.host.label", bundle: .module),
                text: Binding(get: { connection.host }, set: { connection.host = $0 })
            )
            #if os(iOS)
            .textInputAutocapitalization(.never)
            #endif
            .autocorrectionDisabled()

            TextField(
                String(localized: "smb.share.label", bundle: .module),
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
                String(localized: "smb.user.label", bundle: .module),
                text: Binding(get: { connection.username }, set: { connection.username = $0 })
            )
            #if os(iOS)
            .textInputAutocapitalization(.never)
            #endif
            .autocorrectionDisabled()

            SecureField(
                String(localized: "smb.password.label", bundle: .module),
                text: Binding(get: { connection.password }, set: { connection.password = $0 })
            )
        } footer: {
            Text("smb.user.hint", bundle: .module)
        }

        Section {
            Button {
                Task { await connection.connect() }
            } label: {
                if case .connecting = connection.step {
                    ProgressView()
                } else {
                    Text("smb.connect", bundle: .module)
                }
            }
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
                        String(localized: "smb.up", bundle: .module),
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
            Text(path.isEmpty ? String(localized: "smb.root", bundle: .module) : path)
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
            Button {
                connection.source().map(onAdd)
                dismiss()
            } label: {
                Text("smb.useFolder", bundle: .module)
            }
        }
    }
}
