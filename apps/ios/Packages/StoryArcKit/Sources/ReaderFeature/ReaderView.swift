public import SwiftUI

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

    public init(publication: Publication, url: URL, progress: ProgressStore? = nil) {
        _model = State(
            initialValue: ReaderModel(publication: publication, url: url, progress: progress)
        )
    }

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
                    ProgressView().tint(.white)
                } else {
                    pages(in: geometry.size)
                }

                if isChromeVisible { chrome }
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
        // The package builds for macOS too, so the pure-Swift targets can be
        // tested on the host without a simulator. These three are touch-only.
        #if os(iOS)
        .statusBarHidden(!isChromeVisible)
        .toolbar(.hidden, for: .navigationBar)
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
                    label: model.pages[index].path
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
        .contentShape(.rect)
        .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { isChromeVisible.toggle() } }
        .accessibilityLabel(
            isRightToLeft ? Text("reader.rightToLeft", bundle: .module) : Text(verbatim: "")
        )
    }

    private var isRightToLeft: Bool { model.readingDirection == .rightToLeft }

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

            if !model.pages.isEmpty {
                Text(
                    "reader.page \(model.currentIndex + 1) \(model.pages.count)",
                    bundle: .module
                )
                .textRole(.footnote)
                .monospacedDigit()
                .foregroundStyle(.white)
                .padding(.horizontal, StoryArcSpace.md)
                .padding(.vertical, StoryArcSpace.xs)
                .background(.ultraThinMaterial, in: .capsule)
                .padding(.bottom, StoryArcSpace.lg)
            }
        }
        .transition(.opacity)
    }
}

/// One page, fitted.
struct PageView: View {
    let image: CGImage?
    let isUnavailable: Bool
    let label: String

    var body: some View {
        if let image {
            Image(decorative: image, scale: 1)
                .resizable()
                // Fit, not fill: cropping a comic page loses artwork, and
                // `comic-reader` treats the whole page as the unit.
                .scaledToFit()
                .accessibilityLabel(label)
        } else if isUnavailable {
            // Said, not blank. `publication-formats` requires an archive to report
            // what it skipped, and this is where a skipped page is met.
            VStack(spacing: StoryArcSpace.sm) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 28, weight: .light))
                Text("reader.pageUnavailable", bundle: .module)
                    .textRole(.footnote)
            }
            .foregroundStyle(.white.opacity(0.7))
        } else {
            ProgressView().tint(.white)
        }
    }
}

struct ReaderFailure: View {
    let message: String

    var body: some View {
        VStack(spacing: StoryArcSpace.sm) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32, weight: .light))
            Text(message)
                .textRole(.footnote)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.white.opacity(0.8))
        .padding(StoryArcSpace.gutter)
    }
}
