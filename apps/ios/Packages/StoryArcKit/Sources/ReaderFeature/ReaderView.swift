public import SwiftUI

#if os(iOS)
internal import UIKit
#endif

internal import DesignSystem
public import Persistence
public import StoryArcCore

/// The paged comic reader.
///
/// `comic-reader` lists five transition modes. This is **slide**, which is the
/// one that needs no shader — page curl and continuous scroll belong to the
/// `reader-theming-and-page-transitions` change, whose Phase 0 spikes decide how
/// the curl is drawn on each platform. Building a curl here would pre-empt that
/// decision, so it is deliberately absent rather than half-done.
///
/// What is here is the part every mode shares: page order, reading direction,
/// fit, and chrome that gets out of the way.
public struct ReaderView: View {
    @Environment(\.theme) var theme
    @Environment(\.dismiss) var dismiss
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    /// Read here rather than in `ReaderChrome.swift`: an extension cannot hold state.
    @Environment(\.dynamicTypeSize) var dynamicTypeSize

    @State var model: ReaderModel
    /// `comic-reader`: nothing is on screen while the user is reading. The chrome
    /// starts visible so the way out is discoverable, and a tap hides it.
    ///
    /// Internal rather than private because the tap routing lives in
    /// `ReaderNavigation.swift`, and a `private` member cannot cross a file.
    @State var wantsChrome = true

    /// Whether the chrome is on screen.
    ///
    /// Forced on over a failure. The gesture that reveals it lives on the pager, and a
    /// publication that failed to open has no pager — so a reader who let the chrome time
    /// out had a black screen, an error message, and no way back to the library except
    /// force-quitting the app.
    var isChromeVisible: Bool { wantsChrome || model.failure != nil }
    /// The pager's own position, which it owns outright.
    ///
    /// A two-way `Binding` into the model was tried twice and fights the gesture:
    /// `TabView` writes a selection during layout as well as on a swipe, and a
    /// setter that rejects some of those writes leaves the pager and the model
    /// disagreeing about where the reader is. Local state that the model *follows*
    /// has one writer and cannot desynchronise.
    ///
    /// Internal rather than private because the containers live in
    /// `ReaderContainers.swift` and a `private` member cannot cross a file.
    @State var displayIndex = 0

    /// What surrounds this publication in its series, and how to open one of them.
    ///
    /// Supplied by the app layer: the reader does not know what a library is, and a
    /// feature module never depends on another feature module.
    ///
    /// `comic-reader` asks for previous and next chapter actions "without returning to
    /// the library", and one publication of a series is what a chapter is here — so the
    /// same two neighbours answer both the chapter buttons and the end screen.
    let previousInSeries: Publication?
    let nextInSeries: Publication?
    let onOpen: (Publication) -> Void

    /// Supplied by the app layer for the same reason as the above: the reader does not know
    /// what a network share is, and `network-share`'s two thresholds are the only part of
    /// that it needs.
    private let blockedSince: () -> Date?
    private let onDismissTrouble: () -> Void
    private let onDownloadForOffline: (() -> Void)?

    /// Where highlights and notes are kept, or `nil` in a preview.
    ///
    /// The same store the reflowable reader writes to, holding the same record: a mark made
    /// in a PDF and a mark made in a novel come out of one export, which is what
    /// `ebook-reader` means by "listed in one place".
    let annotations: AnnotationStore?

