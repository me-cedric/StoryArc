internal import SwiftUI

internal import DesignSystem
internal import StoryArcCore

/// One primary action, and everything else out of its way.
///
/// `publication-detail` makes this an accessibility requirement rather than a layout
/// preference: exactly one thing the screen wants you to do, first in the reading order
/// after the title, labelled with *which* of read and continue will happen — so a
/// screen-reader user learns the outcome before taking it rather than after.
///
/// Everything else is behind one menu button beside it. Not disabled, absent: an action
/// that cannot apply — removing a download that does not exist, downloading a folder that
/// has no single file to copy — is left out, because a greyed control with no explanation
/// asks the reader to work out what they did wrong.
struct DetailActions: View {
    @Environment(\.theme) private var theme

    let publication: Publication
    let model: LibraryModel
    /// Whether the app's own store holds a copy, as the page last asked.
    @Binding var isKept: Bool
    /// Where the bytes are, or `nil` when the library cannot place them right now.
    let file: URL?
    let onRead: () -> Void

    @State private var isCopying = false
    @State private var isRestarting = false
    @State private var refusedServer: String?

    var body: some View {
        VStack(alignment: .leading, spacing: StoryArcSpace.sm) {
            // `.fixedSize(horizontal:vertical:)` on the row, so the two controls share one
            // height: the primary sets it from its own label and the secondary's circle is
            // measured to match rather than to a number written down here. That matters at
            // the largest text size, where the primary grows and a hard-coded disc would
            // not — and it is why the overflow is a `.frame(maxHeight:)` below rather than
            // a diameter.
            HStack(spacing: StoryArcSpace.md) {
                primary
                secondary
            }
            .fixedSize(horizontal: false, vertical: true)

            if isCopying {
                // `offline-downloads` lets a publication be read while it arrives, so this
                // is a state on the page and never a modal over it. Indeterminate on
                // purpose: this copy has no byte count to report — it is one file move
                // inside the device — and a bar pretending to know how far along it is
                // would be a fiction.
                HStack(spacing: StoryArcSpace.sm) {
                    ProgressView()
                    Text("detail.download.working", bundle: .module)
                        .textRole(.footnote)
                        .foregroundStyle(theme.palette.textSecondary)
                }
            } else if !publication.isOpenable {
                // Named, per `publication-formats`: a refusal says which format it refused.
                Text("library.cell.cannotOpen", bundle: .module)
                    .textRole(.footnote)
                    .foregroundStyle(theme.palette.textSecondary)
            } else if file == nil {
                // The primary action states what it needs rather than failing when taken.
                Text("detail.unavailable", bundle: .module)
                    .textRole(.footnote)
                    .foregroundStyle(theme.palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .refusedByServer($refusedServer, model: model, publication: publication)
        .confirmationDialog(
            Text("library.restart.title \(publication.displayTitle)", bundle: .module),
            isPresented: $isRestarting,
            titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                Task { await model.restart(publication) }
            } label: {
                Text("library.restart.confirm", bundle: .module)
            }
        } message: {
            Text("library.restart.body", bundle: .module)
        }
    }

    // MARK: - The one that matters

    @ViewBuilder
    private var primary: some View {
        if !publication.isOpenable {
            EmptyView()
        } else if file != nil {
            Button(action: onRead) {
                primaryLabel.frame(maxWidth: .infinity)
            }
            // §3.4: the one place in the app a prominent glass button is warranted, because
            // it *is* the most important functional element on the screen.
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .tint(theme.accent)
        } else if canCopy {
            Button {
                copy()
            } label: {
                Text("catalogue.acquire.download", bundle: .module).frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .tint(theme.accent)
            .disabled(isCopying)
        }
    }

    /// *Continue*, *Read*, *Listen* or *Continue listening* — and the wording is the promise.
    ///
    /// Which of the four is ``PrimaryAction``'s decision, asserted there. It said *Read* for an
    /// audiobook until `audiobooks-and-playback`, which was a promise the button never kept:
    /// `StoryArcApp.open(_:at:)` sends an audiobook to the player.
    private var primaryLabel: Text {
        PrimaryAction
            .of(publication.format, hasProgress: (model.readFraction(of: publication) ?? 0) > 0)
            .label
    }

    // MARK: - Everything else

    private var secondary: some View {
        Menu {
            if isKept {
                Button(role: .destructive) { forget() } label: {
                    Label {
                        Text("downloads.remove", bundle: .module)
                    } icon: {
                        Image(systemName: "trash")
                    }
                }
            } else if canCopy, file != nil {
                Button { copy() } label: {
                    Label {
                        Text("catalogue.acquire.download", bundle: .module)
                    } icon: {
                        Image(systemName: "arrow.down.circle")
                    }
                }
            }

            AddToShelfMenu(
                model: model,
                publications: [publication],
                onRefused: { refusedServer = $0 },
                onRestart: { isRestarting = true }
            )
        } label: {
            // Fills whatever height the row settled on, and stays a circle by matching its
            // width to it. A 44 × 44 frame used to sit here instead, *inside* a `.large`
            // control, so the disc came out as the glyph plus a hit target plus the control's
            // own padding — half again as tall as the button it pairs with. Dropping the
            // frame alone left it too small; the answer is neither number, it is the height
            // of the thing beside it.
            Image(systemName: "ellipsis")
                .frame(maxHeight: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .contentShape(.rect)
        }
        .menuStyle(.button)
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .controlSize(.large)
        // An ellipsis has nothing to announce. Named rather than left to VoiceOver, which
        // would read the glyph's own description and tell a reader nothing about what is
        // behind it.
        .accessibilityLabel(Text("detail.more", bundle: .module))
    }

    /// Whether there is anything here a copy could be made of.
    ///
    /// A folder of images is already on the device and has no single file to copy, which is
    /// why ``LibraryModel/keepOffline(_:)`` skips it — offering the action anyway would be a
    /// button that reports success and changes nothing.
    private var canCopy: Bool {
        publication.isOpenable && publication.format != .imageFolder
    }

    private func copy() {
        isCopying = true
        Task {
            let kept = await model.keepOffline([publication.id])
            isCopying = false
            // Asked of the store rather than assumed from the call: the copy can be skipped
            // for a publication whose file could not be read, and a page that said "on this
            // device" on the strength of having tried is the lie this screen exists to
            // prevent.
            isKept = model.keptOffline.contains(publication.id)
            _ = kept
        }
    }

    private func forget() {
        model.forgetKept([publication.id])
        isKept = model.keptOffline.contains(publication.id)
    }
}
