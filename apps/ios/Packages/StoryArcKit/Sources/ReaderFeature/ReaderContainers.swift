internal import SwiftUI

internal import DesignSystem
internal import StoryArcCore

// One container per transition mode, over one page body.
//
// `page-transitions` treats the mode as a property of the container, and this file is
// what that means here. Split out of `ReaderView` so that file stays the screen and
// its chrome, rather than the screen plus three layouts.
//
// The members are internal rather than private because `ReaderView.body` is in the
// other file, and a `private` member of an extension cannot be reached from it.
extension ReaderView {
    /// Slide: the platform's own pager, which brings its gesture and edge resistance.
    var paged: some View {
        TabView(selection: $displayIndex) {
            ForEach(displayOrder, id: \.self) { displayIndex in
                page(at: displayIndex)
                    .tag(displayIndex)
            }
        }
        #if os(iOS)
        .tabViewStyle(.page(indexDisplayMode: .never))
        #endif
        .animation(.default, value: displayIndex)
    }

    /// Fast fade: no container, and no translation. Taps, keys and the slider turn.
    ///
    /// `.id` is what makes the dissolve happen: without it SwiftUI reuses the view and
    /// swaps the image inside, which is a cut rather than a fade.
    var faded: some View {
        page(at: displayIndex)
            .id(displayIndex)
            .transition(.opacity)
            .animation(.easeInOut(duration: Self.fadeDuration), value: displayIndex)
    }

    /// Scroll: continuous, with pages meeting edge to edge.
    ///
    /// `comic-reader` asks for them "stitched with no gap by default", so the stack
    /// has no spacing and each page takes the size its own proportions ask for along
    /// the scroll axis.
    @ViewBuilder
    func stitched(_ axis: ScrollAxis) -> some View {
        ScrollView(axis == .vertical ? .vertical : .horizontal) {
            let content = ForEach(displayOrder, id: \.self) { displayIndex in
                stitchedPage(at: displayIndex, along: axis)
                    .id(displayIndex)
            }
            if axis == .vertical {
                LazyVStack(spacing: 0) { content }
            } else {
                LazyHStack(spacing: 0) { content }
            }
        }
        .scrollTargetLayout()
        .scrollPosition(id: scrollPosition)
        .ignoresSafeArea()
    }

    /// The scroll's position, as the same `displayIndex` every other mode uses.
    ///
    /// A scroll reports `nil` mid-flight; keeping the last index rather than writing
    /// the nil through is what stops the page counter blinking during a drag.
    var scrollPosition: Binding<Int?> {
        Binding(
            get: { displayIndex },
            set: { if let new = $0 { displayIndex = new } }
        )
    }

    func page(at displayIndex: Int) -> some View {
        let index = modelIndex(forDisplay: displayIndex)
        return PageView(
            image: model.image(at: index),
            isUnavailable: model.isUnavailable(at: index),
            label: model.pages[index].path,
            fit: fit,
            onTap: { location, size in handleTap(at: location, in: size) }
        )
    }

    /// One page in a continuous scroll: full across, natural along.
    ///
    /// Zoom is off here, because the scroll owns the drag — two things claiming it is
    /// how a reader ends up able to do neither.
    func stitchedPage(at displayIndex: Int, along axis: ScrollAxis) -> some View {
        let index = modelIndex(forDisplay: displayIndex)
        return StitchedPage(
            image: model.image(at: index),
            isUnavailable: model.isUnavailable(at: index),
            label: model.pages[index].path,
            axis: axis,
            onTap: { location, size in handleTap(at: location, in: size) }
        )
    }

    /// Short enough not to read as an animation, which is the point of the name.
    ///
    /// `page-transitions` uses Fast fade as the Reduce Motion substitute as well as a
    /// mode in its own right, so it must not become the thing it replaces.
    static let fadeDuration = 0.14
}