    public init(
        publication: Publication,
        url: URL,
        progress: ProgressStore? = nil,
        preferences: ReaderPreferences? = nil,
        annotations: AnnotationStore? = nil,
        previousInSeries: Publication? = nil,
        nextInSeries: Publication? = nil,
        onOpen: @escaping (Publication) -> Void = { _ in },
        blockedSince: @escaping () -> Date? = { nil },
        onDismissTrouble: @escaping () -> Void = {},
        onDownloadForOffline: (() -> Void)? = nil
    ) {
        _model = State(
            initialValue: ReaderModel(
                publication: publication,
                url: url,
                progress: progress,
                preferences: preferences
            )
        )
        self.preferences = preferences
        self.annotations = annotations
        self.blockedSince = blockedSince
        self.onDismissTrouble = onDismissTrouble
        self.onDownloadForOffline = onDownloadForOffline
        self.previousInSeries = previousInSeries
        self.nextInSeries = nextInSeries
        self.onOpen = onOpen
        let shelf = publication.series ?? publication.displayTitle
        self.shelf = shelf
        _adjustments = State(
            initialValue: preferences?.themes().theme(for: .fixedLayout, shelf: shelf).adjustments
                ?? ImageAdjustments()
        )
    }

    /// The series these adjustments belong to. `comic-reader` requires them to apply "to the
    /// series and [not be] applied globally", and a comic with no series is its own shelf.
    let shelf: String

    /// Where the per-series choices are remembered. Absent in previews.
    let preferences: ReaderPreferences?

    /// Whether the page in front of the reader is being trimmed, and a way to say no.
    private var cropsThisPage: Binding<Bool> {
        Binding(
            get: { !uncropped.contains(model.currentIndex) },
            set: { wanted in
                if wanted {
                    uncropped.remove(model.currentIndex)
                } else {
                    uncropped.insert(model.currentIndex)
                }
            }
        )
    }

    /// Keeps the adjustment against this series alone.
    private func rememberAdjustments(_ now: ImageAdjustments) {
        guard let preferences else { return }
        let memory = preferences.themes()
        let stored = memory.theme(for: .fixedLayout, shelf: shelf).settingAdjustments(now)
        preferences.save(memory.remembering(stored, for: .fixedLayout, shelf: shelf))
    }

    /// Set when the reader turns past the last page.
    @State var hasReachedEnd = false

    /// How many turns the publication has refused this session.
    ///
    /// A count rather than a flag: `native-experience` asks for the platform's haptics,
    /// and SwiftUI plays one when a trigger *changes* — so two refusals in a row have to
    /// be two different values or the second one is silent.
    @State var refusals = 0

    /// How the page is sized.
    ///
    /// Read from the shelf rather than held here: `comic-reader` requires the choice to
    /// persist per series, and the shelf is where every other per-series reader choice
    /// already lives, and `ReaderModel.choose(_ fit:)` is what writes it there.
    var fit: PageFit { model.settings.fit }

    /// Whether the thumbnail strip is open.
    @State var isBrowsingThumbnails = false

    /// Where a jump came from, so `comic-reader`'s "control to return to the previous
    /// position" has somewhere to return to.
    @State var pageReturn = PageReturn()

    /// The page the slider is scrubbing towards, while the drag is in progress.
    ///
    /// `comic-reader`: "a thumbnail of the target page follows the drag ... releasing
    /// jumps there". So the drag moves this and nothing else, and only the release moves
    /// the reader — a slider that turned every page it passed over would decode a
    /// hundred pages on the way across a comic.
    @State var scrubbing: Int?

    /// Whether the finger is on the slider.
    ///
    /// The two ways a slider is moved need different answers: a drag scrubs and only the
    /// release moves the reader, while VoiceOver's increment is a whole gesture with no
    /// drag around it and has to move the reader at once.
    @State var isScrubbing = false

    /// How the pages are grouped on screen: one per slot, and a slot may hold two.
    ///
    /// Held rather than computed, because every layout pass asks it several times — the
    /// pager, the counter, the slider and the end check — and rebuilding two hundred
    /// slots per question is work that never had to happen. ``rebuildLayout()`` is what
    /// keeps it honest, and ``layoutKey`` is what says when.
    @State var layout: SpreadLayout = .single(pageCount: 0)

    /// Whether the screen is wider than it is tall.
    ///
    /// `comic-reader` pairs facing pages only "when the device is in landscape", so this
    /// is the switch. Read from the geometry rather than from an orientation
    /// notification: a split-screen iPad is not in landscape in the way the reader means
    /// it, and the geometry is the thing the pages actually have to fit into.
    @State var isLandscape = false

