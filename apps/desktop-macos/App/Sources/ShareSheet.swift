import LibraryFeature
import Smb
import StoryArcCore
import SwiftUI

/// Adding a network share: the shares the network announces, the address by hand, the
/// sign-in, then the folder to read.
///
/// `desktop-experience`, *Finding and reaching a network share*: announced shares are
/// suggestions that fill the address, the address field is always there, and each refusal
/// is named in grey (the package's own sentences, which name encryption when a share needs
/// it). Discovery is Bonjour (`_smb._tcp`), behind the local-network text in `Info.plist`.
/// The state machine is StoryArcKit's `SmbConnection`; this is its Mac face.
struct ShareSheet: View {
    let sources: MacSources
    @Environment(\.dismiss) private var dismiss
    @State private var discovery = SmbDiscovery()

    private var connection: SmbConnection { sources.share }

    var body: some View {
        @Bindable var connection = connection
        VStack(spacing: 0) {
            SheetTitle(title: "desktop.sources.add.share.title")
            Form {
                if case let .browsing(identity, path, entries) = connection.step {
                    browsing(identity: identity, path: path, entries: entries)
                } else {
                    discovered
                    Section {
                        TextField(text: $connection.host, prompt: Text(verbatim: "nas.local")) {
                            Text("desktop.share.host")
                        }
                        TextField(text: $connection.share, prompt: Text("desktop.share.share.prompt")) {
                            Text("desktop.share.share")
                        }
                    } footer: {
                        Text("desktop.share.address.footer").foregroundStyle(.secondary)
                    }
                    Section {
                        TextField(text: $connection.username) { Text("desktop.share.user") }
                        SecureField(text: $connection.password) { Text("desktop.share.password") }
                    } footer: {
                        Text("desktop.share.signIn.footer").foregroundStyle(.secondary)
                    }
                    status
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
        .task { if sources.discoversShares { discovery.start() } }
        .onDisappear { discovery.stop() }
    }

    @ViewBuilder
    private var discovered: some View {
        Section {
            if discovery.hosts.isEmpty {
                if let advice = discovery.advice {
                    Text(advice).foregroundStyle(.secondary)
                } else {
                    Text("desktop.share.discovery.none").foregroundStyle(.secondary)
                }
            }
            ForEach(discovery.hosts) { host in
                Button {
                    connection.host = host.port == SmbAddress.defaultPort
                        ? host.address : "\(host.address):\(host.port)"
                } label: {
                    Label(host.name, systemImage: "externaldrive.connected.to.line.below")
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("desktop.share.discovery")
        }
    }

    @ViewBuilder
    private var status: some View {
        switch connection.step {
        case .connecting:
            Section { ProgressView().controlSize(.small).accessibilityLabel(Text("desktop.share.connecting")) }
        case let .failed(sentence):
            Section { Text(sentence).foregroundStyle(.secondary) }
        case .entering, .browsing:
            EmptyView()
        }
    }

    @ViewBuilder
    private func browsing(identity: SmbIdentity, path: String, entries: [SmbEntry]) -> some View {
        Section {
            (identity.isEncrypted ? SourceRow.Line.encrypted(dialect: identity.dialect)
                : .notEncrypted(dialect: identity.dialect)).text
                .foregroundStyle(.secondary)
        } header: {
            Text("desktop.share.connected")
        }
        Section {
            if let parent = connection.parent(of: path) {
                Button { Task { await connection.enter(parent) } } label: {
                    Label("desktop.share.up", systemImage: "arrow.turn.left.up")
                }
                .buttonStyle(.plain)
            }
            ForEach(entries.filter(\.isDirectory)) { entry in
                Button { Task { await connection.enter(entry.path) } } label: {
                    Label(entry.name, systemImage: "folder")
                }
                .buttonStyle(.plain)
            }
        } header: {
            if path.isEmpty { Text("desktop.share.root") } else { Text("desktop.share.folder \(path)") }
        } footer: {
            Text("desktop.share.folder.footer").foregroundStyle(.secondary)
        }
    }

    private var primaryTitle: LocalizedStringKey {
        if case .browsing = connection.step { return "desktop.share.add" }
        return "desktop.share.connect"
    }

    private var isPrimaryEnabled: Bool {
        if case .browsing = connection.step { return true }
        return connection.canConnect
    }

    private func primary() {
        if case .browsing = connection.step {
            guard let source = connection.source() else { return }
            if connection.replacing != nil { sources.replace(source) } else { sources.add(source) }
            connection.reset()
            dismiss()
        } else {
            Task { await connection.connect() }
        }
    }

    private func close() {
        connection.reset()
        sources.adding = nil
        dismiss()
    }
}

/// The two buttons at the foot of every add sheet: Cancel, and the one action that moves on.
struct SheetButtons: View {
    let primary: LocalizedStringKey
    let isPrimaryEnabled: Bool
    let onCancel: () -> Void
    let onPrimary: () -> Void

    var body: some View {
        HStack {
            Spacer()
            Button(role: .cancel, action: onCancel) { Text("desktop.sheet.cancel") }
                .keyboardShortcut(.cancelAction)
            Button(action: onPrimary) { Text(primary) }
                .keyboardShortcut(.defaultAction)
                .disabled(!isPrimaryEnabled)
        }
        .padding()
    }
}

/// The bold line at the head of an add sheet, as a Mac sheet names what it asks.
struct SheetTitle: View {
    let title: LocalizedStringKey

    var body: some View {
        Text(title)
            .scaledFont(.headline)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding([.top, .horizontal], 20)
            .accessibilityAddTraits(.isHeader)
    }
}

/// The size every add sheet shares, so switching kinds does not jump.
enum SourceSheet {
    static let width: CGFloat = 480
    static let height: CGFloat = 520
}
