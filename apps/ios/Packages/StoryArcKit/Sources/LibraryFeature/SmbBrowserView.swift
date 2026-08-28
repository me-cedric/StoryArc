public import SwiftUI

internal import DesignSystem
internal import Formats
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
    @State private var cost = NetworkCost()

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
        .task(id: path) {
            guard entries.isEmpty else { return }
            do {
                entries = try await SmbClient(address: address).list(path)
                failure = nil
            } catch {
                failure = LocalizedStringResource("smb.error.unexpected", bundle: .atURL(Bundle.module.bundleURL))
            }
        }
    }

    /// Opens a publication that lives on the share.
    ///
    /// The index itself is ranged reads over the share — a header, not a file. The URL
    /// handed back is the share's own for anything the reader can stream, and a local copy
    /// only for the decoders that cannot take a source: PDFKit wants a file, libarchive
    /// wants a path, and the EPUB reader opens one of its own.
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
            if catalogued.streaming != .refused {
                return onOpen(catalogued, remote)
            }

            // Refused means the decoder needs a file. Fetch it, and index again with one.
            let directory = URL.cachesDirectory.appending(path: "Smb", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let local = directory.appending(path: entry.name)
            let existing = try? local.resourceValues(forKeys: [.fileSizeKey]).fileSize
            if existing.map({ Int64($0) }) != entry.length {
                try await source.read(offset: 0, count: Int(entry.length))
                    .write(to: local, options: .atomic)
            }
            onOpen(try await PublicationIndexer.index(fileAt: local), local)
        } catch {
            // Said out loud rather than swallowed. A tap that does nothing is the worst
            // answer a screen can give.
            failure = LocalizedStringResource(
                "smb.error.unexpected",
                bundle: .atURL(Bundle.module.bundleURL)
            )
        }
    }
}