    /// What to do to a page before it is shown, for this series.
    @State var adjustments = ImageAdjustments()

    /// Whether the adjustment controls are open.
    @State var isAdjusting = false

    /// Pages the reader has told the trimmer to leave alone.
    ///
    /// `comic-reader`: "the user can disable it for a page that crops wrongly". Detection on
    /// a scan is a guess, and a guess needs a way to be overruled. Held for the session
    /// rather than stored: an exemption is about one page of one book in front of the
    /// reader now, and a store of page numbers outlives the pages it describes.
    @State var uncropped: Set<Int> = []

    /// The text layer of a PDF that has one, and nothing at all otherwise.
    ///
    /// `nil` is the whole of the degradation `ebook-reader` asks for: a comic, and a PDF that
    /// is images only, never builds one, and every control that depends on text is written
    /// against its presence rather than against a flag.
    @State var pdfText: PdfTextModel?

    /// Whether the find sheet — search, marks, contents — is open.
    @State var isFindingText = false

    /// The mark a note is being written on, or nothing.
    @State var noting: Annotation?

    /// Whether the reader has been told, in one sentence, that this PDF has no text.
    ///
    /// Said only when they try. `ebook-reader` forbids a control that promises what it cannot
    /// do, so there is no search box to explain; what is left is the press that would have
    /// selected a word, and an answer to it.
    @State var saysThereIsNoText = false

    /// Whether the reader is holding the device at one way up.
    ///
    /// Held for the session rather than stored, like the exemptions above: `comic-reader`
    /// scopes the lock to "the reader only" and asks nothing about it surviving the book
    /// being closed, and a reader who has just put the phone down flat is answering about
    /// now rather than about every book they will ever open.
    @State var isOrientationLocked = false

    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Black behind every page, whatever the app's appearance. A comic
                // is read against its own artwork, not against a themed surface,
                // and a light border around a dark page is a distraction.
                // `reading-themes`: a custom background "applies to the area around the
                // page and not to the page itself". This is that area, and black is what
                // it is until a reader says otherwise.
                model.matte.ignoresSafeArea()

                if let failure = model.failure {
                    ReaderFailure(message: failure)
                } else if model.pages.isEmpty || layout.slots.isEmpty {
                    // The pager is not built until there are pages to put in it.
                    // A `TabView` with no tags resolves its selection against
                    // nothing and then lands on whatever appears first, which
                    // opened every publication on its last page. The layout is in
                    // the same guard for the same reason: it is rebuilt by an
                    // effect, so it is empty for the frame in which pages arrive.
                    DelayedProgressView()
                } else {
                    pages(in: geometry.size)
                }

                // Grouped, so overlapping glass shapes morph as one rather than
                // stacking their edges — `native-experience`'s requirement, and
                // something only the container can do.
                if isChromeVisible {
                    GlassEffectContainer(spacing: StoryArcSpace.md) { chrome }
                }

