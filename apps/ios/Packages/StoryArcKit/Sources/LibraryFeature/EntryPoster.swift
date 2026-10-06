import DesignSystem
import Formats
import Foundation
import Kavita
import StoryArcCore
import SwiftUI

/// One chapter's artwork, at the height of a reading-list row.
///
/// Through the client rather than an image loader, for the reason ``KavitaSeriesList`` gives:
/// Kavita's image routes want the reader's key and a loader has nowhere to put one. The fetch
/// lives in the row, so a list of seventy-seven asks the server only for the rows a reader has
/// scrolled to.
///
/// A chapter with no artwork, or a fetch that fails, leaves the frame empty — the row keeps
/// its number, its title and its place, which is what `collections-and-reading-lists` asks
/// for. Android's `rememberChapterCover` is its twin.
struct EntryPoster: View {
    /// How tall the poster is. A row, not a cell: the list is a run of titles.
    static let height: CGFloat = 56

    let chapterID: Int?
    let address: KavitaAddress
    /// The source this list belongs to, which names the chapter the way the library does.
    var serverID: String?

    @Environment(\.theme) private var theme
    @State private var cover: Image?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: StoryArcRadius.sm)
                .fill(theme.palette.surfaceRaised)
            if let cover {
                cover
                    .resizable()
                    .scaledToFill()
                    .clipShape(RoundedRectangle(cornerRadius: StoryArcRadius.sm))
            }
        }
        .frame(height: Self.height)
        .aspectRatio(2.0 / 3.0, contentMode: .fit)
        .clipped()
        .accessibilityHidden(true)
        .task(id: chapterID) {
            guard cover == nil, let chapterID else { return }
            // The reader's own picture first, as the publication page draws it: a chosen
            // cover is the ladder's top rung, and the only one a server row can reach. The
            // server's own cover only where the reader chose none.
            if let chosen = chosenCover(chapterID) {
                cover = Self.image(from: chosen)
                return
            }
            guard let data = try? await KavitaClient(address: address).chapterCover(chapterID)
            else { return }
            cover = Self.image(from: data)
        }
    }

    /// The chapter's chosen cover, under the identity `KavitaContributor` gives it.
    private func chosenCover(_ chapterID: Int) -> Data? {
        guard let serverID, let source = UUID(uuidString: serverID) else { return nil }
        let identity = PublicationIdentity(
            serverIdentifier: .init(sourceID: source, remoteID: "chapter:\(chapterID)")
        )
        let chapter = Publication(identity: identity, format: .cbz, displayTitle: "", origin: .authoritative)
        return CoverOverrideStore().data(for: chapter)
    }

    private static func image(from data: Data) -> Image? {
        #if canImport(UIKit)
        return UIImage(data: data).map(Image.init(uiImage:))
        #else
        return nil
        #endif
    }
}
