internal import SwiftUI

internal import DesignSystem
internal import Formats
internal import Smb
internal import StoryArcCore

/// A remote PDF on the publication page, fetched whole and then opened.
///
/// `publication-formats`, *Opening a remote PDF on iOS*: "the app fetches the whole file
/// first, shows how far the fetch has come, and opens the PDF reader when it ends", and "a
/// fetch that fails is stated as a connection failure, not as a fault in the file". PDFKit
/// opens a whole file only, so O4 keeps PDFKit and fetches; there is no offer to accept first.
///
/// The share browser already fetched this way. The page offered a download instead, which is
/// task 14.15. Outside the view, with one callback per outcome, so ``ShareFetchTests`` drives
/// it with a source of its choosing and watches which callback fires.
@MainActor
enum ShareFetch {
    /// Where fetched shares land: the same cache folder the share browser uses.
    static var directory: URL {
        URL.cachesDirectory.appending(path: "Smb", directoryHint: .isDirectory)
    }

    /// The share's bytes, through the opener the app registers for `smb` at launch.
    static func source(for share: URL) async throws -> any RandomAccessSource {
        guard let source = try await ComicArchiveOpener.source(for: share) else {
            throw SmbError.shareNotFound
        }
        return source
    }

    /// Fetches the whole file behind `address`, reports how far it has come, then opens it.
    ///
    /// `progress` hears a fraction from 0 to 1 after each chunk. Any failure, of the share or
    /// of the copy, is said as ``ShareOpening/unexpected`` — "The share could not be
    /// reached." — because the file was never read, so nothing is known about it.
    static func fetch( // swiftlint:disable:this function_parameter_count
        _ publication: Publication,
        at address: URL,
        into directory: URL,
        source: () async throws -> any RandomAccessSource,
        progress: @escaping @Sendable (Double) -> Void,
        onOpen: (Publication, URL) -> Void,
        onSay: (LocalizedStringResource) -> Void
    ) async {
        do {
            // The server named this file. `cacheLocation` keeps its name from being a place.
            let entry = SmbEntry(name: address.lastPathComponent, path: "", isDirectory: false, length: 0)
            guard let local = entry.cacheLocation(in: directory) else {
                throw SmbError.unexpected(detail: "unusable entry name")
            }
            let remote = try await source()
            let total = Double(max(remote.length, 1))
            progress(0)
            try await ChunkedCopy.copy(remote, to: local) { copied in
                progress(min(Double(copied) / total, 1))
            }
            onOpen(publication, local)
        } catch {
            onSay(ShareOpening.unexpected)
        }
    }
}

/// How far a fetch has come, along the foot of the publication page.
///
/// A determinate bar with the title, the way ``DownloadBanner`` names a transfer, so a reader
/// sees the fetch move rather than a page that does nothing after a tap.
struct ShareFetchBar: View {
    @Environment(\.theme) private var theme

    let title: String
    let fraction: Double

    var body: some View {
        VStack(alignment: .leading, spacing: StoryArcSpace.hair) {
            Text(String(
                format: String(localized: "catalogue.acquire.fetching",
                               bundle: .module.inChosenLanguage, locale: .storyArc),
                title
            ))
            .textRole(.footnote)
            .foregroundStyle(theme.palette.textPrimary)
            .lineLimit(1)

            ProgressView(value: fraction)
        }
        .padding(.horizontal, StoryArcSpace.gutter)
        .padding(.vertical, StoryArcSpace.sm)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }
}
