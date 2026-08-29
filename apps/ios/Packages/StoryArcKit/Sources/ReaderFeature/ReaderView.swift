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

    /// What follows this publication, and how to open it.
    ///
    /// Supplied by the app layer: the reader does not know what a library is, and a
    /// feature module never depends on another feature module.
    private let nextInSeries: Publication?
    private let onOpenNext: (Publication) -> Void

    /// Supplied by the app layer for the same reason as the above: the reader does not know
    /// what a network share is, and `network-share`'s two thresholds are the only part of
    /// that it needs.
    private let blockedSince: () -> Date?
    private let onDismissTrouble: () -> Void
    private let onDownloadForOffline: (() -> Void)?

    public init(
        publication: Publication,
        url: URL,
        progress: ProgressStore? = nil,
        preferences: ReaderPreferences? = nil,
        nextInSeries: Publication? = nil,
        onOpenNext: @escaping (Publication) -> Void = { _ in },
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
        self.blockedSince = blockedSince
        self.onDismissTrouble = onDismissTrouble
        self.onDownloadForOffline = onDownloadForOffline
        self.nextInSeries = nextInSeries
        self.onOpenNext = onOpenNext
        _fit = State(initialValue: preferences?.pageFit() ?? .screen)
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

    /// Where the fit choice is remembered. Absent in previews.
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

    /// How the page is sized. `comic-reader` requires the choice to persist.
    @State var fit: PageFit = .screen

    /// Whether the thumbnail strip is open.
    @State var isBrowsingThumbnails = false

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
                } else if model.pages.isEmpty {
                    // The pager is not built until there are pages to put in it.
                    // A `TabView` with no tags resolves its selection against
                    // nothing and then lands on whatever appears first, which
                    // opened every publication on its last page.
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
                        onOpenNext: onOpenNext,
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
        }
        // `comic-reader`: the mapped keys turn pages. Arrow and page keys only —
        // `native-experience`: haptics, for the two events that have nothing else to
        // announce them. Not for a page turn — a comic read at speed is two hundred of
        // those, and a buzz on each is a defect.
        .storyArcFeedback(.completion, trigger: hasReachedEnd) { $0 }
        .storyArcFeedback(.refusal, trigger: refusals)
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

    /// The pages themselves, in whichever container the chosen mode calls for.
    ///
    /// `page-transitions` treats the mode as a property of the container, and this is
    /// what that means here: Slide is a `TabView`, Fast fade is one page with a
    /// dissolve, and Scroll is a `ScrollView` of stitched pages. One `displayIndex`
    /// drives all three — on iOS `scrollPosition` and `TabView`'s selection speak the
    /// same language, so there is no coordinator type to write. Android needs one.
    ///
    /// Right-to-left reverses the *display* order and maps the index at the
    /// boundary, so the model keeps counting pages the way the publication does
    /// and the indicator says "2 of 4" rather than "3 of 4" for the same page.
    ///
    /// The obvious alternative — mirroring the pager with a `scaleEffect` of -1 —
    /// was tried and does not work: `TabView`'s paging gesture is computed before
    /// the transform, so a swipe pages the wrong way, jumps two at a time, and
    /// then sticks at an end. Reversing the data is the mechanism that survives
    /// contact with the gesture recogniser.
    @ViewBuilder
    private func pages(in size: CGSize) -> some View {
        let choices = model.transitions(reduceMotion: reduceMotion)
        let container = Group {
            switch choices.effective {
            case .verticalScroll: stitched(.vertical)
            case .horizontalScroll: stitched(.horizontal)
            case .fastFade: faded
            case .pageCurl: curled
            case .slide: paged
            }
        }
        container
            // One direction only: the container moves, the model follows.
            .onChange(of: displayIndex) { _, new in
                let index = modelIndex(forDisplay: new)
                guard model.pages.indices.contains(index) else { return }
                Task { await model.go(to: index) }
            }
            // And once, the other way, when the publication opens on a page that is
            // not the first — a ComicInfo cover, or a resumed position later.
            .onAppear { displayIndex = displayIndex(forModel: model.currentIndex) }
            // `comic-reader`: a direction change "applies immediately without losing the
            // current page". The run the pager lays out reverses under the reader, so the
            // position holding the page they are on moves to the other end of it. Asked
            // again here, or turning a manga around would leave them the same distance
            // from the other cover.
            //
            // Not animated, because this is not a turn: the page in front of the reader
            // does not change, only where the pager keeps it, and animating that would
            // fling across the publication to arrive back where it started.
            .onChange(of: model.readingDirection) { _, _ in
                var instant = Transaction()
                instant.disablesAnimations = true
                withTransaction(instant) {
                    displayIndex = displayIndex(forModel: model.currentIndex)
                }
            }
            .accessibilityLabel(
                isRightToLeft ? Text("reader.rightToLeft", bundle: .module) : Text(verbatim: "")
            )
    }
}
