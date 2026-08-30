public import SwiftUI

internal import DesignSystem
public import StoryArcCore

/// The page a publication has.
///
/// The seam. `library-browsing` presents a file on the device, a cached catalogue entry, a
/// chapter on a server and a file on a share as one library, and takes origin off every
/// browse surface to do it; this is the one screen that puts origin back — identically
/// composed for all four, with one line at the foot saying which of them this is.
///
/// It is also the app's only screen between the shelf and the reader, so everything that is
/// not reading lives here: downloading, adding to a shelf, marking read, starting over, and
/// the rest of the series.
///
/// **It is never an error page.** Every state is composed from what the device already
/// knows: a publication whose source is away still opens here, from cached metadata, with a
/// cover that may or may not have decoded and a primary action that says what it needs. A
/// screen that only works when the network does would be a screen the reader stops trusting.
public struct PublicationDetailView: View {
    @Environment(\.theme) private var theme
    /// The whole environment, so the palette's own colours can be resolved to hex and put
    /// through the same contrast arithmetic the tokens are held to.
    @Environment(\.self) private var environment

    let publication: Publication
    let model: LibraryModel
    let onOpen: (Publication, URL) -> Void

    /// The cover, once it has been decoded. `nil` is a normal state twice over: before it
    /// arrives, and for a publication that has none.
    @State private var cover: CGImage?
    /// The colour taken from that cover, adjusted until the page's own text clears the
    /// floor over it. `nil` for a cover that has no colour to give.
    @State private var wash: DetailWash?
    /// Whether the app's own store holds a copy. Read when the page appears and after the
    /// reader acts, never on a redraw.
    @State private var isKept = false

    public init(
        publication: Publication,
        model: LibraryModel,
        onOpen: @escaping (Publication, URL) -> Void
    ) {
        self.publication = publication
        self.model = model
        self.onOpen = onOpen
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: StoryArcSpace.xl) {
                DetailHero(publication: publication, cover: cover)
                DetailTitleBlock(publication: publication)
                DetailActions(
                    publication: publication,
                    model: model,
                    isKept: $isKept,
                    file: file,
                    onRead: read
                )
                summary
                series
                DetailProvenanceLine(provenance: provenance)
            }
            // A measure, not a margin. On a 13-inch iPad the description runs to nearly two
            // hundred characters a line and the primary action becomes a metre-wide bar —
            // both of which are the page *filling* the window rather than composing it.
            // Wider than a reading column because the series shelf lives in it too.
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, StoryArcSpace.gutter)
            .padding(.bottom, StoryArcSpace.xxxl)
        }
        .background(DetailBackground(wash: wash))
        // The derived accent, on this subtree only. `Theme.coverAccent` has had a slot and
        // no library caller since it was written — the reader's thumbnails were the only
        // thing in the app that ever set it.
        .coverAccent(wash.map { Color(hex: $0.tint) })
        .navigationTitle(publication.displayTitle)
        // Inline, so the bar stays a thin sliver of glass over the artwork rather than
        // restating the title the page has already set in the editorial face.
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        // Nothing here touches the toolbar's material. `native-experience` requires chrome
        // to stay untinted so it picks up whatever is beneath it, and a navigation bar that
        // took the cover's hue would change colour as the reader moved between publications.
        .task(id: publication.id) {
            isKept = model.keptOffline.contains(publication.id)
            cover = await model.cover(for: publication, maxPixelSize: 900)
        }
        // Keyed on the canvas as well as the cover: the wash is checked against the page it
        // is drawn on, so switching between light and dark is a different question with a
        // different answer, not the same one cached.
        .task(id: WashInputs(hasCover: cover != nil, canvas: canvasHex)) {
            wash = derivedWash()
        }
    }

    // MARK: - Content that may be absent

    /// The description, when the publication carries one.
    ///
    /// Absent rather than empty: the delta refuses a placeholder, and this change does not
    /// alter what the scan collects — if a description is missing today it is missing here.
    @ViewBuilder
    private var summary: some View {
        if let summary = publication.summary, !summary.isEmpty {
            Text(summary)
                .textRole(.body)
                .foregroundStyle(theme.palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var series: some View {
        let rest = DetailSeriesShelf.rest(of: publication, in: model.publications)
        if !rest.isEmpty {
            DetailSeriesShelf(publications: rest, model: model)
        }
    }

    // MARK: - The answers the page is built from

    /// Where the bytes are, or `nil` when the library cannot place them right now.
    private var file: URL? {
        guard publication.isOpenable else { return nil }
        guard let url = model.location(of: publication) else { return nil }
        // A folder whose card was pulled still has rows on the shelf and a location in the
        // model. The page says so rather than offering to open a file that is not there.
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) ? url : nil
    }

    /// The one line at the foot, computed with no network call.
    private var provenance: PublicationProvenance {
        PublicationProvenance.of(
            publication,
            isOnDevice: isKept || model.isOnDevice(publication),
            hasFile: file != nil,
            // `nil` when the publication is unattributed *and* when its source has been
            // removed. `offline-downloads` promises the download outlives the source, and
            // the line must not name a library that no longer exists.
            source: publication.sourceID.flatMap { model.registry[$0] }
        )
    }

    private func read() {
        if let file { onOpen(publication, file) }
    }

    // MARK: - Colour

    private var canvasHex: String { theme.palette.surfaceCanvas.resolvedHex(in: environment) }

    private func derivedWash() -> DetailWash? {
        guard let cover, let pixels = CoverAccent.pixels(of: cover) else { return nil }
        return DetailWash.of(
            cover: pixels,
            canvas: canvasHex,
            text: theme.palette.textPrimary.resolvedHex(in: environment)
        )
    }

    /// What a recomputation of the wash depends on.
    private struct WashInputs: Equatable {
        let hasCover: Bool
        let canvas: String
    }
}
