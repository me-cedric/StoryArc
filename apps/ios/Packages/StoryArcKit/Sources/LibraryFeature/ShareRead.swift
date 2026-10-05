internal import SwiftUI

internal import Persistence
internal import StoryArcCore

/// How the library's own page opens a row whose bytes are on a network share.
///
/// ``SmbContributor`` files a share row under the share's own `smb://` address, so the
/// publication page already holds an address the reader's registered opener can take. What
/// the page did not hold is the two things the share browser owes the identical file:
/// `network-share`'s *Metered connection* requires "explicit confirmation before streaming or
/// downloading" on such a link, and `publication-formats` requires a format that cannot be
/// read where it lies to state its size and offer a download rather than open and fail.
///
/// ``ShareOpening/offerOrOpen(file:index:onOpen:onOffer:onSay:)`` is the browser's own rule,
/// asked here with the shelf's row in place of a ranged index read: ``SmbContributor`` already
/// took the format, the streaming capability and the length from the share's directory entry,
/// so a second round trip would only ask the share what the shelf already knows. Android's
/// `ShareRead.kt` is its twin.
@MainActor
enum ShareRead {

    /// Whether this address is a share this app browses rather than a file it holds.
    ///
    /// A scheme test rather than ``Formats/ComicArchiveOpener/isRemote(_:)``, for the reason
    /// Android's `isOnDevice(_:)` already states: that one answers from a table the app layer
    /// fills at start-up, so it is true or false depending on how far the app has booted, and
    /// a host test cannot assert it at all.
    static func isShare(_ address: URL) -> Bool { address.scheme == "smb" }

    /// What a tap on a share row owes the reader before anything is opened.
    enum Ask: Equatable {
        /// The link is one to be careful with, so the reader confirms before bytes move.
        case metered

        /// This format cannot be read where it lies. The size, where the share stated one.
        case download(bytes: Int64?)

        /// Nothing will open this, here or anywhere, and the sentence says which refusal.
        case said(LocalizedStringResource)

        /// Whether this is the offer to fetch the whole file first.
        var isDownloadOffer: Bool {
            guard case .download = self else { return false }
            return true
        }

        /// The size that offer states, and `nil` where the share stated none.
        var offeredBytes: Int64? {
            guard case .download(let bytes) = self else { return nil }
            return bytes
        }

        /// The refusal's sentence, and `nil` for the two asks that are not refusals.
        var sentence: LocalizedStringResource? {
            guard case .said(let said) = self else { return nil }
            return said
        }
    }

    /// What the page does next about `publication`, which lives at `address` on a share.
    ///
    /// `nil` means open it at that address now. Free of SwiftUI so ``ShareReadTests`` can
    /// state every answer without composing the page, which is the lesson
    /// ``ShareOpeningTests`` records: a decision only a text search can reach is a decision
    /// a green suite can lose.
    static func step(
        _ publication: Publication,
        at address: URL,
        isCareful: Bool,
        hasConfirmedMetered: Bool
    ) async -> Ask? {
        if isCareful, !hasConfirmedMetered { return .metered }
        var opened = false
        var ask: Ask?
        await ShareOpening.offerOrOpen(
            file: (publication.displayTitle, publication.fileSize ?? 0),
            index: { (publication, address) },
            onOpen: { _, _ in opened = true },
            onOffer: { bytes in ask = .download(bytes: bytes) },
            onSay: { said in ask = .said(said) }
        )
        return opened ? nil : ask
    }
}

extension View {
    /// The three answers a share row's primary action may owe, drawn as the share browser
    /// draws them: the same titles, the same bodies and the same byte formatter, because one
    /// file reached two ways must not be described two ways.
    func shareReading(
        _ ask: Binding<ShareRead.Ask?>,
        title: String,
        onConfirmMetered: @escaping () -> Void,
        onDownload: @escaping () -> Void
    ) -> some View {
        shareMeteredConfirmation(ask, title: title, onConfirm: onConfirmMetered)
            .shareDownloadOffer(ask, title: title, onDownload: onDownload)
            .shareRefusal(ask)
    }

    /// `network-share`'s *Metered connection*, on the publication page rather than only in
    /// the share browser.
    private func shareMeteredConfirmation(
        _ ask: Binding<ShareRead.Ask?>,
        title: String,
        onConfirm: @escaping () -> Void
    ) -> some View {
        confirmationDialog(
            Text("smb.metered.title", bundle: .module),
            isPresented: shareAskPresented(ask, while: ask.wrappedValue == .metered),
            titleVisibility: .visible
        ) {
            Button {
                ask.wrappedValue = nil
                onConfirm()
            } label: {
                Text("smb.metered.continue", bundle: .module)
            }
            Button(role: .cancel) { ask.wrappedValue = nil } label: {
                Text("smb.cancel", bundle: .module)
            }
        } message: {
            Text("smb.metered.body \(title)", bundle: .module)
        }
    }

    /// `publication-formats`: a publication that cannot be read where it lies is named, sized
    /// and offered — never streamed badly into a stalled page.
    private func shareDownloadOffer(
        _ ask: Binding<ShareRead.Ask?>,
        title: String,
        onDownload: @escaping () -> Void
    ) -> some View {
        confirmationDialog(
            Text("smb.downloadFirst.title", bundle: .module),
            isPresented: shareAskPresented(ask, while: ask.wrappedValue?.isDownloadOffer == true),
            titleVisibility: .visible
        ) {
            Button {
                ask.wrappedValue = nil
                onDownload()
            } label: {
                Text("catalogue.acquire.download", bundle: .module)
            }
            Button(role: .cancel) { ask.wrappedValue = nil } label: {
                Text("smb.cancel", bundle: .module)
            }
        } message: {
            if let bytes = ask.wrappedValue?.offeredBytes {
                Text("smb.downloadFirst.body \(title) \(formattedBytes(bytes))", bundle: .module)
            } else {
                Text("smb.downloadFirst.bodyUnstated \(title)", bundle: .module)
            }
        }
    }

    /// The refusal ``ShareOpening`` named, said rather than swallowed.
    private func shareRefusal(_ ask: Binding<ShareRead.Ask?>) -> some View {
        let sentence = ask.wrappedValue?.sentence
        return alert(
            sentence.map { Text($0) } ?? Text(verbatim: ""),
            isPresented: shareAskPresented(ask, while: sentence != nil)
        ) {
            Button { ask.wrappedValue = nil } label: {
                Text("library.import.dismiss", bundle: .module)
            }
        }
    }

    /// One dialog's presentation, clearing the whole ask when it closes.
    private func shareAskPresented(
        _ ask: Binding<ShareRead.Ask?>,
        while isShown: Bool
    ) -> Binding<Bool> {
        Binding(get: { isShown }, set: { if !$0 { ask.wrappedValue = nil } })
    }
}
