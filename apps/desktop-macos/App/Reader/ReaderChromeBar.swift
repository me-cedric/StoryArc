import DesignSystem
import ReaderFeature
import StoryArcCore
import SwiftUI

/// The reader's chrome: a glass cluster at the head with the contents, adjustments, page
/// mode, layout and zoom menus, and a glass bar at the foot with the page slider, the count,
/// a thumbnail while the slider is dragged, the way back after a jump, and the page browser
/// above it when it is open.
///
/// `docs/designs/desktop/macos.md` section 4. Glass is untinted and only here; it fades
/// after the pointer rests (`ReaderWindow`). Reduce Transparency falls back inside
/// `storyArcGlass`.
struct ReaderChromeBar: View {
    @Environment(\.theme) private var theme

    let state: ReaderState
    @Binding var isAdjusting: Bool
    let onChapter: (Int) -> Void

    @State private var scrubbing: Double?

    private var model: ReaderModel { state.model }

    var body: some View {
        VStack {
            HStack {
                Spacer()
                GlassEffectContainer {
                    // Icons with their names in the tooltip and for VoiceOver: five worded menus
                    // reached across the artwork, which is what chrome must not do.
                    HStack(spacing: 4) {
                        contentsMenu
                        adjustButton
                        modeMenu
                        layoutMenu
                        zoomMenu
                    }
                    .labelStyle(.iconOnly)
                }
                .storyArcGlass()
                .padding(16)
            }
            Spacer()
            if state.isBrowsingPages, model.pages.count > 1 {
                PageBrowserStrip(state: state, centred: scrubbing.map { Int($0.rounded()) })
                    .padding(.horizontal, 48)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            footer
                .storyArcGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal, 48)
                .padding(.bottom, 20)
        }
    }

    // MARK: - The foot

