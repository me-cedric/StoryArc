import AppKit
import DesignSystem
import ReaderFeature
import StoryArcCore
import SwiftUI

/// The page surface of a Mac reader: the spread, the zoom, the drag and the click zones.
///
/// SwiftUI over `ReaderModel`'s decoded pages rather than `ZoomablePage`, which is UIKit.
/// Pinch is `MagnifyGesture`; Command and the wheel, and a plain wheel turn, come through a
/// local event monitor because SwiftUI has no wheel modifier; a double click toggles the
/// zoom; a drag pans a zoomed page and slides a fitted one. Tasks 2.12 to 2.15.
struct ReaderCanvas: View {
    @Environment(\.theme) private var theme

    let model: ReaderModel
    @Binding var zoom: ZoomModel
    let layout: SpreadLayout
    let viewport: CGSize
    let reduceMotion: Bool
    let zonesOn: Bool
    let onTurn: (Int) -> Void
    let onToggleChrome: () -> Void
    let onPointerMoved: () -> Void

    @State private var baseZoom: ZoomModel?
    @State private var dragTranslation: CGFloat = 0
    @State private var wheelMonitor: WheelMonitor?

    private var isRightToLeft: Bool { model.readingDirection == .rightToLeft }

    var body: some View {
        let spread = layout[layout.slot(containing: model.currentIndex)] ?? Spread(leading: model.currentIndex)
        ZStack {
            spreadView(spread)
                .scaleEffect(zoom.scale)
                .offset(x: zoom.offset.width + slideOffset, y: zoom.offset.height)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: zoom.scale)
        }
        .frame(width: viewport.width, height: viewport.height)
        .clipped()
        .contentShape(Rectangle())
        .gesture(doubleClick.exclusively(before: singleClick))
        .simultaneousGesture(drag)
        .simultaneousGesture(magnify)
        .onContinuousHover { phase in if case .active = phase { onPointerMoved() } }
        .contextMenu { pageMenu(spread) }
        .onAppear { installWheelMonitor() }
        .onDisappear { wheelMonitor?.remove(); wheelMonitor = nil }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("desktop.reader.pageLabel \(spread.leading + 1) \(model.pages.count)"))
    }

    /// The slide while a fitted page is dragged. The curl is wave 5.
    private var slideOffset: CGFloat { zoom.isZoomed ? 0 : dragTranslation }

    // MARK: - The spread

    private func spreadView(_ spread: Spread) -> some View {
        HStack(spacing: 0) {
            ForEach(SpreadDecision.screenOrder(spread, isRightToLeft: isRightToLeft), id: \.self) { index in
                page(index, share: spread.isPair ? 0.5 : 1)
            }
        }
    }

    @ViewBuilder
    private func page(_ index: Int, share: CGFloat) -> some View {
        let slotWidth = viewport.width * share
        if let image = model.displayImage(at: index) {
            Image(decorative: image, scale: 1)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(maxWidth: slotWidth, maxHeight: viewport.height)
        } else {
            // *A page that has not loaded*: a quiet placeholder, never a spinner over the artwork.
            RoundedRectangle(cornerRadius: 2)
                .fill(theme.palette.surfaceSunken)
                .aspectRatio(2.0 / 3.0, contentMode: .fit)
                .frame(maxWidth: slotWidth, maxHeight: viewport.height)
                .overlay {
                    if model.isUnavailable(at: index) {
                        Group {
                            if let codec = model.codecName(at: index) {
                                Text("desktop.reader.pageUndecodable \(codec)")
                            } else {
                                Text("desktop.reader.pageUnreadable")
                            }
                        }
                        .scaledFont(.callout).foregroundStyle(.secondary).padding()
                    }
                }
        }
    }

    // MARK: - Gestures

    private var singleClick: some Gesture {
        SpatialTapGesture().onEnded { value in
            let zone = ClickZones.zone(atX: value.location.x, width: viewport.width, zonesOn: zonesOn && !zoom.isZoomed)
            let step = ClickZones.step(for: zone, isRightToLeft: isRightToLeft)
            if step == 0 { onToggleChrome() } else { onTurn(step) }
        }
    }

    private var doubleClick: some Gesture {
        SpatialTapGesture(count: 2).onEnded { _ in
            zoom = zoom.doubleClicked().settled(fittedSize: fittedSize, viewport: viewport)
        }
    }

    private var magnify: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let base = baseZoom ?? zoom
                baseZoom = base
                zoom = base.magnified(by: value.magnification).settled(fittedSize: fittedSize, viewport: viewport)
            }
            .onEnded { _ in baseZoom = nil }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                if zoom.isZoomed {
                    let delta = CGSize(width: value.translation.width - dragTranslation, height: 0)
                    _ = delta
                    zoom = zoom.panned(
                        by: CGSize(width: value.velocity.width / 60, height: value.velocity.height / 60),
                        fittedSize: fittedSize, viewport: viewport
                    )
                } else {
                    dragTranslation = value.translation.width
                }
            }
            .onEnded { value in
                defer { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { dragTranslation = 0 } }
                guard !zoom.isZoomed else { return }
                let step = DragTurn.step(
                    translation: value.translation.width, width: viewport.width, isRightToLeft: isRightToLeft
                )
                if step != 0 { onTurn(step) }
            }
    }

    /// The page's size at fit, which the zoom is a multiple of.
    private var fittedSize: CGSize {
        guard let image = model.displayImage(at: model.currentIndex) else { return viewport }
        let imageSize = CGSize(width: image.width, height: image.height)
        let scale = min(viewport.width / imageSize.width, viewport.height / imageSize.height)
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }

    // MARK: - The wheel

    private func installWheelMonitor() {
        guard wheelMonitor == nil else { return }
        wheelMonitor = WheelMonitor { event in
            if event.modifierFlags.contains(.command) {
                zoom = zoom.wheeled(by: event.scrollingDeltaY / 10).settled(fittedSize: fittedSize, viewport: viewport)
                return true
            }
            if zoom.isZoomed {
                let delta = CGSize(width: event.scrollingDeltaX, height: event.scrollingDeltaY)
                zoom = zoom.panned(by: delta, fittedSize: fittedSize, viewport: viewport)
                return true
            }
            // *Plain wheel on a page that fits*: the wheel turns the page in a paged reader.
            if let step = WheelTurn.step(
                deltaY: event.scrollingDeltaY, deltaX: event.scrollingDeltaX,
                phase: event.phase, momentum: event.momentumPhase
            ) {
                onTurn(isRightToLeft && event.scrollingDeltaX != 0 ? -step : step)
                return true
            }
            return false
        }
    }

    // MARK: - The context menu

    @ViewBuilder
    private func pageMenu(_ spread: Spread) -> some View {
        Button { zoom = zoom.fitted() } label: { Text("desktop.menu.fitPage") }
        Button { zoom = zoom.zoomedIn() } label: { Text("desktop.menu.zoomIn") }
        Button { zoom = zoom.zoomedOut() } label: { Text("desktop.menu.zoomOut") }
        Divider()
        Menu {
            Button { model.choose(ReadingDirection.leftToRight) } label: { Text("desktop.reader.leftToRight") }
            Button { model.choose(ReadingDirection.rightToLeft) } label: { Text("desktop.reader.rightToLeft") }
        } label: { Text("desktop.reader.direction") }
        Button { copyPage(spread.leading) } label: { Text("desktop.reader.copyImage") }
            .disabled(model.displayImage(at: spread.leading) == nil)
    }

    private func copyPage(_ index: Int) {
        guard let image = model.displayImage(at: index) else { return }
        let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([nsImage])
    }
}

