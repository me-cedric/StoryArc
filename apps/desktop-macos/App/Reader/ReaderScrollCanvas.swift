import DesignSystem
import ReaderFeature
import StoryArcCore
import SwiftUI

/// The continuous scroll: every page stitched into one strip along the scroll axis.
///
/// `comic-reader`, *Continuous scroll* and *Scroll axis for webtoons*, with `page-transitions`'
/// Scroll mode. Pages meet with no gap unless the reader asks for a separator; the axis is
/// the one the publication implies (vertical for a strip of tall pages) until the reader
/// picks the other row; the page in view is the reader's position, written as it changes;
/// and where the strip sits within that page is remembered (`ReaderModel.saveScrollFraction`)
/// and restored exactly when the publication opens again. The plain wheel scrolls the strip.
struct ReaderScrollCanvas: View {
    @Environment(\.theme) private var theme

    let state: ReaderState
    let onPointerMoved: () -> Void

    @State private var position = ScrollPosition(idType: Int.self)
    @State private var visible: Int?
    @State private var restored = false

    private var model: ReaderModel { state.model }
    private var axis: ScrollAxis { state.choices.effective.scrollAxis ?? .vertical }

    var body: some View {
        GeometryReader { geometry in
            ScrollView(axis == .vertical ? .vertical : .horizontal) {
                strip(viewport: geometry.size)
                    .scrollTargetLayout()
            }
            .scrollPosition($position, anchor: .topLeading)
            .onScrollTargetVisibilityChange(idType: Int.self, threshold: 0.3) { ids in
                visible = ids.min()
            }
            .onScrollGeometryChange(for: Double.self) { geometry in
                axis == .vertical ? geometry.contentOffset.y : geometry.contentOffset.x
            } action: { _, offset in
                remember(offset: offset, viewport: geometry.size)
            }
            .environment(\.layoutDirection, axis == .horizontal && state.isRightToLeft ? .rightToLeft : .leftToRight)
            .onContinuousHover { phase in if case .active = phase { onPointerMoved() } }
            .onChange(of: visible) { _, index in
                if let index, index != state.shownIndex { state.go(to: index) }
            }
            .onChange(of: state.shownIndex) { _, index in
                // A key, the slider or the browser moved the reader: bring that page into view.
                guard visible != index else { return }
                withAnimation(state.reduceMotion ? nil : .easeOut) { position.scrollTo(id: index) }
            }
            .onChange(of: model.pages.count, initial: true) { restore(viewport: geometry.size) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("desktop.reader.pageLabel \(state.shownIndex + 1) \(model.pages.count)"))
    }

    @ViewBuilder
    private func strip(viewport: CGSize) -> some View {
        let gap: CGFloat = model.settings.showsPageSeparator ? 4 : 0
        if axis == .vertical {
            LazyVStack(spacing: gap) {
                ForEach(model.pages.indices, id: \.self) { index in
                    page(index).frame(width: min(viewport.width, 900)).id(index)
                }
            }
            .frame(maxWidth: .infinity)
        } else {
            LazyHStack(spacing: gap) {
                ForEach(model.pages.indices, id: \.self) { index in
                    page(index).frame(height: viewport.height).id(index)
                }
            }
        }
    }

    @ViewBuilder
    private func page(_ index: Int) -> some View {
        if let image = model.displayImage(at: index) {
            AdjustedPage(image: image, index: index, adjustments: state.adjustments(at: index))
                .accessibilityLabel(Text("desktop.reader.pageLabel \(index + 1) \(model.pages.count)"))
        } else {
            PagePlaceholder(model: model, index: index)
        }
    }

    /// Where the strip sits within the page in view, as a fraction of that page.
    private func remember(offset: Double, viewport: CGSize) {
        guard restored, let index = visible ?? Optional(state.shownIndex) else { return }
        let extent = pageExtent(index, viewport: viewport)
        guard extent > 0 else { return }
        let start = (0..<index).reduce(0.0) { $0 + pageExtent($1, viewport: viewport) }
        let fraction = min(max((offset - start) / extent, 0), 1)
        model.saveScrollFraction(fraction, onPage: index)
    }

    /// Back to the page and the place within it that the last session left.
    private func restore(viewport: CGSize) {
        guard !restored, !model.pages.isEmpty else { return }
        restored = true
        let index = state.shownIndex
        if let fraction = model.takeScrollRestore(forPage: index) {
            let start = (0..<index).reduce(0.0) { $0 + pageExtent($1, viewport: viewport) }
            let offset = start + fraction * pageExtent(index, viewport: viewport)
            position.scrollTo(point: axis == .vertical ? CGPoint(x: 0, y: offset) : CGPoint(x: offset, y: 0))
        } else {
            position.scrollTo(id: index, anchor: .topLeading)
        }
    }

    /// A page's length along the axis, from its decoded size, or a portrait page's while it
    /// is not decoded.
    private func pageExtent(_ index: Int, viewport: CGSize) -> Double {
        let gap = model.settings.showsPageSeparator ? 4.0 : 0
        let ratio: Double = model.displayImage(at: index).map { Double($0.height) / Double(max(1, $0.width)) } ?? 1.5
        if axis == .vertical { return min(viewport.width, 900) * ratio + gap }
        return viewport.height / ratio + gap
    }
}
