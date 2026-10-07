internal import SwiftUI

internal import DesignSystem
internal import StoryArcCore

/// Each visible page's own frame in `ReaderContainers.scrollSpace`, and the viewport
/// they are in, for ``ScrollProgress``.
private struct ScrollFrames: Equatable {
    var pages: [Int: CGRect] = [:]
    var viewport: CGSize = .zero
}

private struct PageFramePreferenceKey: PreferenceKey {
    static var defaultValue: ScrollFrames { ScrollFrames() }
    static func reduce(value: inout ScrollFrames, nextValue: () -> ScrollFrames) {
        let next = nextValue()
        value.pages.merge(next.pages) { _, new in new }
        if next.viewport != .zero { value.viewport = next.viewport }
    }
}

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
    ///
    /// **`beneath` and `previous` are one reading-order step apart, not one *display*
    /// index apart.** Right-to-left reverses the display order (`ReaderNavigation`), so
    /// display position `displayIndex + 1` is the *previous* page in reading order there,
    /// not the next one. `CurlTurn.forward` already mirrors the gesture and the shader
    /// already mirrors the crease for right-to-left; handing it `displayIndex + 1` as the
    /// forward reveal on top of that mirrored the gesture twice, so a drag that lifted the
    /// page the reader expects opened the page behind them instead.
    ///
    /// **At rest the curl is the normal page body** (D33): `page(at:)`, with its fit, its
    /// pinch and its PDF marks, and its taps routed as the page routes them. The shader
    /// stands over it only while a turn runs.
    var curled: some View {
        let next = adjacentDisplayIndex(
            from: displayIndex, steps: 1, slotCount: layout.count, isRightToLeft: isRightToLeft
        )
        let behind = adjacentDisplayIndex(
            from: displayIndex, steps: -1, slotCount: layout.count, isRightToLeft: isRightToLeft
        )
        return CurledPages(
            // One page, or a spread composited into one texture. See `ReaderCurlSheets`.
            page: curlTexture(forDisplay: displayIndex),
            beneath: curlSheet(at: next),
            // The page behind, for the other direction. The reader met a curl that "only
            // seems to work in one direction": the shader had nothing to turn backwards
            // because nothing was handed to it.
            previous: curlSheet(at: behind),
            isRightToLeft: isRightToLeft,
            matte: model.matte,
            adjustments: adjustments,
            isUnavailable: model.isUnavailable(at: modelIndex(forDisplay: displayIndex)),
            codecName: model.codecName(at: modelIndex(forDisplay: displayIndex)),
            // D10: past the last page the end screen is the next sheet.
            endsHere: next == nil,
            isSpread: layout[slotIndex(forDisplay: displayIndex)]?.trailing != nil,
            beneathOpens: curlOpening(forDisplay: next),
            previousOpens: curlOpening(forDisplay: behind),
            content: page(at: displayIndex),
            underneath: endOfPublication,
            // `turn(by:)` and not `turnInReadingOrder(by:)`: the curl has already rolled
            // the page over by the time these are called, and the reading-order route
            // files a fresh ``CurlRequest``, which would roll it over again.
            onTurned: { turn(by: readingOrderStep(1, isRightToLeft: isRightToLeft)) },
            onTurnedBack: { turn(by: readingOrderStep(-1, isRightToLeft: isRightToLeft)) },
            request: $curlRequest
        )
    }

    /// Slide: the platform's own pager, which brings its gesture and edge resistance.
    var paged: some View {
        TabView(selection: $displayIndex) {
            // `comic-reader`: "a swipe past the last page reaches the end screen".
            // Without a tagged view past the last page, `TabView` has nowhere to swipe
            // to and the gesture simply stops at the last page. `hasReachedEnd` covers
            // this slot the instant it becomes current (`pages(in:)`), so nothing here
            // is ever actually seen. Before the run under right-to-left: see `endSlot`.
            withEndSlot(
                ForEach(displayOrder, id: \.self) { displayIndex in
                    page(at: displayIndex)
                        .tag(displayIndex)
                },
                Color.clear.tag(endSlot)
            )
        }
        #if os(iOS)
        .tabViewStyle(.page(indexDisplayMode: .never))
        #endif
        .animation(.default, value: displayIndex)
        // The pager animates a turn and reports no end, so the index bounds the count.
        //
        // A swipe and a tap are counted differently here, and the difference is the pager's:
        // `TabView` moves the selection when the swipe settles, so a swiped turn counts the
        // frames that follow it. A tap, a key, the slider and the thumbnail strip all move
        // the index first, and those turns are counted while they run.
        .probingTurns(displayIndex, of: .slide)
    }

    /// Fast fade: no container, and no translation. Taps, swipes, keys and the slider turn.
    ///
    /// `.id` is what makes the dissolve happen: without it SwiftUI reuses the view and
    /// swaps the image inside, which is a cut rather than a fade.
    var faded: some View {
        page(at: displayIndex)
            .id(displayIndex)
            .transition(.opacity)
            .animation(.easeInOut(duration: Self.fadeDuration), value: displayIndex)
            // Nothing turns a page here but the index, so the index bounds the count.
            .probingTurns(displayIndex, of: .fastFade)
            // Task 8.2: with no container there is no swipe, so the page brings one.
            .environment(\.swipeTurn, SwipeTurn { turn(by: $0) })
    }

    /// Scroll: continuous, with pages meeting edge to edge.
    ///
    /// `comic-reader` asks for them "stitched with no gap by default", so the stack
    /// has no spacing and each page takes the size its own proportions ask for along
    /// the scroll axis.
    ///
    /// **No frame run is opened here, and the reason is the mode.** A scroll has no discrete
    /// turn: the index moves on every frame of a drag, so each move would open a run the
    /// next move closes, and the numbers would describe the finger rather than a transition.
    /// `PageTransition.turnWindow` states the same rule where it can be tested.
    @ViewBuilder
    func stitched(_ axis: ScrollAxis) -> some View {
        ScrollViewReader { proxy in
            ScrollView(axis == .vertical ? .vertical : .horizontal) {
                let content = ForEach(displayOrder, id: \.self) { displayIndex in
                    // `comic-reader` asks for the separator between pages, so the first
                    // page does not get one — a band above page one is a margin, not a
                    // separator.
                    if model.settings.showsSeparator(above: displayIndex) {
                        PageSeparator(axis: axis, matte: model.matte)
                    }
                    stitchedPage(at: displayIndex, along: axis)
                        .id(displayIndex)
                        // `comic-reader`: the scroll position is "preserved exactly", which
                        // a page *index* alone cannot do for a page many screens tall. This
                        // reports each page's own frame in the scroll's coordinate space, so
                        // ``ScrollProgress`` can turn it into a fraction through whichever
                        // page is current. See `saveScrollProgress` below.
                        .background(frameReport(of: displayIndex))
                }
                // `comic-reader`: "a scroll past the last page reaches the end screen". A
                // continuous scroll has no natural end the way a discrete turn does — the
                // stack simply stops — so this gives it one more, page-sized slot to reach.
                // `containerRelativeFrame` sizes it to the viewport, same as a real page
                // fills it, so reaching it reads as "one more screen", not a sliver.
                let end = Color.clear
                    .containerRelativeFrame(axis == .vertical ? .vertical : .horizontal)
                    .id(endSlot)
                if axis == .vertical {
                    LazyVStack(spacing: 0) { withEndSlot(content, end) }
                } else {
                    LazyHStack(spacing: 0) { withEndSlot(content, end) }
                }
            }
            .scrollTargetLayout()
            .scrollPosition(id: scrollPosition)
            .ignoresSafeArea()
            .coordinateSpace(name: Self.scrollSpace)
            .background(
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: PageFramePreferenceKey.self, value: ScrollFrames(viewport: geometry.size)
                    )
                }
            )
            // ponytail: unthrottled — every geometry change writes. `UserDefaults` coalesces
            // its own writeback, and a debounce would need stored state this function, on
            // `ReaderView`, cannot add without crossing the line cap; raise this ceiling if a
            // profile ever shows it costing something.
            .onPreferenceChange(PageFramePreferenceKey.self) { frames in
                saveScrollProgress(frames, axis: axis)
            }
            // Once, when Scroll is what the reader opens into: restores the fraction
            // through the current page that the last session left off at. Reads
            // `model.currentIndex` rather than `displayIndex`, so it does not race
            // `pages(in:)`'s own `.onAppear` for which sets first.
            //
            // Keyed on the page having decoded: until then it is a placeholder whose
            // length is a guess, and a fraction of the guess is not where the reader was.
            .task(id: model.image(at: model.currentIndex) != nil) {
                restoreScrollProgress(with: proxy, axis: axis)
            }
        }
    }

    /// One page's frame in the scroll's coordinate space, reported for ``ScrollProgress``.
    private func frameReport(of displayIndex: Int) -> some View {
        GeometryReader { geometry in
            Color.clear.preference(
                key: PageFramePreferenceKey.self,
                value: ScrollFrames(pages: [displayIndex: geometry.frame(in: .named(Self.scrollSpace))])
            )
        }
    }

    /// Scrolls back to where the last session left the current page, once it has decoded.
    private func restoreScrollProgress(with proxy: ScrollViewProxy, axis: ScrollAxis) {
        let page = model.currentIndex
        guard model.image(at: page) != nil,
              let fraction = model.takeScrollRestore(forPage: page), fraction > 0
        else { return }
        proxy.scrollTo(
            displayIndex(forModel: page),
            anchor: ScrollProgress.anchor(forFraction: fraction, axis: axis)
        )
    }

    /// The pages with the end slot on the side the reading order ends: after them in
    /// left-to-right, before them under right-to-left. See `endSlot`.
    @ViewBuilder
    func withEndSlot(_ pages: some View, _ end: some View) -> some View {
        if isRightToLeft {
            end
            pages
        } else {
            pages
            end
        }
    }

    /// Where the current page's own frame is reported, for ``ScrollProgress``.
    static var scrollSpace: String { "ReaderContainers.scroll" }

    /// Remembers where a continuous scroll sits within its current page.
    private func saveScrollProgress(_ frames: ScrollFrames, axis: ScrollAxis) {
        guard let frame = frames.pages[displayIndex], frames.viewport != .zero else { return }
        model.saveScrollFraction(
            ScrollProgress.fraction(pageFrame: frame, viewport: frames.viewport, axis: axis),
            onPage: modelIndex(forDisplay: displayIndex)
        )
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
            singlePage(at: spread?.leading ?? 0, onTap: tapHandler())
        }
    }

    /// One half of a spread, with its taps put back into screen terms.
    ///
    /// The halves are equal, so a tap in one is a tap in the same place on a screen twice
    /// as wide. Without this the edge zones would be measured against half the screen and
    /// the middle of a spread would turn the page.
    private func half(at index: Int, isFirstOnScreen: Bool) -> some View {
        singlePage(
            at: index,
            onTap: tapHandler { location, size in
                (
                    CGPoint(x: isFirstOnScreen ? location.x : location.x + size.width, y: location.y),
                    CGSize(width: size.width * 2, height: size.height)
                )
            }
        )
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func singlePage(at index: Int, onTap: @escaping (CGPoint, CGSize) -> Void) -> some View {
        if model.pages.indices.contains(index) {
            PageView(
                // The zoom-resolution copy when one is held, the display one otherwise.
                image: model.displayImage(at: index),
                isUnavailable: model.isUnavailable(at: index),
                codecName: model.codecName(at: index),
                pageID: model.pages[index].path,
                label: Text("reader.pageLabel \(index + 1) \(model.pages.count)", bundle: .module),
                fit: fit,
                // D6: only fit-to-width carries a pinch forward; every other mode
                // still resets on a turn, which `nil` here leaves unchanged.
                carriedZoomScale: fit == .width ? carriedZoomScale : nil,
                isRightToLeft: isRightToLeft,
                adjustments: trimming(at: index),
                onTap: onTap,
                onZoom: { scale, overFit in
                    Task { await model.holdZoom(scale, at: index) }
                    if fit == .width { carriedZoomScale = overFit }
                },
                decoration: decoration(at: index),
                onSelect: selectionHandler(at: index)
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
            codecName: model.codecName(at: index),
            label: Text("reader.pageLabel \(index + 1) \(model.pages.count)", bundle: .module),
            axis: axis,
            adjustments: trimming(at: index),
            onTap: tapHandler(),
            placeholderRatio: PagePlaceholder.ratio(nearest: index, among: model.decodedRatios)
        )
    }

    /// The series' adjustments, with the trim off for a page the reader excused.
    ///
    /// And off for every page of a PDF that carries text. Margin trimming exists for a *scan*
    /// — `comic-reader` asks for "uniform white or black margins ... trimmed per page" — and a
    /// PDF with a real text layer is not one: its margins are the publisher's typography.
    /// Trimming them would also move the words out from under the marks a reader put on them,
    /// because a highlight is normalised to the whole page and the trimmed raster is not it.
    func trimming(at index: Int) -> ImageAdjustments {
        adjustments.trimmingBorders(!uncropped.contains(index) && pdfText == nil)
    }

    /// Short enough not to read as an animation, which is the point of the name.
    ///
    /// `page-transitions` uses Fast fade as the Reduce Motion substitute as well as a
    /// mode in its own right, so it must not become the thing it replaces.
    static let fadeDuration = 0.14
}
