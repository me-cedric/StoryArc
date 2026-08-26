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
    @State var isChromeVisible = true
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

    public init(
        publication: Publication,
        url: URL,
        progress: ProgressStore? = nil,
        preferences: ReaderPreferences? = nil,
        nextInSeries: Publication? = nil,
        onOpenNext: @escaping (Publication) -> Void = { _ in }
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
        self.nextInSeries = nextInSeries
        self.onOpenNext = onOpenNext
        _fit = State(initialValue: preferences?.pageFit() ?? .screen)
    }

    /// Where the fit choice is remembered. Absent in previews.
    let preferences: ReaderPreferences?

    /// Set when the reader turns past the last page.
    @State private var hasReachedEnd = false

    /// How the page is sized. `comic-reader` requires the choice to persist.
    @State var fit: PageFit = .screen

    /// Whether the thumbnail strip is open.
    @State var isBrowsingThumbnails = false

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
            .task(id: chromeTimerKey) {
                guard isChromeVisible, !isBrowsingThumbnails else { return }
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.2)) { isChromeVisible = false }
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
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
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
            .accessibilityLabel(
                isRightToLeft ? Text("reader.rightToLeft", bundle: .module) : Text(verbatim: "")
            )
    }

    private var isRightToLeft: Bool { model.readingDirection == .rightToLeft }

    /// What a tap means, by where it landed.
    ///
    /// `comic-reader`: the edges turn pages and do not reveal the chrome, the
    /// centre toggles it. The zones are "mirrored in right-to-left mode" for free
    /// here — the pager's *data* is reversed for RTL, so moving one step to the
    /// right on screen is always one step to the right on screen, whichever way
    /// the story runs.
    func handleTap(at location: CGPoint, in size: CGSize) {
        let edge = size.width * edgeZoneFraction
        if location.x < edge {
            turn(by: -1)
        } else if location.x > size.width - edge {
            turn(by: 1)
        } else {
            withAnimation(.easeInOut(duration: 0.2)) { isChromeVisible.toggle() }
        }
    }

    /// The same zones the page's own recognisers use to route a tap.
    private var edgeZoneFraction: CGFloat { ZoomablePage.edgeZoneFraction }

    func turn(by step: Int) {
        let next = displayIndex + step
        // `comic-reader`: turning past the last page reaches an end screen rather
        // than nothing. In right-to-left the last *page* is the first display
        // position, which is why this asks the model rather than the pager.
        if !model.pages.indices.contains(next), model.currentIndex == model.pages.count - 1 {
            withAnimation(.easeInOut(duration: 0.2)) { hasReachedEnd = true }
            return
        }
        guard model.pages.indices.contains(next) else { return }
        withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : .default) {
            displayIndex = next
        }
    }

    /// Display positions, in the order the pager lays them out.
    var displayOrder: [Int] { Array(model.pages.indices) }

    /// A display position turned back into the publication's own page number.
    ///
    /// The only place the reversal lives. Everything above and below this line
    /// counts pages the way the file does.
    func modelIndex(forDisplay displayIndex: Int) -> Int {
        isRightToLeft ? model.pages.count - 1 - displayIndex : displayIndex
    }

    func displayIndex(forModel index: Int) -> Int {
        isRightToLeft ? model.pages.count - 1 - index : index
    }

    var pageSlider: Binding<Double> {
        Binding(
            get: { Double(model.currentIndex) },
            set: { new in
                let index = Int(new.rounded())
                guard model.pages.indices.contains(index) else { return }
                displayIndex = displayIndex(forModel: index)
            }
        )
    }

    /// Restarts the auto-hide countdown whenever either of these changes.
    private var chromeTimerKey: String {
        // The strip counts as interaction: reading a row of thumbnails takes longer
        // than four seconds, and the chrome vanishing underneath would take the
        // strip with it.
        "\(isChromeVisible)-\(displayIndex)-\(isBrowsingThumbnails)"
    }

}