                if hasReachedEnd {
                    EndOfPublication(
                        title: model.publication.displayTitle,
                        colours: model.coverColours,
                        next: nextInSeries,
                        onOpenNext: onOpen,
                        onBack: { hasReachedEnd = false },
                        onClose: { dismiss() }
                    )
                }
            }
            // `comic-reader`: the chrome fades out again "after 4 seconds of no
            // interaction". Keyed on the index too, so turning a page while the
            // chrome is up restarts the countdown rather than hiding mid-swipe.
            // Held open while the controls are: `comic-reader` calls for a live preview,
            // and a preview whose chrome times out mid-drag hides the button that opened it.
            .sheet(isPresented: $isAdjusting) {
                AdjustmentsSheet(
                    adjustments: $adjustments,
                    shelf: shelf,
                    cropsThisPage: cropsThisPage
                )
            }
            // Written when the drag stops, not on every value: a slider produces dozens of
            // changes a second and each one would be a `UserDefaults` write.
            .onChange(of: adjustments) { _, now in
                rememberAdjustments(now)
            }
            // The geometry answers this rather than an orientation notification, and it
            // answers it for a split-screen window too.
            .onChange(of: geometry.size, initial: true) { _, size in
                isLandscape = size.width > size.height
            }
            // Regrouped when, and only when, one of its inputs moves.
            .onChange(of: layoutKey, initial: true) { _, _ in rebuildLayout() }
            .task(id: chromeTimerKey) {
                // The chrome stays up over a failure. It is the only way back to the
                // library, and hiding it four seconds after an error message left a black
                // screen that could only be escaped by force-quitting the app.
                // Not while the adjustment controls are open: they sit over the page with
                // the chrome behind them, and a reader dragging a slider has not stopped
                // interacting just because they have not touched the page.
                guard isChromeVisible, !isBrowsingThumbnails, !isAdjusting, model.failure == nil
                else { return }
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.2)) { wantsChrome = false }
            }
            .task {
                // Bounded by the screen, not by the page. A 2000×3000 scan
                // decoded in full costs 24 MB for something shown at a fraction
                // of it — `publication-formats` requires the bound.
                await model.open(
                    maxPixelSize: Int(max(geometry.size.width, geometry.size.height) * displayScale)
                )
            }
            // `comic-reader`: the prefetch window narrows "under memory pressure rather
            // than the app being terminated", and widens again when the pressure lifts.
            // For as long as the reader is on screen: leaving cancels the task, which
            // cancels the source.
            .task {
                for await pressure in MemoryPressureSource.pressures() {
                    await model.noteMemoryPressure(pressure)
                }
            }
        }
        // `comic-reader`: the mapped keys turn pages. Arrow and page keys only —
        // `native-experience`: haptics, for the two events that have nothing else to
        // announce them. Not for a page turn — a comic read at speed is two hundred of
        // those, and a buzz on each is a defect.
        .storyArcFeedback(.completion, trigger: hasReachedEnd) { $0 }
        .storyArcFeedback(.refusal, trigger: refusals)
        // The selection menu, the find sheet, and the one sentence a PDF with no text gets.
        // Empty for everything else, which is most of what this reader opens.
        .overlay { pdfTextControls }
        // Over the page rather than in place of it: `network-share` requires pages already
        // read to stay readable while the network is away.
        .overlay(alignment: .bottom) {
            NetworkNotice(
                blockedSince: blockedSince,
                onDismiss: onDismissTrouble,
                onDownload: onDownloadForOffline,
                onLeave: { dismiss() }
            )
        }
        // volume buttons are behind a setting the app does not have yet.
        .focusable()
        .onKeyPress(.leftArrow) { turn(by: -1); return .handled }
        .onKeyPress(.rightArrow) { turn(by: 1); return .handled }
        .onKeyPress(.pageUp) { turn(by: -1); return .handled }
        .onKeyPress(.pageDown) { turn(by: 1); return .handled }
        .onKeyPress(.space) { turn(by: 1); return .handled }
        // The package builds for macOS too, so the pure-Swift targets can be
        // tested on the host without a simulator. These are touch-only.
        #if os(iOS)
        .statusBarHidden(!isChromeVisible)
        .toolbar(.hidden, for: .navigationBar)
        // `comic-reader`: "the screen does not auto-lock while a page is visible,
        // and normal locking resumes on leaving". A long look at one page is
        // reading, not idling.
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            // However the reader left — the close button, the end screen, a swipe — the
            // rest of the app follows the device again, which is the other half of what
            // `comic-reader` asks of the lock.
            ReaderOrientation.release()
        }
        .onChange(of: isOrientationLocked) { _, isLocked in
            if isLocked { ReaderOrientation.hold() } else { ReaderOrientation.release() }
        }
        #endif
    }
}
