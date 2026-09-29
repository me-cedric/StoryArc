import SwiftUI

internal import Persistence
internal import StoryArcCore

/// The reader-facing notice for `reading-progress`'s conflicts, once for the whole refresh
/// rather than once per chapter.
///
/// D3: one conflict names both positions in the notice itself. Several give the count and a
/// "Show" action that opens a list naming both positions for every title.
struct SyncConflictNotice: ViewModifier {
    @Binding var conflicts: [KavitaConflict]
    let progress: ProgressStore?

    @State private var showingList = false

    func body(content: Content) -> some View {
        content
            .alert(
                Text("sync.conflict.title", bundle: .module),
                // No setter: each button says what its dismissal means. Clearing here would
                // empty the list `Show` is about to open.
                isPresented: Binding(get: { !conflicts.isEmpty && !showingList }, set: { _ in })
            ) {
                alertButtons
            } message: {
                alertMessage
            }
            // A swipe down is the reader keeping what was kept, not a reason to ask again.
            .sheet(isPresented: $showingList, onDismiss: { conflicts = [] }, content: { list })
    }

    @ViewBuilder
    private var alertButtons: some View {
        Button(role: .cancel) { conflicts = [] } label: {
            Text("sync.conflict.keep", bundle: .module)
        }
        if conflicts.count > 1 {
            Button { showingList = true } label: {
                Text("sync.conflict.show", bundle: .module)
            }
        }
        Button { take(conflicts) } label: {
            Text("sync.conflict.take", bundle: .module)
        }
    }

    @ViewBuilder
    private var alertMessage: some View {
        if conflicts.count == 1, let only = conflicts.first {
            row(only)
        } else {
            Text("sync.conflict.body \(conflicts.count)", bundle: .module)
        }
    }

    /// The list `Show` opens: one row per title, naming both positions -- D3's answer for
    /// several conflicting titles at once.
    private var list: some View {
        NavigationStack {
            List(Array(conflicts.enumerated()), id: \.offset) { _, conflict in
                item(conflict)
            }
            .navigationTitle(Text("sync.conflict.title", bundle: .module))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { showingList = false; conflicts = [] } label: {
                        Text("sync.conflict.keep", bundle: .module)
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button { showingList = false; take(conflicts) } label: {
                        Text("sync.conflict.take", bundle: .module)
                    }
                }
            }
        }
    }

    private func row(_ conflict: KavitaConflict) -> Text {
        let kept = label(conflict.resolved.position)
        let discarded = label(conflict.discarded)
        return Text("sync.conflict.body.one \(conflict.title) \(kept) \(discarded)", bundle: .module)
    }

    private func item(_ conflict: KavitaConflict) -> Text {
        let kept = label(conflict.resolved.position)
        let discarded = label(conflict.discarded)
        return Text("sync.conflict.item \(conflict.title) \(kept) \(discarded)", bundle: .module)
    }

    /// Writes back what was set aside -- the reader saying the further position was not
    /// theirs.
    private func take(_ discarded: [KavitaConflict]) {
        conflicts = []
        Task {
            for conflict in discarded {
                var restored = conflict.resolved
                restored.position = conflict.discarded
                try? await progress?.save(restored)
            }
        }
    }

    /// A position, in the unit it already keeps: a page's own index, or a fraction as a
    /// percentage where there is no page count to name.
    func label(_ position: ReadingPosition) -> String {
        if case let .page(index, total) = position, total > 0 {
            let format = String(localized: "sync.position.page", bundle: .module, locale: .storyArc)
            return String(format: format, index + 1, total)
        }
        let percent = Int((position.fraction * 100).rounded())
        let format = String(localized: "sync.position.percent", bundle: .module, locale: .storyArc)
        return String(format: format, percent)
    }
}

extension View {
    /// Shows `reading-progress`'s conflict notice for a Kavita refresh's merge. Clears
    /// `conflicts` once the reader has decided, on either the alert or the list `Show` opens.
    func syncConflictAlert(conflicts: Binding<[KavitaConflict]>, progress: ProgressStore?) -> some View {
        modifier(SyncConflictNotice(conflicts: conflicts, progress: progress))
    }
}