/// One wheel notch to one turn: a flick's first event turns, its momentum does not.
enum WheelTurn {
    static let threshold: CGFloat = 4

    static func step(deltaY: CGFloat, deltaX: CGFloat, phase: NSEvent.Phase, momentum: NSEvent.Phase) -> Int? {
        guard momentum == [] || momentum == .began else { return nil }
        guard phase == [] || phase == .began || phase == .changed else { return nil }
        let delta = abs(deltaX) > abs(deltaY) ? deltaX : deltaY
        guard abs(delta) >= threshold else { return nil }
        return delta < 0 ? 1 : -1
    }
}

/// A local monitor for the wheel over this window, removed with the view.
@MainActor
final class WheelMonitor {
    private var token: Any?
    private var lastTurn = Date.distantPast

    init(handle: @escaping @MainActor (NSEvent) -> Bool) {
        token = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, event.window?.isKeyWindow == true else { return event }
            // One turn per flick: a trackpad sends many events for one gesture.
            if !event.modifierFlags.contains(.command), Date().timeIntervalSince(lastTurn) < 0.35 { return nil }
            let handled = MainActor.assumeIsolated { handle(event) }
            if handled { lastTurn = Date() }
            return handled ? nil : event
        }
    }

    func remove() {
        if let token { NSEvent.removeMonitor(token) }
        token = nil
    }
}
