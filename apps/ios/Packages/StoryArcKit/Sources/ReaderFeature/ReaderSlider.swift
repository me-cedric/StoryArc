public import SwiftUI

internal import DesignSystem

// The page slider, and everything `comic-reader` hangs off it.
//
// "WHEN a user drags the page slider THEN a thumbnail of the target page follows the
// drag, and the page number and total are shown AND releasing jumps there, with a
// control to return to the previous position."
//
// Three things, and the middle one is why the drag no longer moves the reader: the
// slider used to write straight through to the pager, so crossing a two-hundred-page
// comic asked the archive for two hundred pages on the way. Now the drag moves a
// scrub position, the release moves the reader, and the thumbnail is what the reader
// looks at in between.
extension ReaderView {
    /// The page the counter and the slider are talking about.
    ///
    /// The scrub target while a drag is in progress, and where the reader actually is
    /// otherwise. `comic-reader` asks for "the page number and total" beside the
    /// thumbnail, and during a drag the number a reader wants is the one they are
    /// heading for.
    var sliderIndex: Int { scrubbing ?? model.currentIndex }

    var pageCount: some View {
        pageCountLabel
            .padding(.horizontal, StoryArcSpace.md)
            .padding(.vertical, StoryArcSpace.xs)
            .storyArcGlass()
    }

    var pageCountLabel: some View {
        Text("reader.page \(sliderIndex + 1) \(model.pages.count)", bundle: .module)
            .textRole(.footnote)
            .monospacedDigit()
            .foregroundStyle(.white)
    }

    var pageSliderRow: some View {
        VStack(spacing: StoryArcSpace.xs) {
            if let scrubbing {
                ScrubThumbnail(model: model, index: scrubbing)
                    // The cross-fade alone says it arrived: `native-experience` forbids
                    // translating a panel into place under Reduce Motion.
                    .transition(.opacity)
            }

            pageCountLabel

            // Bound to the *publication's* page number, not the pager's position.
            // In right-to-left the two run opposite ways, and a slider whose left
            // end is the last page would be a puzzle.
            Slider(
                value: pageSlider,
                in: 0...Double(max(1, model.pages.count - 1)),
                step: 1,
                onEditingChanged: { editing in
                    isScrubbing = editing
                    guard !editing else { return }
                    if let target = scrubbing { jump(to: target) }
                    withAnimation(.easeInOut(duration: 0.15)) { scrubbing = nil }
                }
            )
            .tint(.white)
            // The visible count is a sibling element, so the slider owns no name
            // and no unit of its own. VoiceOver otherwise says "12, adjustable".
            .accessibilityLabel(Text("reader.page.slider", bundle: .module))
            .accessibilityValue(
                Text("reader.page \(sliderIndex + 1) \(model.pages.count)", bundle: .module)
            )

            if let mark = pageReturn.mark {
                returnButton(to: mark)
            }
        }
        .padding(.horizontal, StoryArcSpace.gutter)
        .padding(.vertical, StoryArcSpace.sm)
        .storyArcGlass(in: RoundedRectangle(cornerRadius: StoryArcRadius.lg))
    }

    /// The way back from a jump.
    ///
    /// It names the page rather than saying "Back", because by the time a reader
    /// notices they have lost their place they no longer remember what it was.
    private func returnButton(to mark: Int) -> some View {
        Button { returnFromJump() } label: {
            Label {
                Text("reader.return \(mark + 1)", bundle: .module)
                    .monospacedDigit()
            } icon: {
                Image(systemName: "arrow.uturn.backward")
            }
            .textRole(.caption)
        }
        .buttonStyle(.glass)
        .tint(.white)
    }

    /// What the slider writes to, which is not always the reader's position.
    var pageSlider: Binding<Double> {
        Binding(
            get: { Double(sliderIndex) },
            set: { new in
                let index = Int(new.rounded())
                guard model.pages.indices.contains(index) else { return }
                // VoiceOver's increment and decrement never begin an edit, so a slider
                // that only moved on release would never move at all for a reader using
                // it. They step one page, which the reader can undo by stepping back —
                // which is why `PageReturn` leaves no mark for a step of one.
                if isScrubbing {
                    scrubbing = index
                } else {
                    jump(to: index)
                }
            }
        )
    }
}

/// The page the slider is heading for, while the finger is still down.
///
/// The thumbnail the strip already has, at the size the strip already decodes: a
/// scrub across a comic asks for a page every few frames, and a full-size decode per
/// frame is how a slider ends up dropping them.
private struct ScrubThumbnail: View {
    @Environment(\.theme) private var theme

    let model: ReaderModel
    let index: Int

    @State private var image: CGImage?

    private let width: CGFloat = 72

    var body: some View {
        ZStack {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFit()
            } else {
                // No spinner: the thumbnail arrives in a frame or two from the cache
                // the strip fills, and a spinner under a moving finger is a flicker.
                theme.palette.surfaceRaised
            }
        }
        .frame(width: width, height: width * 1.5)
        .clipShape(.rect(cornerRadius: StoryArcRadius.sm))
        .overlay {
            RoundedRectangle(cornerRadius: StoryArcRadius.sm)
                .strokeBorder(theme.palette.borderSubtle, lineWidth: 1)
        }
        // The page number beside it is the accessible label for this whole row, and a
        // second announcement of the same page would only get in the way of the drag.
        .accessibilityHidden(true)
        .task(id: index) { image = await model.thumbnail(at: index) }
    }
}
