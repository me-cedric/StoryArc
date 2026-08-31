public import SwiftUI

internal import DesignSystem
internal import Formats
internal import Persistence
public import Smb
public import StoryArcCore

/// A share, browsed folder by folder.
///
/// The publication is indexed from the share itself rather than from a copy:
/// `PublicationIndexer` takes a `RandomAccessSource`, and ADR-0008 put that interface there
/// so a remote archive could supply one. The first page of a 400 MB comic costs a few
/// megabytes, not four hundred.
public struct SmbBrowserView: View {
    @Environment(\.theme) private var theme

    private let title: String
    private let address: SmbAddress
    private let path: String
    private let onOpen: (Publication, URL) -> Void

    @State private var entries: [SmbEntry] = []
    @State private var failure: LocalizedStringResource?
    @State private var opening: String?
    /// `network-share`: on a metered connection the reader confirms before the app spends
    /// their data. Held rather than acted on, because the answer is theirs to give.
    @State private var confirming: SmbEntry?
    /// A publication the app cannot read where it lies, waiting for the reader to say whether
    /// the whole file may come across. See ``TransferAsk``.
    @State private var transferring: TransferAsk?
    @State private var cost = NetworkCost()

    /// What the reader is being asked to fetch before they can read it.
    ///
    /// A value rather than a flag, for ``MeteredAsk``'s reason: the dialog names the
    /// publication and states its size, and both have to survive being raised from inside
    /// the work that discovered them.
    private struct TransferAsk: Identifiable, Equatable {
        let entry: SmbEntry
        /// What the share said the file weighs. `publication-formats` requires the size to be
        /// stated, and a directory entry is where it comes from.
        let bytes: Int64

        var id: String { entry.path }
    }

    public init(
        title: String,
        address: SmbAddress,
        path: String = "",
        onOpen: @escaping (Publication, URL) -> Void = { _, _ in }
    ) {
        self.title = title
        self.address = address
        self.path = path
        self.onOpen = onOpen
    }

