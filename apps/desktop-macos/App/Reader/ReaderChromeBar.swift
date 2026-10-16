import DesignSystem
import ReaderFeature
import StoryArcCore
import SwiftUI

/// The reader's chrome: a glass bar at the foot with the page slider and the count, and a
/// glass cluster at the head with the layout and zoom menus.
///
/// `docs/designs/desktop/macos.md` section 4. Glass is untinted and only here; it fades
/// after the pointer rests (`ReaderWindow`). Reduce Transparency falls back inside
/// `storyArcGlass`.
struct ReaderChromeBar: View {
    @Environment(\.theme) private var theme

    let model: ReaderModel
    let layout: SpreadLayout
    @Binding var spreadMode: SpreadMode
    @Binding var zoom: ZoomModel
    let onJump: (Int) -> Void

    @State private var scrubbing: Double?

    /// The page the slider points at, counted from one, while it is dragged or at rest.
    private var shownPage: Int { Int((scrubbing ?? Double(model.currentIndex)).rounded()) + 1 }

    var body: some View {
        VStack {
            HStack {
                Spacer()
                GlassEffectContainer {
                    HStack(spacing: 4) {
                        layoutMenu
                        zoomMenu
                    }
                }
                .storyArcGlass()
                .padding(16)
            }
            Spacer()
            footer
                .storyArcGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal, 48)
                .padding(.bottom, 20)
        }
    }

    private var footer: some View {
        HStack(spacing: 16) {
            Text(counter).monospacedDigit().storyArcGlassText(.primary)
                .accessibilityLabel(Text("desktop.reader.pageLabel \(model.currentIndex + 1) \(model.pages.count)"))
            if model.pages.count > 1 {
                Slider(
                    value: Binding(get: { scrubbing ?? Double(model.currentIndex) }, set: { scrubbing = $0 }),
                    in: 0...Double(max(0, model.pages.count - 1)),
                    step: 1
                ) {
                    Text("desktop.reader.slider")
                } onEditingChanged: { editing in
                    if !editing, let page = scrubbing {
                        onJump(Int(page.rounded()))
                        scrubbing = nil
                    }
                }
                .accessibilityValue(Text("desktop.reader.pageLabel \(shownPage) \(model.pages.count)"))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    /// "12–13 / 32" for a pair, "12 / 32" for one page.
    private var counter: String {
        let slot = layout[layout.slot(containing: model.currentIndex)]
        let pages = (slot?.pages ?? [model.currentIndex]).map { $0 + 1 }
        let shown = pages.count == 2 ? "\(pages.min() ?? 0)–\(pages.max() ?? 0)" : "\(pages.first ?? 1)"
        return "\(shown) / \(model.pages.count)"
    }

    private var layoutMenu: some View {
        Menu {
            Picker(selection: $spreadMode) {
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
    }

    private var zoomMenu: some View {
        Menu {
            Button { zoom = zoom.zoomedIn() } label: { Text("desktop.menu.zoomIn") }
            Button { zoom = zoom.zoomedOut() } label: { Text("desktop.menu.zoomOut") }
            Button { zoom = zoom.fitted() } label: { Text("desktop.menu.fitPage") }
        } label: {
            Label("desktop.reader.zoom", systemImage: "plus.magnifyingglass")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .padding(8)
        .help(Text("desktop.reader.zoom"))
    }
}
