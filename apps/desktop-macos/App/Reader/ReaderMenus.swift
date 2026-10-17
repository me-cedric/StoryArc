import AppKit
import ReaderFeature
import StoryArcCore
import SwiftUI

/// The page mode rows: every transition, the ones that cannot run marked with their reason,
/// the scroll's page separator, and the one sentence for the curl the Mac does not have yet.
struct TransitionMenuItems: View {
    let state: ReaderState

    var body: some View {
        let choices = state.choices
        ForEach(TransitionMenu.rows(choices)) { row in
            Toggle(isOn: Binding(get: { row.isChosen }, set: { if $0 { state.choose(row.mode) } })) {
                Text(LocalizedStringKey(row.titleKey))
                if let reason = row.reasonKey {
                    Text(LocalizedStringKey(reason))
                }
            }
            .disabled(row.reasonKey != nil)
        }
        if state.isScrolling {
            Divider()
            Toggle(isOn: Binding(
                get: { state.model.settings.showsPageSeparator }, set: { state.choosePageSeparator($0) }
            )) {
                Text("desktop.transition.separator")
            }
        }
        if let absent = TransitionMenu.absentCurlKey(choices) {
            Divider()
            Text(LocalizedStringKey(absent))
        }
    }
}

/// The fit rows, the chosen one checked.
struct FitMenuItems: View {
    let state: ReaderState

    var body: some View {
        ForEach(PageFit.allCases, id: \.self) { fit in
            Toggle(isOn: Binding(
                get: { state.model.settings.fit == fit }, set: { if $0 { state.applyFit(fit) } }
            )) {
                Text(LocalizedStringKey(fit.titleKey))
            }
        }
    }
}

extension PageFit {
    var titleKey: String {
        switch self {
        case .screen: "desktop.menu.fitPage"
        case .width: "desktop.menu.fitWidth"
        case .height: "desktop.menu.fitHeight"
        case .original: "desktop.menu.originalSize"
        }
    }
}

/// The context menu of a page: `docs/designs/desktop/macos.md` section 7.
struct ReaderPageMenu: View {
    let state: ReaderState
    let spread: Spread

    var body: some View {
        Menu { FitMenuItems(state: state) } label: { Text("desktop.reader.fit") }
        Button { state.zoom = state.zoom.zoomedIn() } label: { Text("desktop.menu.zoomIn") }
        Button { state.zoom = state.zoom.zoomedOut() } label: { Text("desktop.menu.zoomOut") }
        Divider()
        Menu { TransitionMenuItems(state: state) } label: { Text("desktop.reader.pageMode") }
        Menu {
            Button { state.choose(ReadingDirection.leftToRight) } label: { Text("desktop.reader.leftToRight") }
            Button { state.choose(ReadingDirection.rightToLeft) } label: { Text("desktop.reader.rightToLeft") }
        } label: { Text("desktop.reader.direction") }
        if state.adjustments.cropsBorders {
            Toggle(isOn: Binding(
                get: { !state.uncropped.contains(spread.leading) },
                set: { state.setCropsPage(spread.leading, $0) }
            )) {
                Text("desktop.adjust.cropThisPage")
            }
        }
        Divider()
        Button { copyPage(spread.leading) } label: { Text("desktop.reader.copyImage") }
            .disabled(state.model.displayImage(at: spread.leading) == nil)
    }

    private func copyPage(_ index: Int) {
        guard let image = state.model.displayImage(at: index) else { return }
        let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([nsImage])
    }
}
