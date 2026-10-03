import SwiftUI

internal import Persistence

/// The conflicts a Kavita source's own background refresh found, waiting to be told to the
/// reader.
///
/// Task 2.9's corrected note: `ServerLibrary.readServers` calls `KavitaSync.pull` for every
/// Kavita source it refreshes — not only the one whose browser is open — and `pull` already
/// resolves and saves the merged record. What it used to throw away is the list of genuine
/// conflicts that merge found, so a conflict a background refresh resolved never reached the
/// `SyncConflictNotice` (D3) the series screen already shows for its own pull.
///
/// Held here, beside the view rather than on `LibraryModel`: `LibraryView.swift` is at its
/// 400-line cap and may not grow past it, so the one line it spends on this reads from a
/// holder of its own rather than a new property there. Android's `RefreshConflicts` is the
/// same split, for the same reason on `LibraryViewModel.kt`.
@MainActor
final class RefreshConflicts: ObservableObject {
    static let shared = RefreshConflicts()

    @Published private(set) var conflicts: [KavitaConflict] = []

    private init() {}

    /// Adds what one refresh found. Call sites hand in every conflict a pull returned.
    func report(_ found: [KavitaConflict]) {
        guard !found.isEmpty else { return }
        conflicts += found
    }

    /// The reader has answered — kept the local position, or taken the server's.
    func clear() {
        conflicts = []
    }
}

extension View {
    /// [SyncConflictNotice], fed by [RefreshConflicts] rather than a view's own `@State` —
    /// task 2.9.
    func refreshConflictNotice(progress: ProgressStore?) -> some View {
        modifier(RefreshConflictNoticeModifier(progress: progress))
    }
}

private struct RefreshConflictNoticeModifier: ViewModifier {
    let progress: ProgressStore?
    @ObservedObject private var holder = RefreshConflicts.shared

    func body(content: Content) -> some View {
        // `SyncConflictNotice` only ever writes `[]` back -- every button and the sheet's
        // own dismiss mean "the reader has answered" -- so the setter is `clear()` and
        // nothing reads the value it is given.
        content.syncConflictAlert(
            conflicts: Binding(get: { holder.conflicts }, set: { _ in holder.clear() }),
            progress: progress
        )
    }
}
