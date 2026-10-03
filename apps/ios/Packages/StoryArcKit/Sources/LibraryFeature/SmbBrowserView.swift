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
    /// Why the listing is empty, explained where the entries would have been.
    @State private var failure: LocalizedStringResource?
    /// What the app owes the reader about a publication they *tapped*, raised as an alert.
    ///
    /// Both used to be the footnote above the list, and a reader who scrolled down a folder
    /// to reach the file saw nothing change at the top of a list they had scrolled past —
    /// VoiceOver said nothing either, because a `Text` appearing in a `List` is not an
    /// announcement. After a four-hundred-megabyte transfer that ends in a refusal, that was
    /// the whole of the feedback. An alert is announced, and cannot be scrolled away from.
    @State private var notice: LocalizedStringResource?
    @State private var opening: String?
    /// `network-share`: on a metered connection the reader confirms before the app spends
    /// their data. Held rather than acted on, because the answer is theirs to give.
    @State private var confirming: SmbEntry?
    /// A publication the app cannot read where it lies, waiting for the reader to say whether
    /// the whole file may come across. See ``TransferAsk``.
    @State private var transferring: TransferAsk?
    @State private var cost = NetworkCost()
    /// What a row's own headers already said, keyed by its path — filled in as each row
    /// nears the viewport (below), and read back by a tap so it never re-reads what a row
    /// already read. `publication-formats` asks the format, the page count, the cover and
    /// the streaming state to reach the row rather than staying guessed from the filename
    /// until the reader taps it.
    @State private var indexed: [String: Publication] = [:]

    /// What the reader is being asked to fetch before they can read it.
    ///
    /// A value rather than a flag, for ``MeteredAsk``'s reason: the dialog names the
    /// publication and states its size, and both have to survive being raised from inside
    /// the work that discovered them.
    private struct TransferAsk: Identifiable, Equatable {
        let entry: SmbEntry
        /// What the share said the file weighs, or `nil` when it said nothing worth repeating.
        /// `publication-formats` requires the size to be stated and a directory entry is where
        /// it comes from; ``ShareOpening/statedLength(_:)`` is where an unusable one becomes an
        /// absence.
        let bytes: Int64?

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
                            VStack(alignment: .leading) {
                                Label(entry.name, systemImage: "book")
                                    .foregroundStyle(theme.palette.textPrimary)
                                // Named before the tap, not after: a solid archive's
                                // headers already say so, and `publication-formats`
                                // asks for that to reach the reader before a transfer
                                // rather than after one.
                                if indexed[entry.path]?.isOpenable == false {
                                    Text("library.cell.cannotOpen", bundle: .module)
                                        .textRole(.footnote)
                                        .foregroundStyle(theme.palette.textSecondary)
                                }
                            }
                            Spacer(minLength: 0)
                            if opening == entry.path { ProgressView() }
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .disabled(opening != nil)
                    // Composed only for a row SwiftUI has actually laid out — near the
                    // viewport, not the whole list — the same lazy trigger `CoverCell`
                    // already reads a publication's cover with. One ranged read of the
                    // headers; nothing is transferred.
                    .task(id: entry.path) {
                        let found = try? await cachedOrIndexed(
                            cached: indexed[entry.path],
                            index: { try await indexedPublication(for: entry) }
                        )
                        if let found {
                            indexed[entry.path] = found
                        }
                    }
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
            // Two bodies, for `MeteredConfirmation`'s reason: a share that named no length is
            // said in words rather than shown as a zero.
            if let bytes = transferring?.bytes {
                Text("smb.downloadFirst.body \(named) \(formattedBytes(bytes))", bundle: .module)
            } else {
                Text("smb.downloadFirst.bodyUnstated \(named)", bundle: .module)
            }
        }
        // What the tap turned out to owe the reader: the refusal `publication-formats` asks to
        // be named, or an error. The sentence is the alert's title, which is what VoiceOver
        // reads first — `AddToShelfMenu.refusedByServer(_:model:publication:)` is the same
        // shape.
        .alert(
            notice.map { Text($0) } ?? Text(verbatim: ""),
            isPresented: Binding(
                get: { notice != nil },
                set: { if !$0 { notice = nil } }
            )
        ) {
            Button { notice = nil } label: {
                Text("library.import.dismiss", bundle: .module)
            }
        }
        .task(id: path) {
            guard entries.isEmpty else { return }
            do {
                entries = try await SmbClient(address: address).list(path)
                failure = nil
            } catch {
                failure = ShareOpening.unexpected
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
    /// ``ShareOpening/offerOrOpen(index:length:onOpen:onOffer:onRefuse:onFailure:)`` is where
    /// that is decided, so that a test can drive the decision without a share.
    private func open(_ entry: SmbEntry) async {
        opening = entry.path
        defer { opening = nil }

        await ShareOpening.offerOrOpen(
            file: (entry.name, entry.length),
            index: {
                let remote = SmbLocator.entry(entry.path, of: address)
                    ?? URL(fileURLWithPath: entry.path)
                let catalogued = try await cachedOrIndexed(cached: indexed[entry.path]) {
                    try await indexedPublication(for: entry)
                }
                indexed[entry.path] = catalogued
                return (catalogued, remote)
            },
            onOpen: onOpen,
            onOffer: { bytes in transferring = TransferAsk(entry: entry, bytes: bytes) },
            onSay: { said in notice = said }
        )
    }

    /// One ranged read of a row's own headers — a header, not a file.
    private func indexedPublication(for entry: SmbEntry) async throws -> Publication {
        let client = SmbClient(address: address)
        let remote = SmbLocator.entry(entry.path, of: address) ?? URL(fileURLWithPath: entry.path)
        let source = try await client.open(entry.path)
        return try await PublicationIndexer.index(
            source: source,
            name: entry.name,
            identity: PublicationIdentity(normalizedPath: remote.absoluteString)
        )
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

        await ShareOpening.openWhatArrived(
            fetch: {
                let source = try await SmbClient(address: address).open(entry.path)
                let directory = URL.cachesDirectory
                    .appending(path: "Smb", directoryHint: .isDirectory)
                try FileManager.default.createDirectory(
                    at: directory, withIntermediateDirectories: true
                )
                // The server named this file. `cacheLocation` is what keeps its name from
                // being a place — see `SmbEntry`.
                guard let local = entry.cacheLocation(in: directory) else {
                    throw SmbError.unexpected(detail: "unusable entry name")
                }
                let existing = try? local.resourceValues(forKeys: [.fileSizeKey]).fileSize
                if existing.map({ Int64($0) }) != entry.length {
                    // Chunked rather than one `read(offset: 0, count: Int(entry.length))`:
                    // a single request for the whole file is capped by SMB's own reply
                    // length before this file's size ever enters into it, and a solid
                    // archive worth downloading is exactly the file large enough to hit
                    // that cap.
                    try await ChunkedCopy.copy(source, to: local)
                }
                return (try await PublicationIndexer.index(fileAt: local), local)
            },
            onOpen: onOpen,
            onSay: { said in notice = said }
        )
    }
}

/// What a path's own headers already said, or a fresh read of them.
///
/// A free function taking the current cached value rather than reaching into the view's own
/// dictionary, so a test can drive the one thing this screen must get right about the merge —
/// a row that has already answered is never asked again — without an actor-isolated `inout`
/// across the `await` that reading one would need. The caller writes the dictionary back on
/// its own actor, before and after. Android's `cachedOrIndexed` is the same decision, over a
/// `MutableMap` that can hold the lock the whole time. `SmbBrowserViewTests` mutates this to
/// prove it can fail.
@MainActor
func cachedOrIndexed(
    cached: Publication?,
    index: () async throws -> Publication
) async rethrows -> Publication {
    if let cached { return cached }
    return try await index()
}
