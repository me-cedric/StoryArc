internal import SwiftUI

internal import DesignSystem
internal import StoryArcCore

/// One source, in full, and the five things that can be done to it.
///
/// `sources`: opening a source's detail screen shows "the state, the last successful sync,
/// the last error in plain language, the item count, and the bytes downloaded", and offers
/// "actions to test the connection, refresh, clear the cache, remove downloads, and remove
/// the source". The settings list carried two of the fields and one of the actions; the
/// audit called the gap out, and this is the screen the scenario describes.
///
/// Which actions this particular source is offered is ``SourceDiagnosis``'s answer, not
/// this view's — a decision with three inputs and no pixels belongs where a test can reach
/// it. Android's `SourceDetailScreen` draws the same rows in the same order.
struct SourceDetail: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    let source: Source
    let diagnosis: SourceDiagnosis
    /// Runs one action. Confirmation for the two that delete bytes happens here first.
    let perform: (SourceAction) async -> Void

    @State private var confirming: SourceAction?
    @State private var isWorking = false

    var body: some View {
        List {
            Section {
                field("sources.detail.status", value: Text(Self.status(of: diagnosis.state), bundle: .module))
                field("sources.detail.lastSync", value: syncedAt)
                if let failure = diagnosis.failure {
                    field("sources.detail.lastError", value: message(for: failure))
                }
                field("sources.detail.items", value: Text("sources.detail \(diagnosis.itemCount)", bundle: .module))
                field(
                    "sources.detail.downloaded",
                    value: Text(diagnosis.downloadedBytes.formatted(.byteCount(style: .file)))
                )
            }

            Section {
                ForEach(diagnosis.actions, id: \.self) { action in
                    Button(role: action == .remove ? .destructive : nil) {
                        // The two that delete bytes ask first. The other three are cheap and
                        // undoable by doing them again, and a confirmation on "Refresh" is a
                        // sheet between a reader and the thing they already asked for.
                        if action.isDestructive {
                            confirming = action
                        } else {
                            run(action)
                        }
                    } label: {
                        Text(Self.label(for: action), bundle: .module)
                    }
                    .disabled(isWorking)
                }
            }
        }
        .navigationTitle(source.displayName)
        .confirmationDialog(
            Text(Self.confirmTitle(for: confirming), bundle: .module),
            isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
            titleVisibility: .visible,
            presenting: confirming
        ) { action in
            Button(role: .destructive) {
                run(action)
                confirming = nil
            } label: {
                Text(Self.label(for: action), bundle: .module)
            }
        } message: { action in
            // Stated before it is asked, per `sources`: a reader must not have to guess
            // whether this deletes their comics.
            switch action {
            case .removeDownloads:
                Text(
                    "sources.removeDownloads.body \(diagnosis.downloadedBytes.formatted(.byteCount(style: .file)))",
                    bundle: .module
                )
            default:
                Text("sources.remove.body \(diagnosis.itemCount)", bundle: .module)
            }
        }
    }

    private func run(_ action: SourceAction) {
        Task {
            isWorking = true
            await perform(action)
            isWorking = false
            // The screen goes with the source. A detail screen for a source that is no
            // longer in the registry is a page describing nothing, and its remaining
            // buttons would act on an identifier the app has already forgotten.
            if action == .remove { dismiss() }
        }
    }

    /// A label and its value, on one row. `settings-and-about` puts a setting's current
    /// value beside its name so it can be read without entering anything.
    private func field(_ key: LocalizedStringKey, value: Text) -> some View {
        HStack {
            Text(key, bundle: .module)
                .foregroundStyle(theme.palette.textPrimary)
            Spacer(minLength: StoryArcSpace.md)
            value
                .foregroundStyle(theme.palette.textSecondary)
                .multilineTextAlignment(.trailing)
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }

    private var syncedAt: Text {
        guard let moment = diagnosis.lastSuccessfulSync else {
            return Text("sources.detail.never", bundle: .module)
        }
        return Text(moment.formatted(date: .abbreviated, time: .shortened))
    }

    /// The last error, in the reader's words rather than the network's.
    ///
    /// An unreachable source names when it stopped answering; a refused credential carries
    /// its own sentence already, written where the refusal happened.
    private func message(for failure: SourceFailure) -> Text {
        switch failure {
        case let .unreachable(since):
            Text(
                "sources.detail.error.unreachable \(since.formatted(date: .abbreviated, time: .shortened))",
                bundle: .module
            )
        case let .unauthorized(reason):
            Text(reason)
        }
    }

    private static func status(of state: SourceConnectionState) -> LocalizedStringKey {
        switch state {
        case .connected: "sources.state.connected"
        case .connecting: "sources.state.connecting"
        case .unreachable: "sources.state.unreachable"
        case .unauthorized: "sources.state.unauthorized"
        }
    }

    private static func label(for action: SourceAction) -> LocalizedStringKey {
        switch action {
        case .testConnection: "sources.action.test"
        case .refresh: "sources.action.refresh"
        case .clearCache: "sources.action.clearCache"
        case .removeDownloads: "sources.action.removeDownloads"
        case .remove: "sources.remove"
        }
    }

    private static func confirmTitle(for action: SourceAction?) -> LocalizedStringKey {
        action == .removeDownloads ? "sources.removeDownloads.title" : "sources.remove"
    }
}
