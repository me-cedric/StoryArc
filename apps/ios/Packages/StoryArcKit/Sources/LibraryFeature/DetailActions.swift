internal import SwiftUI

internal import DesignSystem
internal import Persistence
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

    /// Where this publication opens from, which is not always a file.
    ///
    /// `offline-downloads`' *Reading while downloading*: a publication still arriving "opens
    /// immediately by streaming". ``ReadingAddress/of(local:transfer:readsWhereItLies:)``
    /// decides it — a copy on the device when there is one, otherwise the address the
    /// transfer is fetching, otherwise nothing.
    ///
    /// Separate from ``file`` because the two answer different questions. `file` is "is a copy
    /// here", which is what the download action and the provenance line ask. This is "can the
    /// reader open something now", which is what the primary action asks. Overloading one on
    /// the other would offer to download a publication that is already downloading.
    let address: URL?
    /// The chapter a started audiobook would resume inside, when the page knows it. `nil` for
    /// everything else, which is every comic and every book never started.
    let resuming: ChapterName?
    let onRead: () -> Void

    @State private var isCopying = false
    @State private var isRestarting = false
    @State private var refusedServer: String?

    /// The one app-level queue, read for the same reason ``PublicationDetailView`` reads it:
    /// it is `@Observable`, so a bar drawn from its records moves as the bytes arrive.
    @State private var queue = DownloadQueue.shared()

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

            if let transfer {
                // `offline-downloads`' *Progress never moves during a transfer*, on this
                // page: the queue's own record, drawn where the reader asked for the
                // download. A state on the page and never a modal over it, because the
                // spec lets the publication be read while it arrives.
                DetailTransferLine(transfer: transfer, title: publication.displayTitle)
            } else if isCopying {
                // The local copy, which has no byte count to report — it is one file move
                // inside the device — so a bar pretending to know how far along it is
                // would be a fiction.
                HStack(spacing: StoryArcSpace.sm) {
                    ProgressView()
                    Text("detail.download.working", bundle: .module)
                        .textRole(.footnote)
                        .foregroundStyle(theme.palette.textSecondary)
                }
            } else if !publication.isOpenable {
                // Named, per `publication-formats`: a refusal says which format it refused.
                Text(publication.refusalSentence)
                    .textRole(.footnote)
                    .foregroundStyle(theme.palette.textSecondary)
            } else if address == nil {
                // The primary action states what it needs rather than failing when taken,
                // and `publication-formats` asks the download offer to state the size the
                // share browser already states for the same file.
                unavailableText
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

    /// This publication's transfer while it is still on its way, and `nil` once it has
    /// landed — a finished record is what ``isKept`` and the provenance line already say.
    private var transfer: Download? {
        RemoteMemberResolution.record(of: publication, in: queue.library)
            .flatMap { $0.state.isFinished ? nil : $0 }
    }

    /// The sentence under the primary action when nothing can open this publication yet,
    /// with the size stated when the source stated one — the same formatter and the same
    /// rule `SmbBrowserView` already draws its own download offer with.
    private var unavailableText: Text {
        guard let fileSize = publication.fileSize, fileSize > 0 else {
            return Text("detail.unavailable", bundle: .module)
        }
        return Text("detail.unavailable.sized \(formattedBytes(fileSize))", bundle: .module)
    }

    // MARK: - The one that matters

    @ViewBuilder
    private var primary: some View {
        if !publication.isOpenable {
            EmptyView()
        } else if address != nil {
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

    /// *Continue*, *Read*, *Listen*, *Continue listening*, or the chapter it resumes inside —
    /// and the wording is the promise.
    ///
    /// Which of the five is ``PrimaryAction``'s decision, asserted there. It said *Read* for an
    /// audiobook until `audiobooks-and-playback`, which was a promise the button never kept:
    /// `StoryArcApp.open(_:at:)` sends an audiobook to the player.
    private var primaryLabel: Text {
        PrimaryAction
            .of(
                publication.format,
                hasProgress: (model.readFraction(of: publication) ?? 0) > 0,
                chapter: resuming
            )
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
            } else if canCopy, file != nil || shareAddress != nil {
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
                onRefused: { server, _ in refusedServer = server },
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
    /// ``PublicationActions/canCopy(_:file:model:)`` — moved out so ``PublicationActionMenu``
    /// can ask the identical question rather than a second copy of it, which is how its own
    /// menu came to refuse a Kavita chapter this one already drew a working button for. An
    /// action a tap cannot carry out is worse shown than left out, which is this file's own
    /// header.
    private var canCopy: Bool {
        PublicationActions.canCopy(publication, file: file ?? shareAddress, model: model)
    }

    /// This row's share address, when the page resolved one. Task 5.13: ``file`` is `nil` for
    /// a share row — its bytes are not here — so the copy route has to be asked about the
    /// address the page is prepared to read from instead.
    private var shareAddress: URL? {
        address.flatMap { ShareRead.isShare($0) ? $0 : nil }
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

/// What the publication page says about a transfer that is still on its way.
///
/// `offline-downloads` asks a transfer to state what it is doing and how far it has got, and
/// this page is where a reader starts an OPDS download — so it is where that answer has to
/// appear. The page drew nothing at all, because it looked the record up under a key the
/// queue does not use; ``RemoteMemberResolution/downloadID(of:)`` is the key it uses now.
///
/// Determinate only when the server stated a size: ``StoryArcCore/Download/fraction`` answers
/// `nil` rather than zero for exactly that absence, so a bar that could never move is never
/// drawn.
private struct DetailTransferLine: View {
    @Environment(\.theme) private var theme

    let transfer: Download

    /// The publication's own name, which is what the held sentence is about.
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: StoryArcSpace.sm) {
            if let fraction = transfer.fraction {
                ProgressView(value: fraction)
            } else {
                ProgressView()
            }
            Text(sentence)
                .textRole(.footnote)
                .foregroundStyle(theme.palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The state in the reader's words, taken from the words the record already carries: a
    /// failure states the reason the queue wrote, a hold names what is being held, and
    /// everything else is a copy on its way.
    private var sentence: String {
        switch transfer.state {
        case let .failed(reason, _):
            DownloadFailureWords.sentence(stored: reason)
        case .paused:
            String(
                format: String(localized: "downloads.pausedTitle", bundle: .module, locale: .storyArc),
                title
            )
        default:
            String(localized: "detail.download.working", bundle: .module, locale: .storyArc)
        }
    }
}

extension Publication {
    /// The sentence that names why this publication does not open.
    ///
    /// Two things make a publication refused, and they owe different sentences. A solid RAR4
    /// is refused from its headers, and `publication-formats` names solid compression as the
    /// reason. A CB7 share row is refused from its name alone (`SmbContributor`), and the same
    /// spec names the container and the formats StoryArc reads instead. The grid cell, the
    /// list row and the publication page all ask this, so a CB7 is never said to use solid
    /// compression. Android's `refusalSentence` makes the same choice.
    var refusalSentence: String {
        format == .cb7
            ? String(localized: "library.cell.cannotOpen.cb7", bundle: .module, locale: .storyArc)
            : String(localized: "library.cell.cannotOpen", bundle: .module, locale: .storyArc)
    }
}
