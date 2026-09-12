public import SwiftUI

internal import DesignSystem
internal import Persistence
internal import Playback
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

    /// The queue's record for this publication, when one exists.
    ///
    /// Re-read whenever the page appears, like ``DownloadsDestination`` does: a transfer that
    /// started in a catalogue browser has to be known here, not one visit later.
    @State private var transfer: Download?

    /// How this page starts an audiobook at a chosen chapter.
    ///
    /// Separate from ``onOpen`` and optional, because they are different requests: `onOpen`
    /// says "open this book where it was left", and `audio-playback` requires a chosen
    /// chapter to start "at that chapter rather than where the book was left". A stack that
    /// hands over nothing still gets the list — seeing the chapters without starting the book
    /// is half of what the requirement asks — and its rows are text rather than buttons,
    /// because "every control the player offers works, or is absent".
    let onListen: ((Publication, URL, Int) -> Void)?

    /// The cover, once it has been decoded. `nil` is a normal state twice over: before it
    /// arrives, and for a publication that has none.
    @State private var cover: CGImage?
    /// The colour taken from that cover, adjusted until the page's own text clears the
    /// floor over it. `nil` for a cover that has no colour to give.
    @State private var wash: DetailWash?
    /// Whether the app's own store holds a copy. Read when the page appears and after the
    /// reader acts, never on a redraw.
    @State private var isKept = false
    /// What a Kavita server said about this publication when it was kept. Read here rather
    /// than inside ``KavitaCardFacts`` for two reasons: the page already runs one task per
    /// publication, and a view that read the card itself would have to exist in order to
    /// perform the read — which is what left 24 pt of nothing under every description.
    /// `nil` for everything that is not a kept Kavita chapter, which is most of the shelf.
    @State private var kavitaCard: KavitaCard?
    /// The chapters, the length and the chapter to resume inside. ``DetailAudiobook/absent``
    /// until the parts have been read, for every comic, and for an audiobook whose bytes this
    /// device does not hold.
    @State private var audiobook = DetailAudiobook.absent

    public init(
        publication: Publication,
        model: LibraryModel,
        onOpen: @escaping (Publication, URL) -> Void,
        onListen: ((Publication, URL, Int) -> Void)? = nil
    ) {
        self.publication = publication
        self.model = model
        self.onOpen = onOpen
        self.onListen = onListen
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: StoryArcSpace.xl) {
                DetailMainColumn(
                    publication: publication,
                    model: model,
                    cover: cover,
                    isKept: $isKept,
                    kavitaCard: kavitaCard,
                    file: file,
                    address: address,
                    audiobook: audiobook.restated(at: playingPlace),
                    onChooseChapter: chooseChapter,
                    onRead: read
                )
                .frame(maxWidth: SidebarLayout.maxContentWidth)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, StoryArcSpace.gutter)

                // Outside the measure, and that is the change §3.11 asks for: "horizontal
                // shelves touch the leading and trailing edges so the system scrolls them
                // under the sidebar automatically". Held inside the column it was a short
                // run of covers boxed in the middle of a 13-inch window with the shelf
                // ending long before the window did. It carries its own gutter now.
                series

                DetailProvenanceLine(provenance: provenance)
                    .frame(maxWidth: SidebarLayout.maxContentWidth)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, StoryArcSpace.gutter)
            }
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
            kavitaCard = KavitaCardStore().card(of: publication.id)
            transfer = DownloadStore().library()[publication.id]
            cover = await model.cover(for: publication, maxPixelSize: 900)
        }
        // Its own task, and keyed on the file as well as the publication: reading an
        // audiobook's chapter markers opens the container, which is slower than either read
        // above and must not hold the cover behind it. A comic never starts it — the guard is
        // ``DetailChapters/read(_:at:progress:)``'s, so it is asserted rather than assumed.
        //
        // **And keyed on whether this book is the one playing.** ``playingPlace`` restates the
        // rows while a session runs, and answers `nil` the moment it ends — which dropped the
        // page back to the record read when it appeared, an hour of listening ago. The session
        // writes a position as it ends (`audio-playback`, *Where a listening position is
        // written*), so re-reading exactly then is what shows it.
        .task(id: ChapterInputs(file: file, isPlaying: playingPlace != nil)) {
            audiobook = await DetailChapters.read(
                publication,
                at: file,
                progress: model.record(of: publication)
            )
        }
        // Keyed on the canvas as well as the cover: the wash is checked against the page it
        // is drawn on, so switching between light and dark is a different question with a
        // different answer, not the same one cached.
        .task(id: WashInputs(hasCover: cover != nil, canvas: canvasHex)) {
            wash = derivedWash()
        }
    }

    // MARK: - Content that may be absent

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

    /// Where this page opens the publication from, which is not always a file.
    ///
    /// `offline-downloads`' *Reading while downloading* asks a publication that is still
    /// arriving to "open immediately by streaming". ``ReadingAddress`` is the rule, shared
    /// with Android and with the reader; this supplies the two facts only this page holds.
    ///
    /// **The transfer is read from the store rather than from a queue.** A `DownloadQueue` is
    /// state inside whichever catalogue browser started it, so no queue reaches this page —
    /// but every queue writes through ``DownloadStore``, and a `Download`'s id *is* the
    /// publication's, which is what makes the lookup one subscript.
    private var address: URL? {
        ReadingAddress.of(
            local: file,
            transfer: transfer,
            // The formats whose decoder insists on a file of its own are the ones that cannot
            // stream. Stated once, in ``ShareOpening/needsLocalFile(_:)``, because the share
            // browser asks the same question.
            readsWhereItLies: !ShareOpening.needsLocalFile(publication.format)
        )
    }

    /// Where the audio is, when it is this publication's audio, and `nil` otherwise.
    ///
    /// **`PlayerCentre.shared` rather than a centre handed down.** The shell reaches the one
    /// session that way at every call site it has, and threading a centre through four browse
    /// surfaces to reach this page would be a far wider change than the fact it carries. See
    /// ``PlayerCentre/shared``, which the class documents as the one session there can be.
    ///
    /// Reading `place` observes it, so this page redraws while this book plays. That is what a
    /// remainder counting down costs, and it is the reason the question is asked of one
    /// publication rather than of the shelf.
    @MainActor
    private var playingPlace: PlaybackPlace? {
        let centre = PlayerCentre.shared
        guard centre.book?.id == publication.id else { return nil }
        return centre.place
    }

    /// What makes the chapter read run again.
    ///
    /// A struct rather than a tuple, because ``SwiftUI/View/task(id:)`` asks for `Equatable`
    /// and a tuple is not one. ``WashInputs`` below is the same shape for the same reason.
    private struct ChapterInputs: Equatable {
        let file: URL?
        let isPlaying: Bool
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
            source: publication.sourceID.flatMap { model.registry[$0] },
            // The other reading of "in two places": another row on the shelf, under another
            // source. Android has always answered this one and iOS never did — see
            // ``PublicationProvenance/alsoIn``.
            elsewhere: PublicationProvenance.alsoHolding(
                publication,
                in: model.publications,
                registry: model.registry
            )
        )
    }

    private func read() {
        if let address { onOpen(publication, address) }
    }

    /// Starts the book at the chapter a listener chose, when a stack handed over a way to.
    ///
    /// `nil` rather than a closure that does nothing, so ``DetailChapterList`` draws rows
    /// instead of buttons: `audio-playback` requires every control to work or be absent.
    private var chooseChapter: ((Int) -> Void)? {
        guard let onListen, let file else { return nil }
        return { onListen(publication, file, $0) }
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
