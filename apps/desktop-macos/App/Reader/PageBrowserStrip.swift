import DesignSystem
import ReaderFeature
import SwiftUI

/// The page browser: every page as a carousel that settles with one page in the centre.
///
/// `comic-reader`, *Thumbnail browser* and *Page browser*: the current page opens centred,
/// larger and marked as current, each page with its number under it; scrolling the carousel
/// does not move the reader and a click on a page jumps there; dragging the slider centres
/// the page it points at; the centred page's chapter is named above, a chapter's first page
/// carries a badge and the slider a tick; it runs right to left for a right-to-left
/// publication; Reduce Motion drops the scaling and leaves the outline; VoiceOver hears the
/// page number, the chapter and which page is current. Opened from the Reader menu (⌘T) or
/// the contents menu, above the foot of the chrome.
struct PageBrowserStrip: View {
    static let cellHeight: CGFloat = 120
    static let cellWidth: CGFloat = 84

    @Environment(\.theme) private var theme

    let state: ReaderState
    /// The page the slider points at while it is dragged.
    let centred: Int?

    @State private var centredID: Int?

    private var model: ReaderModel { state.model }

    var body: some View {
        VStack(spacing: 8) {
            if let label = ReaderChapters.label(at: centredID ?? state.shownIndex, markers: state.markers) {
                Text(label.text).scaledFont(.callout, weight: .semibold).storyArcGlassText(.primary)
                    .accessibilityAddTraits(.isHeader)
            }
            GeometryReader { geometry in
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 14) {
                        ForEach(model.pages.indices, id: \.self) { index in cell(index).id(index) }
                    }
                    .scrollTargetLayout()
                    .padding(.vertical, 18)
                }
                .scrollIndicators(.never)
                .contentMargins(.horizontal, max(0, (geometry.size.width - Self.cellWidth) / 2), for: .scrollContent)
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $centredID, anchor: .center)
                .environment(\.layoutDirection, state.isRightToLeft ? .rightToLeft : .leftToRight)
            }
            .frame(height: Self.cellHeight * 1.25 + 56)
        }
        .padding(.top, 10)
        .storyArcGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onAppear { centredID = state.shownIndex }
        .onChange(of: centred) { _, page in
            if let page { withAnimation(state.reduceMotion ? nil : .easeOut(duration: 0.15)) { centredID = page } }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("desktop.reader.pageBrowser"))
    }

    private func cell(_ index: Int) -> some View {
        let isCentred = index == (centredID ?? state.shownIndex)
        let isCurrent = index == state.shownIndex
        return Button { state.jump(to: index) } label: {
            VStack(spacing: 14) {
                PageThumbnail(model: model, index: index, height: Self.cellHeight, showsNumber: false)
                    .overlay {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(isCentred ? theme.accent : .clear, lineWidth: 2)
                    }
                    .overlay(alignment: .topLeading) { badge(index) }
                    .scaleEffect(isCentred && !state.reduceMotion ? 1.15 : 1)
                    .animation(state.reduceMotion ? nil : .easeOut(duration: 0.15), value: isCentred)
                VStack(spacing: 3) {
                    Text(verbatim: "\(index + 1)")
                        .scaledFont(.caption, weight: isCurrent ? .bold : .regular)
                        .monospacedDigit()
                        .storyArcGlassText(.primary)
                    Capsule().fill(isCurrent ? theme.accent : .clear).frame(width: 18, height: 3)
                }
            }
            .frame(width: Self.cellWidth)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(spoken(index)))
        .accessibilityValue(isCurrent ? Text("desktop.reader.currentPage") : Text(verbatim: ""))
        .accessibilityAddTraits(isCurrent ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private func badge(_ index: Int) -> some View {
        if let badge = ReaderChapters.badge(at: index, markers: state.markers) {
            Text(verbatim: badge)
                .scaledFont(.caption2, weight: .bold)
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(theme.accent, in: Capsule())
                .foregroundStyle(.white)
                .padding(4)
        }
    }

    /// "Page 5, Chapter 2": the number and, with markers, the chapter's name.
    private func spoken(_ index: Int) -> String {
        var parts = [String(localized: "desktop.reader.pageNumber \(index + 1)")]
        if let chapter = ReaderChapters.label(at: index, markers: state.markers) { parts.append(chapter.text) }
        return parts.joined(separator: ", ")
    }
}

/// A page's thumbnail, decoded on demand through `ReaderModel.thumbnail(at:)`, or a quiet
/// placeholder while it is not there.
struct PageThumbnail: View {
    @Environment(\.theme) private var theme

    let model: ReaderModel
    let index: Int
    let height: CGFloat
    let showsNumber: Bool

    @State private var image: CGImage?

    var body: some View {
        VStack(spacing: 4) {
            Group {
                if let image {
                    Image(decorative: image, scale: 1).resizable().scaledToFit()
                } else {
                    RoundedRectangle(cornerRadius: 3).fill(theme.palette.surfaceSunken)
                        .aspectRatio(2.0 / 3.0, contentMode: .fit)
                }
            }
            .frame(height: height)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            if showsNumber {
                Text(verbatim: "\(index + 1) / \(model.pages.count)").scaledFont(.caption).monospacedDigit()
            }
        }
        .task(id: index) { image = await model.thumbnail(at: index) }
    }
}
