internal import SwiftUI

internal import Catalogue
internal import Persistence

/// What the reader is being asked to spend mobile data on.
///
/// A value rather than a flag, because the dialog names the publication and states its
/// size, and both have to survive the sheet being presented from a modifier one level up
/// from the button that raised it.
struct MeteredAsk: Identifiable, Equatable {
    let entry: OpdsEntry
    let acquisition: OpdsAcquisition

    /// What the app can honestly say the download weighs, or `nil` when nothing can.
    let bytes: Int64?

    var id: String { entry.id }
}

extension View {
    /// The confirmation `offline-downloads`' *Overriding once* requires.
    ///
    /// > when a user explicitly downloads a specific publication while on a metered
    /// > connection, the app confirms **with the size** and proceeds **for that item only**.
    ///
    /// A modifier rather than a dialog written into each surface, for
    /// ``restartConfirmation(_:model:)``'s reason: the shelf offers the download from a
    /// context menu and the detail screen offers it from a row, and a second copy of this
    /// wording is a second thing to get wrong. A context menu cannot present a dialog at
    /// all, so the ask has to travel out of the menu either way.
    ///
    /// **The size, and the honest absence of one.** An OPDS acquisition link carries no
    /// `length`, so before a first download the app usually has no figure — and
    /// `offline-downloads` is explicit elsewhere that a fabricated size is worse than an
    /// honest blank. The dialog therefore has two bodies, and the one without a number says
    /// so in words rather than showing a zero. Where a figure *is* known it is formatted by
    /// the platform's own byte formatter, the same one the Downloads destination and the
    /// storage rows use.
    func meteredConfirmation(
        _ ask: Binding<MeteredAsk?>,
        onConfirm: @escaping (MeteredAsk) -> Void
    ) -> some View {
        confirmationDialog(
            // The wording is already translated, four times, for the share that asks the
            // same question before streaming. One question, one sentence.
            Text("smb.metered.title", bundle: .module),
            isPresented: Binding(
                get: { ask.wrappedValue != nil },
                set: { if !$0 { ask.wrappedValue = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button {
                if let asked = ask.wrappedValue { onConfirm(asked) }
                ask.wrappedValue = nil
            } label: {
                Text("catalogue.acquire.download", bundle: .module)
            }
            Button(role: .cancel) { ask.wrappedValue = nil } label: {
                Text("smb.cancel", bundle: .module)
            }
        } message: {
            // The title is lifted out rather than interpolated with its `?? ""` in place:
            // `scripts/ios-strings.mjs` derives the key by reading the literal, and a
            // nested quote ends the literal early — so a two-argument key was checked as a
            // one-argument one and the second half of the sentence went unverified.
            let named = ask.wrappedValue?.entry.title ?? ""
            if let bytes = ask.wrappedValue?.bytes {
                Text("downloads.metered.body \(named) \(formattedBytes(bytes))", bundle: .module)
            } else {
                Text("downloads.metered.bodyUnstated \(named)", bundle: .module)
            }
        }
    }
}
