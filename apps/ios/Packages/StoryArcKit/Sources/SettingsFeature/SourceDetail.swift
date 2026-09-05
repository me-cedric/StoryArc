internal import SwiftUI

internal import DesignSystem
internal import Persistence
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
    @Environment(\.dynamicTypeSize) private var typeSize

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
                // ``Persistence/DownloadStore/formatted(_:)`` rather than `.byteCount` here,
                // and the difference is only ever visible at zero — which is every source a
                // reader has just added. The platform style spells zero out unless told not
                // to, so this row read *Zero kB* in English and *Zéro ko* in French while
                // Settings › Downloads, which does use the helper, said *0 bytes* for the
                // same figure. German and Spanish never showed it, which is why it survived
                // a reading of the screen. The September sweep wrote the helper for exactly
                // this and left this call site behind.
                field("sources.detail.downloaded", value: Text(DownloadStore.formatted(diagnosis.downloadedBytes)))
            } footer: {
                // `reading-progress`' *Source cannot store progress*: a source with no
                // progress mechanism keeps positions locally only, "and the source detail
                // screen states that progress for it does not sync". Under the fields rather
                // than beside them, because it is a fact about the source rather than a
                // value that changes — and it belongs on this screen rather than in the
                // list, which describes what a kind of source *is* before one exists.
                if statesProgressIsLocal {
                    Text("sources.detail.progressLocalOnly", bundle: .module)
                }
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
                // The same helper as the field above, so the sentence cannot name a
                // different figure from the row the reader read it on. Reachable at zero
                // only through a finished download that weighs nothing — ``SourceDiagnosis``
                // withholds the action when there are none — but a size written two ways one
                // tap apart is the defect the helper exists to stop, not a rarer one.
                Text(
                    "sources.removeDownloads.body \(DownloadStore.formatted(diagnosis.downloadedBytes))",
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

    /// A label and its value, beside each other — or stacked, where beside would not fit.
    ///
    /// `settings-and-about` puts a setting's current value beside its name so it can be read
    /// without entering anything. Beside is the right shape until the two stop fitting, and on
    /// this screen they stop fitting sooner than most: two of the five values are a date and a
    /// sentence, and *No answer since Sep 5, 2026 at 15:02* already wraps to two lines at the
    /// default size.
    ///
    /// **At the accessibility sizes it wrapped mid-word.** Photographed on 2026-09-05: the
    /// status read `Not an-swering` across three lines of a column a few characters wide, with
    /// the label sitting in its own half of an otherwise empty row. A value squeezed into a
    /// third of the width is not a value beside its name; it is a value hidden behind one.
    ///
    /// So the row stacks at those sizes, label above value, both leading-aligned — which is
    /// what the system's own Settings does with a long value at the same sizes, and what the
    /// grid of theme presets needed for the same reason on the same day. `isAccessibilitySize`
    /// rather than `ViewThatFits`: the two layouts differ in alignment as well as in axis, so
    /// the fallback is a different row rather than the same row narrower, and a reader at those
    /// sizes should get the same shape on every field rather than a mixture decided per value.
    @ViewBuilder
    private func field(_ key: LocalizedStringKey, value: Text) -> some View {
        let name = Text(key, bundle: .module).foregroundStyle(theme.palette.textPrimary)
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: StoryArcSpace.xs) {
                    name
                    value
                        .foregroundStyle(theme.palette.textSecondary)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack {
                    name
                    Spacer(minLength: StoryArcSpace.md)
                    value
                        .foregroundStyle(theme.palette.textSecondary)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }

    /// Whether this screen has to say that a position for this source stays on the device.
    ///
    /// Two clauses, and the second is the one a `kind` alone gets wrong. "On this device" is
    /// a real registered source of kind `.localFolder` — ``ImportedCopies`` puts it in the
    /// registry the moment a reader imports a file — so the kind says it cannot hold a
    /// position, and the sentence written for a folder on a NAS then tells a reader that the
    /// device cannot store progress and that their place is kept on the device. A category
    /// error and a tautology in one line. ``SourcesSettings`` excludes the same identifier
    /// from removal and from `isRemovable` for the same reason: it is not a source the reader
    /// added, it is where the app keeps their own copies.
    private var statesProgressIsLocal: Bool {
        source.id != ImportedCopies.sourceID && !source.kind.syncsReadingProgress
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
        case .reconnect: "sources.action.reconnect"
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
