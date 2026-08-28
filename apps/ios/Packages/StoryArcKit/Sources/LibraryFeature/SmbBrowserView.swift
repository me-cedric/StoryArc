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
                        Task { await open(entry) }
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
    /// The whole file is fetched first. That is not what `network-share` asks for — it wants
    /// the first page of a 400 MB archive without transferring 400 MB — and the pieces for
    /// the better answer are already here: `ComicArchiveOpener.open(source:)` reads a ZIP
    /// through ranged reads, and `SmbClient.open` hands back exactly such a source. What is
    /// missing is an indexer and a reader that take one. Until they do, this downloads, and
    /// says so rather than pretending.
    private func open(_ entry: SmbEntry) async {
        opening = entry.path
        defer { opening = nil }

        do {
            let client = SmbClient(address: address)
            let directory = URL.cachesDirectory.appending(path: "Smb", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

            let local = directory.appending(path: entry.name)
            let existing = try? local.resourceValues(forKeys: [.fileSizeKey]).fileSize
            if existing.map({ Int64($0) }) != entry.length {
                let source = try await client.open(entry.path)
                try await source.read(offset: 0, count: Int(entry.length))
                    .write(to: local, options: .atomic)
            }

            let publication = try await PublicationIndexer.index(fileAt: local)
            onOpen(publication, local)
        } catch {
            // Said out loud rather than swallowed. A tap that does nothing is the worst
            // answer a screen can give.
            failure = LocalizedStringResource("smb.error.unexpected", bundle: .atURL(Bundle.module.bundleURL))
        }
    }
}