    public var body: some View {
        List {
            if let failure {
                Text(failure)
                    .textRole(.footnote)
                    .foregroundStyle(theme.palette.textSecondary)
            }
            ForEach(entries) { entry in
                if entry.isDirectory {
                    NavigationLink {
                        SmbBrowserView(
                            title: title,
                            address: address,
                            path: entry.path,
                            onOpen: onOpen
                        )
                    } label: {
                        Label(entry.name, systemImage: "folder")
                    }
                } else {
                    Button {
                        if cost.isCareful {
                            confirming = entry
                        } else {
                            Task { await open(entry) }
                        }
                    } label: {
                        HStack {
                            Label(entry.name, systemImage: "book")
                                .foregroundStyle(theme.palette.textPrimary)
                            Spacer(minLength: 0)
                            if opening == entry.path { ProgressView() }
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .disabled(opening != nil)
                }
            }
        }
        .navigationTitle(path.isEmpty ? title : String(path.split(separator: "/").last ?? ""))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .confirmationDialog(
            Text("smb.metered.title", bundle: .module),
            isPresented: Binding(
                get: { confirming != nil },
                set: { if !$0 { confirming = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button {
                if let entry = confirming {
                    confirming = nil
                    Task { await open(entry) }
                }
            } label: {
                Text("smb.metered.continue", bundle: .module)
            }
            Button(role: .cancel) { confirming = nil } label: {
                Text("smb.cancel", bundle: .module)
            }
        } message: {
            Text("smb.metered.body \(confirming?.name ?? "")", bundle: .module)
        }
        // `publication-formats`, *Streaming capability per format*: a publication that cannot
        // be read with ranged reads gets a sentence, a size and an offer — never a transfer
        // the reader did not ask for, and never a stalled page.
        .confirmationDialog(
            Text("smb.downloadFirst.title", bundle: .module),
            isPresented: Binding(
                get: { transferring != nil },
                set: { if !$0 { transferring = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button {
                if let ask = transferring {
                    transferring = nil
                    Task { await transfer(ask.entry) }
                }
            } label: {
                Text("catalogue.acquire.download", bundle: .module)
            }
            Button(role: .cancel) { transferring = nil } label: {
                Text("smb.cancel", bundle: .module)
            }
        } message: {
            // Lifted out rather than interpolated in place, for `MeteredConfirmation`'s
            // reason: `scripts/ios-strings.mjs` derives the key by reading the literal, and a
            // nested quote ends the literal early.
            let named = transferring?.entry.name ?? ""
            let size = formattedBytes(transferring?.bytes ?? 0)
            Text("smb.downloadFirst.body \(named) \(size)", bundle: .module)
        }
        .task(id: path) {
            guard entries.isEmpty else { return }
            do {
                entries = try await SmbClient(address: address).list(path)
                failure = nil
            } catch {
                failure = unexpected
            }
        }
    }

    /// Opens a publication that lives on the share, or says what it would cost to.
    ///
    /// The index itself is ranged reads over the share — a header, not a file. The URL handed
    /// back is the share's own for anything the reader can stream, and a local copy only for
    /// the decoders that cannot take a source: PDFKit wants a file, libarchive wants a path,
    /// and the EPUB reader opens one of its own.
    ///
    /// **The copy is offered, not taken.** This used to fetch the whole file the moment
    /// `PublicationIndexer` handed back a record, so a four-hundred-megabyte comic tapped on
    /// a share came across in silence with its length already in hand.
    /// `publication-formats` asks for the opposite — "the app says the format has to be
    /// downloaded before it can be read, states the size, and offers to download it" — and
    /// ``StreamingOffer`` is where that is decided.
    private func open(_ entry: SmbEntry) async {
        opening = entry.path
        defer { opening = nil }

        do {
            let client = SmbClient(address: address)
            let remote = URL(string: "\(SmbLocator.write(address))/\(entry.path)")
                ?? URL(fileURLWithPath: entry.path)
            let source = try await client.open(entry.path)
            let identity = PublicationIdentity(normalizedPath: remote.absoluteString)

            let catalogued = try await PublicationIndexer.index(
                source: source,
                name: entry.name,
                identity: identity
            )
            switch StreamingOffer.of(
                streaming: catalogued.streaming,
                isLocal: false,
                // A record is how `PublicationIndexer` says the decoder needs a file: a
                // remote PDF, EPUB or CBR comes back `refused` with its pages unreached.
                // Anything else was read from the share's own headers and can go on being.
                readsWhereItLies: catalogued.streaming != .refused,
                bytes: entry.length
            ) {
            case .open:
                onOpen(catalogued, remote)
            case .download(let bytes):
                transferring = TransferAsk(entry: entry, bytes: bytes ?? entry.length)
            case .refuse:
                failure = cannotOpen
            }
        } catch {
            failure = unexpected
        }
    }

    /// Fetches the whole file, then opens the publication from the copy.
    ///
    /// Reached only through the reader's own answer to ``TransferAsk``. The index is done
    /// again against the local file, because that is the first moment the container can say
    /// what it really is: a solid RAR5 becomes ``StreamingCapability/downloadOnly`` and opens,
    /// and a solid RAR4 becomes ``StreamingCapability/refused`` and does not. This used to
    /// open whatever came back, so a reader who had just waited for four hundred megabytes
    /// was taken to a reader that could not render page one.
    private func transfer(_ entry: SmbEntry) async {
        opening = entry.path
        defer { opening = nil }

        do {
            let source = try await SmbClient(address: address).open(entry.path)
            let directory = URL.cachesDirectory.appending(path: "Smb", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            // The server named this file. `cacheLocation` is what keeps its name from
            // being a place — see `SmbEntry`.
            guard let local = entry.cacheLocation(in: directory) else {
                throw SmbError.unexpected(detail: "unusable entry name")
            }
            let existing = try? local.resourceValues(forKeys: [.fileSizeKey]).fileSize
            if existing.map({ Int64($0) }) != entry.length {
                try await source.read(offset: 0, count: Int(entry.length))
                    .write(to: local, options: .atomic)
            }
            let publication = try await PublicationIndexer.index(fileAt: local)
            let offer = StreamingOffer.of(
                streaming: publication.streaming,
                isLocal: true,
                readsWhereItLies: true,
                bytes: entry.length
            )
            if offer == .refuse {
                failure = cannotOpen
            } else {
                onOpen(publication, local)
            }
        } catch {
            failure = unexpected
        }
    }

    /// Said out loud rather than swallowed. A tap that does nothing is the worst answer a
    /// screen can give.
    private var unexpected: LocalizedStringResource {
        LocalizedStringResource("smb.error.unexpected", bundle: .atURL(Bundle.module.bundleURL))
    }

    /// The refusal `publication-formats` requires to be named rather than retried.
    private var cannotOpen: LocalizedStringResource {
        LocalizedStringResource("smb.cannotOpen", bundle: .atURL(Bundle.module.bundleURL))
    }
}
