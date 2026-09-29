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
    /// What the page turned out to be, when it could not be decoded. See ``PageProblem``.
    let codecName: String?
    /// The archive entry, used to tell one page from the next so zoom resets on a turn.
    let pageID: String
    /// What VoiceOver says. Separate from `pageID` because the two were the same value
    /// and only one of them should have been a path: VoiceOver read "page10.png" aloud,
    /// which names a file inside a CBZ rather than a page.
    let label: Text
    let fit: PageFit
    /// D6: what the reader pinched to on the last page, offered to this one.
    var carriedZoomScale: Double?
    var isRightToLeft = false
    let adjustments: ImageAdjustments
    let onTap: (CGPoint, CGSize) -> Void
    /// How far the reader has magnified the page, reported when a pinch settles.
    ///
    /// `publication-formats` asks for a page to be "re-decoded at higher resolution
    /// when the user zooms", and the scroll view is the only thing that knows how far.
    let onZoom: (_ scale: Double, _ overFit: Double) -> Void

    /// The marks and the live selection over a PDF page. Empty for everything else.
    var decoration: PdfPageDecoration = .none
    /// How a press-and-drag over the page is answered, or `nil` where there is no text.
    var onSelect: ((CGPoint, CGPoint, Bool) -> Void)?

    var body: some View {
        if let image {
            // Fit, not fill: cropping a comic page loses artwork, and
            // `comic-reader` treats the whole page as the unit. Zoom starts from
            // that fit rather than replacing it.
            ZoomablePage(
                image: sharpened(cropped(image, when: adjustments.cropsBorders), by: adjustments.sharpness),
                pageID: pageID,
                fit: fit,
                carriedZoomScale: carriedZoomScale,
                isRightToLeft: isRightToLeft,
                onTap: onTap,
                onZoom: onZoom,
                decoration: decoration,
                onSelect: onSelect
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
                        PageProblem(codecName: codecName)
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
    /// What the page turned out to be, when it could not be decoded. See ``PageProblem``.
    let codecName: String?
    /// What VoiceOver says. See ``PageView/label`` for why this is not the entry path.
    let label: Text
    let axis: ScrollAxis
    let adjustments: ImageAdjustments
    let onTap: (CGPoint, CGSize) -> Void

    /// This page's shape before it is decoded: the nearest decoded page's own ratio, or
    /// the ordinary comic-page default. See ``PagePlaceholder``.
    var placeholderRatio = PagePlaceholder.defaultRatio

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
                    PageProblem(codecName: codecName)
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
        guard let image, image.height > 0 else { return placeholderRatio }
        return Double(image.width) / Double(image.height)
    }
}

/// The break between two pages in a continuous scroll.
///
/// `comic-reader`: pages are "stitched with no gap by default, with an option to show a
/// separator". A band of the matte with a hairline through it, rather than a hairline on
/// its own: a black line between two black-bordered pages is invisible and so is a white
/// one between two white ones, and the matte is the colour the reader has already said
/// belongs between the artwork and the screen.
struct PageSeparator: View {
    @Environment(\.theme) private var theme

    let axis: ScrollAxis
    /// What shows around the page, which is what shows between two of them.
    let matte: Color

    /// Enough to read as a deliberate break at arm's length, and not so much that a
    /// webtoon stops reading as one strip.
    private static let band: CGFloat = 10

    var body: some View {
        ZStack {
            matte
            Rectangle()
                .fill(theme.palette.borderSubtle)
                .frame(
                    width: axis == .vertical ? nil : 1,
                    height: axis == .vertical ? 1 : nil
                )
        }
        .frame(
            width: axis == .vertical ? nil : Self.band,
            height: axis == .vertical ? Self.band : nil
        )
        // Decoration, and named as such: VoiceOver reads the pages either side of it and
        // has no use for the gap between them.
        .accessibilityHidden(true)
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
///
/// `publication-formats`: an undecodable page "displays a placeholder naming the codec,
/// and does not break pagination". Naming it is what lets a reader tell the two cases
/// apart: one page saying JPEG among ninety-nine that drew is a damaged entry in the
/// file, and every page saying JPEG XL is a format this device has no decoder for. With
/// no name the two look identical, and the only thing a reader could conclude was that
/// the app was broken.
///
/// The name is absent when nothing could be read at all, and then the shorter sentence
/// is the honest one.
struct PageProblem: View {
    let codecName: String?

    var body: some View {
        VStack(spacing: StoryArcSpace.sm) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28, weight: .light))
            if let codecName {
                Text("reader.pageUnavailable.codec \(codecName)", bundle: .module)
                    .textRole(.footnote)
                    .multilineTextAlignment(.center)
            } else {
                Text("reader.pageUnavailable", bundle: .module)
                    .textRole(.footnote)
            }
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

extension ReadingDirection {
    /// Which way the pages run, named the way a reader would say it.
    ///
    /// Right-to-left reuses the sentence VoiceOver already reads out on entering a
    /// manga, because it is the same fact and a second wording of it would be one to
    /// keep in step for nothing.
    var titleKey: LocalizedStringKey {
        switch self {
        case .leftToRight: "reader.leftToRight"
        case .rightToLeft: "reader.rightToLeft"
        }
    }
}
