public import SwiftUI

internal import DesignSystem
public import StoryArcCore

// What the reader draws inside the pager, and what it draws after it: one page,
// a named failure, a spinner that waits, and the end screen. Split out of
// `ReaderView` so the screen itself is the pager, the chrome and the gestures —
// which is already enough for one file.

/// One page, fitted.
struct PageView: View {
    let image: CGImage?
    let isUnavailable: Bool
    /// The archive entry, used to tell one page from the next so zoom resets on a turn.
    let pageID: String
    /// What VoiceOver says. Separate from `pageID` because the two were the same value
    /// and only one of them should have been a path: VoiceOver read "page10.png" aloud,
    /// which names a file inside a CBZ rather than a page.
    let label: Text
    let fit: PageFit
    let adjustments: ImageAdjustments
    let onTap: (CGPoint, CGSize) -> Void

    var body: some View {
        if let image {
            // Fit, not fill: cropping a comic page loses artwork, and
            // `comic-reader` treats the whole page as the unit. Zoom starts from
            // that fit rather than replacing it.
            ZoomablePage(
                image: sharpened(cropped(image, when: adjustments.cropsBorders), by: adjustments.sharpness),
                pageID: pageID,
                fit: fit,
                onTap: onTap
            )
            .adjusted(adjustments)
            .accessibilityLabel(label)
        } else {
            // A page that is not drawn still has to accept a tap: a reader who
            // lands on a skipped page must be able to turn away from it, and one
            // waiting on a decode must be able to reach the chrome.
            GeometryReader { geometry in
                ZStack {
                    Color.black
                    if isUnavailable {
                        // Said, not blank. `publication-formats` requires an
                        // archive to report what it skipped, and this is where a
                        // skipped page is met.
                        VStack(spacing: StoryArcSpace.sm) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 28, weight: .light))
                            Text("reader.pageUnavailable", bundle: .module)
                                .textRole(.footnote)
                        }
                        .foregroundStyle(.white.opacity(0.7))
                    } else {
                        DelayedProgressView()
                    }
                }
                .contentShape(.rect)
                .onTapGesture { location in onTap(location, geometry.size) }
            }
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

/// A spinner that waits before it appears.
///
/// `comic-reader`: "a progress indicator appears only after 400 ms". A page that
/// decodes in 30 ms should not flash a spinner on its way — the flash reads as a
/// stutter, which is the opposite of what the indicator is for.
struct DelayedProgressView: View {
    @State private var isVisible = false

    var body: some View {
        Group {
            if isVisible { ProgressView().tint(.white) }
        }
        .task {
            try? await Task.sleep(for: .milliseconds(400))
            isVisible = true
        }
    }
}

/// What the reader shows after the last page.
///
/// `comic-reader`: "an end screen offers the next publication in the series or
/// reading list, marks this one finished". Marking is already done — the last page
/// records `isFinished` as it is turned to, because a reader who closes the app on
/// the last page has still finished it.
///
/// Deleting the download is offered by the same scenario and is not here: there
/// are no downloads yet, and a button that deletes nothing is worse than none.
struct EndOfPublication: View {
    @Environment(\.theme) private var theme

    let title: String
    let next: Publication?
    let onOpenNext: (Publication) -> Void
    let onBack: () -> Void
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.92).ignoresSafeArea()

            VStack(spacing: StoryArcSpace.lg) {
                VStack(spacing: StoryArcSpace.xs) {
                    Text("reader.end.finished", bundle: .module)
                        .textRole(.title3)
                        .foregroundStyle(.white)
                    Text(title)
                        .textRole(.footnote)
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                }

                if let next {
                    Button {
                        onOpenNext(next)
                    } label: {
                        Text("reader.end.next \(next.displayTitle)", bundle: .module)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, StoryArcSpace.xs)
                    }
                    .buttonStyle(.borderedProminent)
                }

                HStack(spacing: StoryArcSpace.md) {
                    Button(action: onBack) {
                        Text("reader.end.back", bundle: .module)
                    }
                    Button(action: onClose) {
                        Text("reader.end.library", bundle: .module)
                    }
                }
                .buttonStyle(.bordered)
                .tint(.white)
            }
            .padding(.horizontal, StoryArcSpace.gutter)
            .frame(maxWidth: StoryArcSpace.huge * 6)
        }
        .transition(.opacity)
    }
}

