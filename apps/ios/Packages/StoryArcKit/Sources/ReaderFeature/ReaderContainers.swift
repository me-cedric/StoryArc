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
    /// Curl: a shader over the two decoded pages, driven by the finger.
    ///
    /// `comic-reader` is explicit that a curl over a comic "uses the already-decoded
    /// page directly rather than a re-raster", which is why this takes `CGImage`s and
    /// not a snapshot of the view.
    var curled: some View {
        CurledPages(
            page: model.image(at: modelIndex(forDisplay: displayIndex)),
            // The page underneath is the next *display* position, not the next page
            // number: in right-to-left the two run opposite ways, and a curl that
            // revealed the wrong side would be worse than no curl.
            beneath: model.image(at: modelIndex(forDisplay: displayIndex + 1)),
            isRightToLeft: model.readingDirection == .rightToLeft,
            matte: model.matte,
            onTurned: { turn(by: 1) },
            onTap: { location, size in handleTap(at: location, in: size) }
        )
    }

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
                // `comic-reader` asks for the separator between pages, so the first page
                // does not get one — a band above page one is a margin, not a separator.
                if model.settings.showsPageSeparator, displayIndex > 0 {
                    PageSeparator(axis: axis, matte: model.matte)
                }
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

    /// One slot: a page, or two facing pages.
    ///
    /// `comic-reader`: a pair is shown "side by side in the correct order for the
    /// reading direction". Reading order is the publication's own either way — a manga
    /// spread reads 4 then 5 exactly as a western one does — so only the screen order
    /// flips, and it flips here rather than anywhere the pages are counted.
    @ViewBuilder
    func page(at displayIndex: Int) -> some View {
        let spread = layout[slotIndex(forDisplay: displayIndex)]
        if let spread, let trailing = spread.trailing {
            let onScreen = isRightToLeft ? [trailing, spread.leading] : [spread.leading, trailing]
            HStack(spacing: 0) {
                ForEach(Array(onScreen.enumerated()), id: \.offset) { position, index in
                    half(at: index, isFirstOnScreen: position == 0)
                }
            }
        } else {
            singlePage(at: spread?.leading ?? 0) { location, size in
                handleTap(at: location, in: size)
            }
        }
    }

    /// One half of a spread, with its taps put back into screen terms.
    ///
    /// The halves are equal, so a tap in one is a tap in the same place on a screen twice
    /// as wide. Without this the edge zones would be measured against half the screen and
    /// the middle of a spread would turn the page.
    private func half(at index: Int, isFirstOnScreen: Bool) -> some View {
        singlePage(at: index) { location, size in
            handleTap(
                at: CGPoint(x: isFirstOnScreen ? location.x : location.x + size.width, y: location.y),
                in: CGSize(width: size.width * 2, height: size.height)
            )
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func singlePage(at index: Int, onTap: @escaping (CGPoint, CGSize) -> Void) -> some View {
        if model.pages.indices.contains(index) {
            PageView(
                image: model.image(at: index),
                isUnavailable: model.isUnavailable(at: index),
                pageID: model.pages[index].path,
                label: Text("reader.pageLabel \(index + 1) \(model.pages.count)", bundle: .module),
                fit: fit,
                adjustments: trimming(at: index),
                onTap: onTap
            )
        } else {
            // A slot that outlived its pages, for the frame between a publication
            // closing and the layout being rebuilt. Black, like everything behind a page.
            Color.black
        }
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
            label: Text("reader.pageLabel \(index + 1) \(model.pages.count)", bundle: .module),
            axis: axis,
            adjustments: trimming(at: index),
            onTap: { location, size in handleTap(at: location, in: size) }
        )
    }

    /// The series' adjustments, with the trim off for a page the reader excused.
    func trimming(at index: Int) -> ImageAdjustments {
        guard uncropped.contains(index) else { return adjustments }
        var excused = adjustments
        excused.cropsBorders = false
        return excused
    }

    /// Short enough not to read as an animation, which is the point of the name.
    ///
    /// `page-transitions` uses Fast fade as the Reduce Motion substitute as well as a
    /// mode in its own right, so it must not become the thing it replaces.
    static let fadeDuration = 0.14
}