    private var footer: some View {
        HStack(spacing: 16) {
            Text(counter).monospacedDigit().storyArcGlassText(.primary)
                .accessibilityLabel(Text("desktop.reader.pageLabel \(state.shownIndex + 1) \(model.pages.count)"))
            if model.pages.count > 1 {
                ReaderSlider(state: state, scrubbing: $scrubbing)
            }
            if let back = state.returnIndex {
                Button { state.goBack() } label: {
                    Label("desktop.reader.backToPage \(back + 1)", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(.borderless)
                .help(Text("desktop.reader.backToPage \(back + 1)"))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    /// "12–13 / 32" for a pair, "12 / 32" for one page.
    private var counter: String {
        let layout = state.layout
        let slot = layout[layout.slot(containing: state.shownIndex)]
        let pages = (slot?.pages ?? [state.shownIndex]).map { $0 + 1 }
        let shown = pages.count == 2 ? "\(pages.min() ?? 0)–\(pages.max() ?? 0)" : "\(pages.first ?? 1)"
        return "\(shown) / \(model.pages.count)"
    }

    // MARK: - The head

    private var contentsMenu: some View {
        Menu {
            Button { state.isBrowsingPages.toggle() } label: {
                Text(state.isBrowsingPages ? "desktop.reader.hidePages" : "desktop.menu.showPages")
            }
            Divider()
            Button { onChapter(-1) } label: { Text("desktop.menu.previousChapter") }
            Button { onChapter(1) } label: { Text("desktop.menu.nextChapter") }
        } label: {
            Label("desktop.reader.contents", systemImage: "list.bullet")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .padding(8)
        .help(Text("desktop.reader.contents"))
    }

    private var adjustButton: some View {
        Button { isAdjusting.toggle() } label: {
            Label("desktop.reader.adjust", systemImage: "slider.horizontal.3")
        }
        .buttonStyle(.borderless)
        .padding(8)
        .help(Text("desktop.menu.adjustImage"))
        .popover(isPresented: $isAdjusting, arrowEdge: .bottom) {
            AdjustmentsPanel(state: state)
        }
    }

    private var modeMenu: some View {
        Menu {
            TransitionMenuItems(state: state)
        } label: {
            Label("desktop.reader.pageMode", systemImage: "book.pages")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .padding(8)
        .help(Text("desktop.reader.pageMode"))
    }

    private var layoutMenu: some View {
        Menu {
            Picker(selection: Binding(get: { state.spreadMode }, set: { state.spreadMode = $0 })) {
                Text("desktop.reader.layout.automatic").tag(SpreadMode.automatic)
                Text("desktop.menu.singlePage").tag(SpreadMode.single)
                Text("desktop.menu.twoPages").tag(SpreadMode.double)
            } label: { EmptyView() }
            .pickerStyle(.inline)
            Divider()
            Toggle(isOn: Binding(get: { MacSettings.shared.coverAlone }, set: { MacSettings.shared.coverAlone = $0 })) {
                Text("desktop.reader.coverAlone")
            }
        } label: {
            Label("desktop.reader.layout", systemImage: "rectangle.split.2x1")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .padding(8)
        .help(Text("desktop.reader.layout"))
        .disabled(state.isScrolling)
    }

    private var zoomMenu: some View {
        Menu {
            Button { state.zoom = state.zoom.zoomedIn() } label: { Text("desktop.menu.zoomIn") }
            Button { state.zoom = state.zoom.zoomedOut() } label: { Text("desktop.menu.zoomOut") }
            Divider()
            FitMenuItems(state: state)
        } label: {
            Label("desktop.reader.zoom", systemImage: "plus.magnifyingglass")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .padding(8)
        .help(Text("desktop.reader.zoom"))
        .disabled(state.isScrolling)
    }
}

/// The page slider: mirrored for a right-to-left publication, a tick at each chapter's start,
/// and a thumbnail of the target page above the thumb while it is dragged.
///
/// `comic-reader`, *Page slider with thumbnails*: releasing jumps there, and the way back
/// is the foot's *Back to page* button.
struct ReaderSlider: View {
    @Environment(\.theme) private var theme

    let state: ReaderState
    @Binding var scrubbing: Double?

    private var count: Int { state.model.pages.count }
    private var shownPage: Int { Int((scrubbing ?? Double(state.shownIndex)).rounded()) }

    var body: some View {
        Slider(
            value: Binding(get: { scrubbing ?? Double(state.shownIndex) }, set: { scrubbing = $0 }),
            in: 0...Double(max(0, count - 1)), step: 1
        ) {
            Text("desktop.reader.slider")
        } onEditingChanged: { editing in
            if !editing, let page = scrubbing {
                state.jump(to: Int(page.rounded()))
                scrubbing = nil
            }
        }
        .labelsHidden()
        .accessibilityValue(Text("desktop.reader.pageLabel \(shownPage + 1) \(count)"))
        .environment(\.layoutDirection, state.isRightToLeft ? .rightToLeft : .leftToRight)
        .background(alignment: .bottom) { ticks }
        .overlay(alignment: .bottomLeading) { preview }
    }

    /// Where along the track a page sits, from the left, mirrored right to left.
    private func across(_ fraction: Double, width: CGFloat) -> CGFloat {
        let along = state.isRightToLeft ? 1 - fraction : fraction
        return 8 + along * (width - 16)
    }

    private var ticks: some View {
        GeometryReader { geometry in
            ForEach(ReaderChapters.tickFractions(markers: state.markers, pageCount: count), id: \.self) { fraction in
                Capsule().fill(theme.palette.textSecondary)
                    .frame(width: 2, height: 6)
                    .offset(x: across(fraction, width: geometry.size.width) - 1, y: geometry.size.height - 2)
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var preview: some View {
        if let scrubbing, !state.isBrowsingPages {
            GeometryReader { geometry in
                let fraction = count > 1 ? scrubbing / Double(count - 1) : 0
                PageThumbnail(model: state.model, index: shownPage, height: 120, showsNumber: true)
                    .padding(6)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .offset(x: across(fraction, width: geometry.size.width) - 46, y: -150)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}
