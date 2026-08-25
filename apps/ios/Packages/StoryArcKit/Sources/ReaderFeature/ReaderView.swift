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
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var model: ReaderModel
    /// `comic-reader`: nothing is on screen while the user is reading. The chrome
    /// starts visible so the way out is discoverable, and a tap hides it.
    @State private var isChromeVisible = true
    /// The pager's own position, which it owns outright.
    ///
    /// A two-way `Binding` into the model was tried twice and fights the gesture:
    /// `TabView` writes a selection during layout as well as on a swipe, and a
    /// setter that rejects some of those writes leaves the pager and the model
    /// disagreeing about where the reader is. Local state that the model *follows*
    /// has one writer and cannot desynchronise.
    @State private var displayIndex = 0

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
            initialValue: ReaderModel(publication: publication, url: url, progress: progress)
        )
        self.preferences = preferences
        self.nextInSeries = nextInSeries
        self.onOpenNext = onOpenNext
        _fit = State(initialValue: preferences?.pageFit() ?? .screen)
    }

    /// Where the fit choice is remembered. Absent in previews.
    private let preferences: ReaderPreferences?

    /// Set when the reader turns past the last page.
    @State private var hasReachedEnd = false

    /// How the page is sized. `comic-reader` requires the choice to persist.
    @State private var fit: PageFit = .screen

    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Black behind every page, whatever the app's appearance. A comic
                // is read against its own artwork, not against a themed surface,
                // and a light border around a dark page is a distraction.
                Color.black.ignoresSafeArea()

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

                if isChromeVisible { chrome }

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
                guard isChromeVisible else { return }
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

    /// The pages themselves, as a horizontal pager.
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
    private func pages(in size: CGSize) -> some View {
        TabView(selection: $displayIndex) {
            ForEach(displayOrder, id: \.self) { displayIndex in
                let index = modelIndex(forDisplay: displayIndex)
                PageView(
                    image: model.image(at: index),
                    isUnavailable: model.isUnavailable(at: index),
                    label: model.pages[index].path,
                    fit: fit,
                    onTap: { location, size in handleTap(at: location, in: size) }
                )
                .tag(displayIndex)
            }
        }
        #if os(iOS)
        .tabViewStyle(.page(indexDisplayMode: .never))
        #endif
        // One direction only: the pager moves, the model follows.
        .onChange(of: displayIndex) { _, new in
            let index = modelIndex(forDisplay: new)
            guard model.pages.indices.contains(index) else { return }
            Task { await model.go(to: index) }
        }
        // And once, the other way, when the publication opens on a page that is
        // not the first — a ComicInfo cover, or a resumed position later.
        .onAppear { displayIndex = displayIndex(forModel: model.currentIndex) }
        // Reduce Motion replaces the slide with a cross-dissolve, which
        // `comic-reader` requires rather than leaving the animation on.
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : .default, value: displayIndex)
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
    private func handleTap(at location: CGPoint, in size: CGSize) {
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

    private func turn(by step: Int) {
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
    private var displayOrder: [Int] { Array(model.pages.indices) }

    /// A display position turned back into the publication's own page number.
    ///
    /// The only place the reversal lives. Everything above and below this line
    /// counts pages the way the file does.
    private func modelIndex(forDisplay displayIndex: Int) -> Int {
        isRightToLeft ? model.pages.count - 1 - displayIndex : displayIndex
    }

    private func displayIndex(forModel index: Int) -> Int {
        isRightToLeft ? model.pages.count - 1 - index : index
    }

    private var pageSlider: Binding<Double> {
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
    private var chromeTimerKey: String { "\(isChromeVisible)-\(displayIndex)" }

    /// The controls. One gesture away, and gone while reading.
    private var chrome: some View {
        VStack {
            HStack {
                Button { dismiss() } label: {
                    Label {
                        Text("reader.close", bundle: .module)
                    } icon: {
                        Image(systemName: "xmark")
                    }
                    .labelStyle(.iconOnly)
                    .padding(StoryArcSpace.sm)
                }
                .background(.ultraThinMaterial, in: .circle)
                .tint(.white)

                Spacer()
            }
            .padding(StoryArcSpace.md)

            Spacer()

            VStack(spacing: StoryArcSpace.sm) {
                // A segmented control rather than a menu. Four options fit across a
                // phone, and a control with no open state cannot be swallowed by
                // the chrome auto-hiding under it.
                Picker("", selection: fitBinding) {
                    ForEach(PageFit.allCases, id: \.self) { candidate in
                        Text(candidate.shortTitleKey, bundle: .module).tag(candidate)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if model.pages.count > 1 {
                    pageSliderRow
                } else if !model.pages.isEmpty {
                    pageCount
                }
            }
            .padding(.horizontal, StoryArcSpace.md)
            .padding(.bottom, StoryArcSpace.lg)
        }
        .transition(.opacity)
    }

    private var fitBinding: Binding<PageFit> {
        Binding(
            get: { fit },
            set: { new in
                fit = new
                preferences?.save(new)
            }
        )
    }

    private var pageCount: some View {
        pageCountLabel
            .padding(.horizontal, StoryArcSpace.md)
            .padding(.vertical, StoryArcSpace.xs)
            .background(.ultraThinMaterial, in: .capsule)
    }

    private var pageCountLabel: some View {
        Text("reader.page \(model.currentIndex + 1) \(model.pages.count)", bundle: .module)
            .textRole(.footnote)
            .monospacedDigit()
            .foregroundStyle(.white)
    }

    private var pageSliderRow: some View {
        VStack(spacing: StoryArcSpace.xs) {
            pageCountLabel

            // Bound to the *publication's* page number, not the pager's position.
            // In right-to-left the two run opposite ways, and a slider whose left
            // end is the last page would be a puzzle. Thumbnails on the slider are
            // the rest of what `comic-reader` asks for and are not here yet.
            Slider(value: pageSlider, in: 0...Double(max(1, model.pages.count - 1)), step: 1)
                .tint(.white)
        }
        .padding(.horizontal, StoryArcSpace.gutter)
        .padding(.vertical, StoryArcSpace.sm)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: StoryArcRadius.lg))
    }
}