/// One page in a continuous scroll.
///
/// Full across the cross axis and natural along the scroll axis, so consecutive pages
/// meet with no gap — `comic-reader` asks for them "stitched with no gap by default".
/// Fitting each one to the screen instead would leave a band of black between every
/// pair, and stitching along the wrong axis leaves a row of slivers.
///
/// Deliberately not ``ZoomablePage``: the scroll owns the drag, and two things
/// claiming it is how a reader ends up able to do neither.
struct StitchedPage: View {
    let image: CGImage?
    let isUnavailable: Bool
    /// What VoiceOver says. See ``PageView/label`` for why this is not the entry path.
    let label: Text
    let axis: ScrollAxis
    let adjustments: ImageAdjustments
    let onTap: (CGPoint, CGSize) -> Void

    /// A page's shape before it is decoded.
    ///
    /// `page-transitions` asks a turn to run "against a placeholder holding the
    /// correct aspect ratio, so the turn does not jump when the content arrives".
    /// Until the page is decoded its real ratio is unknown, and a comic page is close
    /// enough to this that the jump is not something a reader notices.
    private static let placeholderRatio = 2.0 / 3.0

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                if let image {
                    Image(
                        decorative: sharpened(
                            cropped(image, when: adjustments.cropsBorders),
                            by: adjustments.sharpness
                        ),
                        scale: 1
                    )
                        .resizable()
                        .scaledToFit()
                        .adjusted(adjustments)
                        .accessibilityLabel(label)
                } else if isUnavailable {
                    // Said, not blank. `publication-formats` requires an archive to
                    // report what it skipped, and this is where a skipped page is met.
                    PageProblem()
                } else {
                    DelayedProgressView()
                }
            }
            .contentShape(.rect)
            .onTapGesture { location in onTap(location, geometry.size) }
        }
        .aspectRatio(ratio, contentMode: .fit)
        .modifier(FullAcross(axis: axis))
    }

    /// The page's own proportions, or the placeholder's until it has any.
    private var ratio: Double {
        guard let image, image.height > 0 else { return Self.placeholderRatio }
        return Double(image.width) / Double(image.height)
    }
}

/// Fills the axis a scroll does *not* run along.
private struct FullAcross: ViewModifier {
    let axis: ScrollAxis

    @ViewBuilder
    func body(content: Content) -> some View {
        switch axis {
        case .vertical: content.frame(maxWidth: .infinity)
        case .horizontal: content.frame(maxHeight: .infinity)
        }
    }
}

/// A page the archive could not give us, said rather than left blank.
private struct PageProblem: View {
    var body: some View {
        VStack(spacing: StoryArcSpace.sm) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28, weight: .light))
            Text("reader.pageUnavailable", bundle: .module)
                .textRole(.footnote)
        }
        .foregroundStyle(.white.opacity(0.7))
    }
}

extension PageTransition {
    /// How the transition modes are named on screen.
    ///
    /// In the feature rather than the domain: `:core:model`'s twin carries no
    /// resources either, because the domain has no business holding UI copy.
    var titleKey: LocalizedStringKey {
        switch self {
        case .pageCurl: "reader.transition.curl"
        case .slide: "reader.transition.slide"
        case .fastFade: "reader.transition.fade"
        case .verticalScroll: "reader.transition.scrollVertical"
        case .horizontalScroll: "reader.transition.scrollHorizontal"
        }
    }
}

extension TransitionUnavailability {
    /// Why a mode cannot run, in one line.
    var titleKey: LocalizedStringKey {
        switch self {
        case .reduceMotion: "reader.transition.reduceMotion"
        case .reflowableText: "reader.transition.reflowable"
        }
    }
}
